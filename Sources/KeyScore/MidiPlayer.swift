import CoreMIDI
import Foundation
import os

/// CoreMIDI 가상 소스 "KeyScore" 로 이벤트를 송신한다. 가상악기/외장악기에서 이 소스를 MIDI 입력으로 선택한다.
///
/// 동시성 규칙: 모든 가변 상태는 `queue` 에서만 읽고 쓴다. 공개 메서드는 큐에 작업을 넣기만 하므로 어느 스레드에서
/// 불러도 안전하고, 그래서 `@unchecked Sendable` 이다. actor 를 쓰지 않는 이유는 docs/decisions 참고
/// (실시간 송신은 우선순위가 보장되는 전용 큐와 strict 타이머가 필요하다).
final class MidiPlayer: @unchecked Sendable {
    private struct Message {
        var time: Double
        var status: UInt8
        var d1: UInt8
        var d2: UInt8
    }

    /// 진행 보고 간격(초)과 표시등 콜백 최소 간격(초)
    private static let progressInterval = 0.05
    private static let activityInterval = 0.06
    private static let log = Logger(subsystem: "dev.soomtong.keyscore", category: "midi")

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private let queue = DispatchQueue(label: "keyscore.midi", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    private var messages: [Message] = []
    private var index = 0
    private var startNanos: UInt64 = 0
    private var endSeconds = 0.0
    private var loop = false
    private var active = Set<UInt16>()
    private var usedChannels = Set<UInt8>()
    private var lastProgress = 0.0
    private var lastActivity = -1.0
    private var pedal = false
    /// 재생 회차. stop 알림이 어느 재생에 대한 것인지 구분한다 (정지 직후 새 재생을 시작했을 때 늦게 도착한 알림 무시용).
    private var session = 0

    /// 아래 콜백은 모두 `queue` 에서 불린다. 재생을 시작하기 전에 한 번만 설정한다.
    var onProgress: (@Sendable (Double) -> Void)?
    /// 인자는 끝난 재생의 session (play 가 돌려준 값)
    var onStop: (@Sendable (Int) -> Void)?
    /// Note On 을 보낼 때 호출 (표시등용). activityInterval 보다 자주 부르지 않는다.
    var onActivity: (@Sendable () -> Void)?

    /// 가상 소스를 만들지 못하면 false. 이때 송신은 조용히 무시된다.
    private(set) var isReady = false

    init() {
        var status = MIDIClientCreateWithBlock("KeyScore" as CFString, &client, nil)
        guard status == noErr else {
            Self.log.error("MIDIClientCreate failed: \(status)")
            return
        }
        status = MIDISourceCreateWithProtocol(client, "KeyScore" as CFString, ._1_0, &source)
        guard status == noErr else {
            Self.log.error("MIDISourceCreate failed: \(status)")
            return
        }
        isReady = true
    }

    deinit {
        timer?.cancel()
        if source != 0 { MIDIEndpointDispose(source) }
        if client != 0 { MIDIClientDispose(client) }
    }

    /// 재생을 시작하고 이 재생의 session 번호를 돌려준다. 메시지 목록 작성과 정렬은 송신 큐에서 한다.
    @discardableResult
    func play(_ song: Song, loop: Bool) -> Int {
        let id = nextSession()
        queue.async { [self] in
            stopLocked(notify: false)
            let (msgs, chans) = Self.schedule(song)
            messages = msgs
            usedChannels = chans
            endSeconds = song.totalBeats * 60 / song.bpm
            self.loop = loop
            session = id
            index = 0
            lastProgress = 0
            lastActivity = -1
            if pedal { for ch in chans { sendRaw(0xB0 | ch, 64, 127) } }  // 페달을 밟은 채로 시작
            startNanos = DispatchTime.now().uptimeNanoseconds
            let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
            t.setEventHandler { [weak self] in self?.tick() }
            timer = t
            t.activate()
            arm()
        }
        return id
    }

    /// 서스테인 페달(CC64). 재생 중이면 즉시 보내고, 재생 전이면 다음 재생 시작 때 적용한다.
    func setPedal(_ down: Bool) {
        queue.async { [self] in
            pedal = down
            for ch in usedChannels { sendRaw(0xB0 | ch, 64, down ? 127 : 0) }
        }
    }

    func setLoop(_ value: Bool) {
        queue.async { [self] in loop = value }
    }

    func stop() {
        queue.async { [self] in stopLocked(notify: true) }
    }

    // MARK: 큐 안

    private let sessionLock = OSAllocatedUnfairLock(initialState: 0)

    private func nextSession() -> Int {
        sessionLock.withLock { $0 += 1; return $0 }
    }

    /// Song 을 시각순 메시지 목록으로. 같은 시각이면 Note Off 가 먼저 나가야 같은 음을 다시 칠 수 있다.
    private static func schedule(_ song: Song) -> ([Message], Set<UInt8>) {
        let spb = 60 / song.bpm
        var msgs: [Message] = []
        msgs.reserveCapacity(song.events.count * 2)
        var chans = Set<UInt8>()
        for e in song.events {
            let ch = e.channel & 0x0F
            chans.insert(ch)
            let on = e.start * spb
            let off = max(on + 0.01, (e.start + e.length) * spb - 0.005)
            msgs.append(Message(time: on, status: 0x90 | ch, d1: UInt8(clamping: e.pitch), d2: UInt8(clamping: e.velocity)))
            msgs.append(Message(time: off, status: 0x80 | ch, d1: UInt8(clamping: e.pitch), d2: 0))
        }
        msgs.sort { $0.time != $1.time ? $0.time < $1.time : ($0.status & 0xF0) < ($1.status & 0xF0) }
        return (msgs, chans)
    }

    /// 다음에 깨어날 시각: 다음 메시지, 다음 진행 보고, 곡 끝 중 가장 빠른 것. 1 ms 폴링 대신 필요한 순간에만 깨어난다.
    private func arm() {
        guard let timer else { return }
        // 곡 끝 처리는 메시지를 다 보낸 뒤에만 한다 (마지막 Note Off 가 endSeconds 를 넘겨도 바쁜 대기에 빠지지 않게)
        let nextMessage = index < messages.count ? messages[index].time : Double.infinity
        let finish = index < messages.count ? Double.infinity : endSeconds
        let next = min(nextMessage, lastProgress + Self.progressInterval, finish)
        let deadline = DispatchTime(uptimeNanoseconds: startNanos &+ UInt64(max(0, next) * 1e9))
        timer.schedule(deadline: deadline, repeating: .never, leeway: .microseconds(100))
    }

    private func tick() {
        guard timer != nil else { return }
        var now = Double(DispatchTime.now().uptimeNanoseconds &- startNanos) / 1e9
        var sentNote = false
        while index < messages.count, messages[index].time <= now {
            sentNote = send(messages[index]) || sentNote
            index += 1
        }
        if sentNote, now - lastActivity >= Self.activityInterval {
            lastActivity = now
            onActivity?()
        }
        if now - lastProgress >= Self.progressInterval {
            lastProgress = now
            onProgress?(min(now, endSeconds))
        }
        if index >= messages.count && now >= endSeconds {
            guard loop else { return stopLocked(notify: true) }
            startNanos &+= UInt64(endSeconds * 1e9)
            index = 0
            now -= endSeconds
            lastProgress = 0
            lastActivity = -1
        }
        arm()
    }

    private func stopLocked(notify: Bool) {
        guard let t = timer else { return }
        t.cancel()
        timer = nil
        for ch in usedChannels { sendRaw(0xB0 | ch, 64, 0) }  // 페달을 먼저 떼야 울리던 음이 끊긴다
        for key in active {
            sendRaw(0x80 | UInt8(key >> 8), UInt8(key & 0xFF), 0)
        }
        active.removeAll()
        for ch in usedChannels { sendRaw(0xB0 | ch, 123, 0) }  // All Notes Off
        if notify { onStop?(session) }
    }

    /// Note On 이면 true
    private func send(_ m: Message) -> Bool {
        let key = UInt16(m.status & 0x0F) << 8 | UInt16(m.d1)
        let isOn = m.status & 0xF0 == 0x90
        if isOn { active.insert(key) } else { active.remove(key) }
        sendRaw(m.status, m.d1, m.d2)
        return isOn
    }

    private func sendRaw(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) {
        guard isReady else { return }
        // UMP MIDI 1.0 Channel Voice: type 2, group 0
        var word = UInt32(0x2) << 28 | UInt32(status) << 16 | UInt32(d1) << 8 | UInt32(d2)
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &word)
        MIDIReceivedEventList(source, &list)
    }
}
