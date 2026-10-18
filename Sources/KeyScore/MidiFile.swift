import Foundation

/// Song 을 Standard MIDI File (SMF 1.0, Format 1) 로 직렬화한다. 파일 입출력은 하지 않는다.
///
/// 트랙 0 은 컨덕터(곡 제목, 템포, 박자)이고, 그 뒤로 쓰인 채널마다 트랙 하나를 채널 순서대로 둔다.
/// Song 은 파트 정보 없이 채널만 갖고 있고 채널은 사용자가 겹치게 고를 수 있으므로, 파트가 아니라 채널 단위로 나눈다.
/// Key signature 는 쓰지 않는다 (모드·블루스 스케일은 FF 59 의 장조/단조로 표현되지 않는다). Program Change 도 쓰지 않는다
/// (외부 악기에서 음색을 고르는 앱이다).
enum MidiFile {
    static let ticksPerBeat = 480
    /// VLQ 로 표현할 수 있는 최대 값 (4 바이트)
    static let maxTick = 0x0FFF_FFFF

    private struct Message {
        var tick: Int
        var isOn: Bool
        var channel: UInt8
        var pitch: UInt8
        var velocity: UInt8
    }

    /// trackNames 는 채널(0-based)별 트랙 이름. 없으면 "Channel N" (1-based).
    static func data(_ song: Song, trackNames: [UInt8: String] = [:], beatsPerBar: Int = 4) -> Data {
        let byChannel = messages(song)
        var out = Data()
        out.reserveCapacity(64 + song.events.count * 10)
        out.append(contentsOf: Array("MThd".utf8))
        out.append(be32(6))
        out.append(be16(1))  // format 1
        out.append(be16(1 + byChannel.count))
        out.append(be16(ticksPerBeat))

        let endTick = tick(song.totalBeats) ?? 0
        out.append(track(conductor(song, beatsPerBar: beatsPerBar), endTick: endTick))
        for (ch, msgs) in byChannel {
            var body = meta(0x03, text(trackNames[ch] ?? "Channel \(Int(ch) + 1)"))
            var last = 0
            for m in msgs {
                body += vlq(m.tick - last)
                body += m.isOn ? [0x90 | m.channel, m.pitch, m.velocity] : [0x80 | m.channel, m.pitch, 64]
                last = m.tick
            }
            out.append(track((body, last), endTick: endTick))
        }
        return out
    }

    /// 템포 meta 의 값 (4분음표당 마이크로초). bpm 이 유한하지 않거나 0 이하이면 120 BPM.
    static func microsPerBeat(_ bpm: Double) -> Int {
        guard bpm.isFinite, bpm > 0 else { return 500_000 }
        return Int(min(Double(0xFF_FFFF), max(1, (60_000_000 / bpm).rounded())))
    }

    /// 가변 길이 수량 (상위 비트가 1 이면 다음 바이트가 이어진다). 범위 밖 값은 0...maxTick 로 자른다.
    static func vlq(_ value: Int) -> [UInt8] {
        var v = min(maxTick, max(0, value))
        var bytes = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            bytes.insert(UInt8(v & 0x7F) | 0x80, at: 0)
            v >>= 7
        }
        return bytes
    }

    // MARK: 내부

    /// 박을 tick 으로. 유한하지 않거나 음수이면 nil.
    private static func tick(_ beats: Double) -> Int? {
        guard beats.isFinite, beats >= 0 else { return nil }
        return Int(min(Double(maxTick), (beats * Double(ticksPerBeat)).rounded()))
    }

    /// 채널별로 정렬한 Note On/Off. 범위 밖 음높이와 시각이 이상한 이벤트는 버리고, 세기는 1...127 로 자른다.
    /// 같은 (채널, 음높이) 가 겹치면 앞 음을 다음 음의 시작에서 끊는다 (실시간 송신에서도 뒤 음의 Off 가 앞 음을 끊는다).
    /// 같은 tick 에 같은 음이 두 번 시작하면 센 쪽 하나만 남긴다.
    private static func messages(_ song: Song) -> [(UInt8, [Message])] {
        struct Key: Hashable { var channel: UInt8; var pitch: UInt8 }
        var notes: [Key: [(start: Int, end: Int, velocity: UInt8)]] = [:]
        for e in song.events where (0...127).contains(e.pitch) {
            guard let start = tick(e.start), e.length.isFinite, let end = tick(e.start + max(0, e.length)) else { continue }
            let key = Key(channel: e.channel & 0x0F, pitch: UInt8(e.pitch))
            notes[key, default: []].append((start, max(end, start + 1), UInt8(clamping: max(1, e.velocity))))
        }
        var byChannel: [UInt8: [Message]] = [:]
        for (key, list) in notes {
            let sorted = list.sorted { $0.start != $1.start ? $0.start < $1.start : $0.velocity > $1.velocity }
            for (i, n) in sorted.enumerated() {
                if i > 0, sorted[i - 1].start == n.start { continue }
                let next = sorted[(i + 1)...].first { $0.start > n.start }?.start
                let end = min(n.end, next ?? .max)
                byChannel[key.channel, default: []] += [
                    Message(tick: n.start, isOn: true, channel: key.channel, pitch: key.pitch, velocity: n.velocity),
                    Message(tick: end, isOn: false, channel: key.channel, pitch: key.pitch, velocity: 0),
                ]
            }
        }
        // 같은 tick 이면 Off 먼저, 그다음 음높이 순 (Dictionary 순서에 따라 파일이 달라지지 않게)
        return byChannel.keys.sorted().map { ch in
            (ch, byChannel[ch]!.sorted {
                if $0.tick != $1.tick { return $0.tick < $1.tick }
                if $0.isOn != $1.isOn { return !$0.isOn }
                return $0.pitch < $1.pitch
            })
        }
    }

    /// 트랙 0: 제목, 4/4 등 박자, 템포. 모두 tick 0.
    private static func conductor(_ song: Song, beatsPerBar: Int) -> ([UInt8], Int) {
        let us = microsPerBeat(song.bpm)
        let numerator = UInt8(min(255, max(1, beatsPerBar)))
        var body = meta(0x03, text(song.title))
        body += meta(0x58, [numerator, 2, 24, 8])  // n/4, 메트로놈 클릭 24 clocks, 4분음표당 32분음표 8개
        body += meta(0x51, [UInt8(us >> 16 & 0xFF), UInt8(us >> 8 & 0xFF), UInt8(us & 0xFF)])
        return (body, 0)
    }

    /// delta 0 의 meta event
    private static func meta(_ type: UInt8, _ payload: [UInt8]) -> [UInt8] {
        [0x00, 0xFF, type] + vlq(payload.count) + payload
    }

    /// 텍스트 meta 의 내용. 너무 긴 제목은 문자 단위로 자른다.
    private static func text(_ s: String) -> [UInt8] {
        Array(String(s.prefix(128)).utf8)
    }

    /// MTrk 청크. End of Track 은 마지막 이벤트와 곡 끝 중 늦은 쪽에 둔다 (곡 끝의 쉼표가 남도록).
    private static func track(_ content: ([UInt8], Int), endTick: Int) -> Data {
        let (body, last) = content
        let bytes = body + vlq(max(0, endTick - last)) + [0xFF, 0x2F, 0x00]
        var chunk = Data(Array("MTrk".utf8))
        chunk.append(be32(bytes.count))
        chunk.append(contentsOf: bytes)
        return chunk
    }

    private static func be32(_ v: Int) -> Data {
        Data([UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)])
    }

    private static func be16(_ v: Int) -> Data {
        Data([UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)])
    }
}
