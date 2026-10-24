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
    /// MIDI Clock(0xF8) 은 4분음표당 24 펄스, Song Position Pointer 단위(16분음표)는 6 펄스
    static let clocksPerBeat = 24
    private static let clocksPerSixteenth = 6
    /// Start/Continue 와 첫 Clock 사이 간격(초). MIDI 1.0 은 수신 측이 준비할 시간으로 1 ms 이상을 권한다.
    private static let startLead = 0.001
    /// Clock 과 메시지를 같은 시각으로 보는 오차(초). 펄스 시각(k × step)과 노트 시각(박 × spb)은 몇 ulp 어긋날 수 있다.
    private static let sameInstant = 1e-6
    private static let log = Logger(subsystem: "dev.soomtong.keyscore", category: "midi")

    private let client: MIDIClientRef
    private let source: MIDIEndpointRef
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
    /// MIDI Clock 과 Start/Stop/Continue 송신 여부. 재생 중에 바뀔 수 있으므로 펄스 위치는 늘 계산해 둔다.
    private var clockOn = false
    private var clockStep = 0.0
    private var clockCount = 0
    private var clockIndex = 0
    /// 수신 측에 Start/Continue 를 보내고 아직 Stop 을 보내지 않았다. Stop 은 이때만 보낸다 (짝 없는 Stop 이 남의 트랜스포트를 세우지 않게).
    private var running = false
    /// 이번 바퀴 끝을 앞두고 다음 바퀴의 Start 를 미리 보냈다
    private var restartSent = false
    /// 재생 회차. stop 알림이 어느 재생에 대한 것인지 구분한다 (정지 직후 새 재생을 시작했을 때 늦게 도착한 알림 무시용).
    private var session = 0

    /// 송신 버퍼. 같은 순간에 나가는 메시지(화음 구성음, 베이스, 드럼)를 하나의 MIDIEventList 로 모아
    /// MIDIServer 왕복을 메시지 수가 아니라 tick 수만큼만 한다. 큐에서만 만진다.
    /// 힙에 두는 이유: 패킷 포인터가 리스트 안을 가리키므로 구조체가 복사되거나 옮겨지면 안 된다.
    private let outbox = UnsafeMutablePointer<MIDIEventList>.allocate(capacity: 1)
    private static let outboxSize = MemoryLayout<MIDIEventList>.size
    /// MIDIEventPacket 하나에 들어가는 최대 워드 수 (MIDI 1.0 메시지 하나 = 1 워드)
    private static let packetWords = 64
    private var outPacket: UnsafeMutablePointer<MIDIEventPacket>?
    private var outWords = 0

    /// 아래 콜백은 모두 `queue` 에서 불린다. 재생을 시작하기 전에 한 번만 설정한다.
    var onProgress: (@Sendable (Double) -> Void)?
    /// 인자는 끝난 재생의 session (play 가 돌려준 값)
    var onStop: (@Sendable (Int) -> Void)?
    /// Note On 을 보낼 때 호출 (표시등용). activityInterval 보다 자주 부르지 않는다.
    var onActivity: (@Sendable () -> Void)?

    /// 가상 소스를 만들지 못하면 false. 이때 송신은 조용히 무시된다.
    let isReady: Bool

    init() {
        var client = MIDIClientRef()
        var source = MIDIEndpointRef()
        var status = MIDIClientCreateWithBlock("KeyScore" as CFString, &client, nil)
        if status == noErr {
            status = MIDISourceCreateWithProtocol(client, "KeyScore" as CFString, ._1_0, &source)
            if status != noErr { Self.log.error("MIDISourceCreate failed: \(status)") }
        } else {
            Self.log.error("MIDIClientCreate failed: \(status)")
        }
        self.client = client
        self.source = source
        isReady = status == noErr
    }

    deinit {
        // 큐 작업은 self 를 붙잡으므로 여기까지 오면 큐에 남은 작업이 없다. 울리던 음과 수신 측 트랜스포트를 세우고 정리한다.
        stopLocked(notify: false)
        outbox.deallocate()
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
            clockStep = 60 / song.bpm / Double(Self.clocksPerBeat)
            clockCount = clockStep.isFinite && clockStep > 0 ? Self.clockCount(totalBeats: song.totalBeats) : 0
            self.loop = loop
            session = id
            index = 0
            clockIndex = 0
            restartSent = false
            lastProgress = 0
            lastActivity = -1
            if pedal {  // 페달을 밟은 채로 시작
                for ch in chans { enqueue(0xB0 | ch, 64, 127) }
            }
            if clockOn {  // Start: 다음에 오는 첫 Clock(t = 0)이 곡의 첫 박. 그 사이에 startLead 를 둔다.
                enqueue(0xFA, 0, 0)
                running = true
            }
            flush()
            startNanos = DispatchTime.now().uptimeNanoseconds &+ (running ? UInt64(Self.startLead * 1e9) : 0)
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
            for ch in usedChannels { enqueue(0xB0 | ch, 64, down ? 127 : 0) }
            flush()
        }
    }

    /// MIDI Clock 과 Start/Stop 송신. 재생 중에 켜면 다음 16분음표 자리를 Song Position Pointer 로 알리고 Continue 로
    /// 이어 붙인다 (SPP 는 수신 측이 멈춰 있을 때 보내야 하는데, Clock 을 받기 전이므로 멈춰 있다). 끄면 바로 Stop 을 보낸다.
    func setClock(_ on: Bool) {
        queue.async { [self] in
            guard on != clockOn else { return }
            clockOn = on
            guard timer != nil else { return }
            if !on {
                if running { enqueue(0xFC, 0, 0) }
                running = false
                restartSent = false
            } else if clockCount > 0 {
                // Continue 와 첫 펄스 사이에 startLead 이상을 두는 가장 가까운 16분음표
                let sixteenthSeconds = clockStep * Double(Self.clocksPerSixteenth)
                let sixteenth = Int((max(0, elapsed + Self.startLead) / sixteenthSeconds).rounded(.up))
                clockIndex = sixteenth * Self.clocksPerSixteenth
                // 곡 끝이 더 가깝거나 SPP 로 나타낼 수 없는 자리면 이번 바퀴는 건너뛴다. 반복이면 다음 바퀴의 Start 부터 따라온다.
                if clockIndex < clockCount && sixteenth <= 0x3FFF {
                    enqueue(0xF2, UInt8(sixteenth & 0x7F), UInt8(sixteenth >> 7))
                    enqueue(0xFB, 0, 0)
                    running = true
                }
            }
            flush()
            arm()
        }
    }

    func setLoop(_ value: Bool) {
        queue.async { [self] in
            loop = value
            arm()  // 바퀴 끝과 다음 Start 시각이 반복 여부에 따라 달라진다
        }
    }

    func stop() {
        queue.async { [self] in stopLocked(notify: true) }
    }

    /// 앱 종료처럼 바로 이어서 프로세스가 끝날 때. 큐에 쌓인 작업을 마친 뒤 Stop 과 Note Off 를 보내고 돌아온다.
    func stopNow() {
        queue.sync { stopLocked(notify: false) }
    }

    // MARK: 큐 안

    private let sessionLock = OSAllocatedUnfairLock(initialState: 0)

    private func nextSession() -> Int {
        sessionLock.withLock { $0 += 1; return $0 }
    }

    /// Song 을 시각순 메시지 목록으로. 같은 시각이면 Note Off 가 먼저 나가야 같은 음을 다시 칠 수 있다.
    /// MIDI 범위 밖의 음높이는 보내지 않고, 세기는 1...127 로 잘라 Note On 이 Note Off(세기 0)로 해석되지 않게 한다.
    private static func schedule(_ song: Song) -> ([Message], Set<UInt8>) {
        let spb = 60 / song.bpm
        var msgs: [Message] = []
        msgs.reserveCapacity(song.events.count * 2)
        var chans = Set<UInt8>()
        for e in song.events where (0...127).contains(e.pitch) {
            let ch = e.channel & 0x0F
            chans.insert(ch)
            let on = e.start * spb
            let off = max(on + 0.01, (e.start + e.length) * spb - 0.005)
            let pitch = UInt8(e.pitch)
            msgs.append(Message(time: on, status: 0x90 | ch, d1: pitch, d2: UInt8(clamping: max(1, e.velocity))))
            msgs.append(Message(time: off, status: 0x80 | ch, d1: pitch, d2: 0))
        }
        msgs.sort { $0.time != $1.time ? $0.time < $1.time : ($0.status & 0xF0) < ($1.status & 0xF0) }
        return (msgs, chans)
    }

    /// 한 바퀴의 Clock 펄스 수. 곡 끝 직전 펄스까지만 센다 (반복하면 곡 끝 자리의 펄스는 다음 바퀴의 첫 펄스다).
    static func clockCount(totalBeats: Double) -> Int {
        guard totalBeats.isFinite, totalBeats > 0 else { return 0 }
        // 상한은 Int 변환이 넘치지 않게 하는 것뿐이다 (최대 곡도 수만 펄스)
        return Int((min(totalBeats, 1e9) * Double(clocksPerBeat) - 1e-6).rounded(.up))
    }

    /// 재생 시작(startNanos)부터 지난 시간(초). 시작 직전(startLead 안)이면 음수다.
    private var elapsed: Double {
        Double(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds &- startNanos)) / 1e9
    }

    /// 다음 Clock 펄스 시각. 수신 측이 멈춰 있거나 이번 바퀴의 펄스를 다 보냈으면 무한대.
    private var nextClock: Double {
        running && clockIndex < clockCount ? Double(clockIndex) * clockStep : .infinity
    }

    /// 반복 재생 한 바퀴의 길이(초). Clock 을 보내면 펄스 격자에 맞춰 올린다 (Legato 여유처럼 곡 길이가 1/24 박 단위가
    /// 아니어도 바퀴 경계의 펄스 간격이 clockStep 그대로이게). 늘어나는 것은 한 펄스 미만이다.
    private var cycleSeconds: Double {
        clockOn && clockCount > 0 ? max(endSeconds, Double(clockCount) * clockStep) : endSeconds
    }

    /// 다음에 보낼 메시지 시각. 반복 재생이면 바퀴 끝 너머의 메시지는 보내지 않는다 (되감을 때 울리던 음을 끊는다).
    private func nextMessage(before cycle: Double) -> Double {
        guard index < messages.count, !loop || messages[index].time < cycle else { return .infinity }
        return messages[index].time
    }

    /// 다음 바퀴 Start 를 미리 보낼 시각. 이번 바퀴의 펄스를 다 보낸 뒤, 바퀴 끝보다 startLead 앞.
    private func restartTime(cycle: Double) -> Double {
        loop && clockOn && clockCount > 0 && !restartSent ? cycle - Self.startLead : .infinity
    }

    /// 다음에 깨어날 시각: 다음 메시지, 다음 Clock, 다음 Start, 다음 진행 보고, 곡 끝 중 가장 빠른 것. 1 ms 폴링 대신 필요한 순간에만 깨어난다.
    private func arm() {
        guard let timer else { return }
        let cycle = cycleSeconds
        // 반복 재생은 바퀴 끝에 바로 되감아 Clock 이 끊기지 않게 한다. 한 번 재생은 메시지를 다 보낸 뒤에만 끝낸다
        // (마지막 Note Off 가 endSeconds 를 넘겨도 바쁜 대기에 빠지지 않게).
        let finish = loop ? cycle : index < messages.count ? Double.infinity : endSeconds
        let next = min(nextMessage(before: cycle), nextClock, restartTime(cycle: cycle), lastProgress + Self.progressInterval, finish)
        let deadline = DispatchTime(uptimeNanoseconds: startNanos &+ UInt64(max(0, next) * 1e9))
        timer.schedule(deadline: deadline, repeating: .never, leeway: .microseconds(100))
    }

    private func tick() {
        guard timer != nil else { return }
        var now = elapsed
        var sentNote = false
        let cycle = cycleSeconds
        // 메시지와 Clock 을 시각순으로 섞는다. 같은 시각이면 Clock 이 먼저 나가 수신 측이 그 펄스를 박의 기준으로 삼는다.
        while true {
            let clock = nextClock
            let message = nextMessage(before: cycle)
            guard min(clock, message) <= now else { break }
            if clock <= message + Self.sameInstant {
                enqueue(0xF8, 0, 0)
                clockIndex += 1
            } else {
                sentNote = send(messages[index]) || sentNote
                index += 1
            }
        }
        if nextClock == .infinity, now >= restartTime(cycle: cycle) {
            enqueue(0xFA, 0, 0)  // 다음 바퀴 Start. 되감은 뒤 t = 0 펄스까지 startLead 가 생긴다.
            running = true
            restartSent = true
        }
        flush()
        if sentNote, now - lastActivity >= Self.activityInterval {
            lastActivity = now
            onActivity?()
        }
        if now - lastProgress >= Self.progressInterval {
            lastProgress = now
            onProgress?(min(now, endSeconds))
        }
        if loop ? now >= cycle : index >= messages.count && now >= endSeconds {
            // 길이가 0 인 곡을 반복하면 타이머가 쉬지 않고 돌므로 그냥 끝낸다
            guard loop, cycle > 0 else { return stopLocked(notify: true) }
            // 바퀴 끝을 넘어 울리던 음은 여기서 끊는다. 다음 바퀴가 같은 음을 다시 칠 수 있게 t = 0 메시지보다 먼저.
            releaseNotes()
            // 곡이 처음으로 돌아가므로 수신 측도 처음부터 (곡 길이가 마디 단위가 아니어도 마디 위치가 맞는다).
            // 보통은 바퀴 끝 직전에 이미 보냈다.
            if clockOn && !restartSent {
                enqueue(0xFA, 0, 0)
                running = true
            }
            flush()
            startNanos &+= UInt64(cycle * 1e9)
            index = 0
            clockIndex = 0
            restartSent = false
            now -= cycle
            lastProgress = 0
            lastActivity = -1
        }
        arm()
    }

    private func stopLocked(notify: Bool) {
        guard let t = timer else { return }
        t.cancel()
        timer = nil
        if running { enqueue(0xFC, 0, 0) }  // Stop: 수신 측 아르페지에이터·시퀀서를 먼저 세운다
        running = false
        restartSent = false
        for ch in usedChannels { enqueue(0xB0 | ch, 64, 0) }  // 페달을 먼저 떼야 울리던 음이 끊긴다
        releaseNotes()
        for ch in usedChannels { enqueue(0xB0 | ch, 123, 0) }  // All Notes Off
        flush()
        if notify { onStop?(session) }
    }

    /// 울리고 있는 음마다 Note Off
    private func releaseNotes() {
        for key in active {
            enqueue(0x80 | UInt8(key >> 8), UInt8(key & 0xFF), 0)
        }
        active.removeAll()
    }

    /// Note On 이면 true. 실제 송신은 flush 에서.
    private func send(_ m: Message) -> Bool {
        let key = UInt16(m.status & 0x0F) << 8 | UInt16(m.d1)
        let isOn = m.status & 0xF0 == 0x90
        if isOn { active.insert(key) } else { active.remove(key) }
        enqueue(m.status, m.d1, m.d2)
        return isOn
    }

    /// 송신 버퍼에 메시지 하나를 더한다. 패킷(64 워드)이 차면 먼저 보내고 새 패킷을 시작하므로 순서는 유지된다.
    /// MIDIEventListAdd 는 자리가 없으면 NULL 을 주지만 Swift 에는 non-optional 로 들어오므로 워드 수를 직접 센다.
    private func enqueue(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) {
        guard isReady else { return }
        if outWords >= Self.packetWords { flush() }
        let packet = outPacket ?? MIDIEventListInit(outbox, ._1_0)
        // UMP group 0. MIDI 1.0 Channel Voice 는 type 2, System Common/Real Time(0xF1...0xFF) 은 type 1. 데이터 바이트는 7비트.
        // SysEx(0xF0, 0xF7)는 UMP type 3 의 여러 워드라 이 경로로 보낼 수 없다.
        assert(status != 0xF0 && status != 0xF7, "SysEx 는 enqueue 로 보낼 수 없다")
        let type: UInt32 = status >= 0xF1 ? 0x1 : 0x2
        var word = type << 28 | UInt32(status) << 16 | UInt32(d1 & 0x7F) << 8 | UInt32(d2 & 0x7F)
        outPacket = MIDIEventListAdd(outbox, Self.outboxSize, packet, 0, 1, &word)
        outWords += 1
    }

    /// 버퍼에 쌓인 메시지를 한 번에 보낸다. 비어 있으면 아무것도 하지 않는다.
    private func flush() {
        guard outWords > 0 else { return }
        MIDIReceivedEventList(source, outbox)
        outPacket = nil
        outWords = 0
    }
}
