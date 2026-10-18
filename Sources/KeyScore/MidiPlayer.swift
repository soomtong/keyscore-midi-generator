import CoreMIDI
import Foundation

/// CoreMIDI 가상 소스 "KeyScore" 로 이벤트를 송신한다. Omnisphere 등에서 이 소스를 MIDI 입력으로 선택한다.
final class MidiPlayer: @unchecked Sendable {
    private struct Message {
        var time: Double
        var status: UInt8
        var d1: UInt8
        var d2: UInt8
    }

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

    /// 메인 스레드가 아닌 곳에서 호출됨.
    var onProgress: (@Sendable (Double) -> Void)?
    var onStop: (@Sendable () -> Void)?

    init() {
        MIDIClientCreate("KeyScore" as CFString, nil, nil, &client)
        MIDISourceCreateWithProtocol(client, "KeyScore" as CFString, ._1_0, &source)
    }

    deinit {
        timer?.cancel()
        MIDIEndpointDispose(source)
        MIDIClientDispose(client)
    }

    func play(_ song: Song, loop: Bool) {
        let spb = 60 / song.bpm
        var msgs: [Message] = []
        var chans = Set<UInt8>()
        for e in song.events {
            let ch = e.channel & 0x0F
            chans.insert(ch)
            let on = e.start * spb
            let off = max(on + 0.01, (e.start + e.length) * spb - 0.005)
            msgs.append(Message(time: on, status: 0x90 | ch, d1: UInt8(clamping: e.pitch), d2: UInt8(clamping: e.velocity)))
            msgs.append(Message(time: off, status: 0x80 | ch, d1: UInt8(clamping: e.pitch), d2: 0))
        }
        // 같은 시각이면 note off 가 먼저
        msgs.sort { $0.time != $1.time ? $0.time < $1.time : ($0.status & 0xF0) < ($1.status & 0xF0) }
        let end = song.totalBeats * spb

        queue.async { [self] in
            stopLocked(notify: false)
            messages = msgs
            usedChannels = chans
            endSeconds = end
            self.loop = loop
            index = 0
            lastProgress = 0
            startNanos = DispatchTime.now().uptimeNanoseconds
            let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(1), leeway: .microseconds(100))
            t.setEventHandler { [weak self] in self?.tick() }
            timer = t
            t.resume()
        }
    }

    func setLoop(_ value: Bool) {
        queue.async { [self] in loop = value }
    }

    func stop() {
        queue.async { [self] in stopLocked(notify: true) }
    }

    private func tick() {
        var now = Double(DispatchTime.now().uptimeNanoseconds - startNanos) / 1e9
        while index < messages.count, messages[index].time <= now {
            send(messages[index])
            index += 1
        }
        if now - lastProgress >= 0.05 {
            lastProgress = now
            onProgress?(min(now, endSeconds))
        }
        if index >= messages.count && now >= endSeconds {
            if loop {
                startNanos += UInt64(endSeconds * 1e9)
                index = 0
                now -= endSeconds
                lastProgress = 0
            } else {
                stopLocked(notify: true)
            }
        }
    }

    private func stopLocked(notify: Bool) {
        guard let t = timer else { return }
        t.cancel()
        timer = nil
        for key in active {
            sendRaw(0x80 | UInt8(key >> 8), UInt8(key & 0xFF), 0)
        }
        active.removeAll()
        for ch in usedChannels { sendRaw(0xB0 | ch, 123, 0) }  // All Notes Off
        if notify { onStop?() }
    }

    private func send(_ m: Message) {
        let key = UInt16(m.status & 0x0F) << 8 | UInt16(m.d1)
        if m.status & 0xF0 == 0x90 { active.insert(key) } else { active.remove(key) }
        sendRaw(m.status, m.d1, m.d2)
    }

    private func sendRaw(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) {
        // UMP MIDI 1.0 Channel Voice: type 2, group 0
        var word = UInt32(0x2) << 28 | UInt32(status) << 16 | UInt32(d1) << 8 | UInt32(d2)
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &word)
        MIDIReceivedEventList(source, &list)
    }
}
