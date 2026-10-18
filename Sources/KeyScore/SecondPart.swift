import Foundation

/// 두 번째 파트(기본 4번 채널)의 역할.
/// Riff 는 LLM 이 섹션마다 쓴 짧은 훅을 멜로디가 쉬는 마디와 간주 섹션에만 놓는다.
enum SecondPart: String, CaseIterable, Identifiable {
    case off = "Off"
    case riff = "Riff"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .off: return "두 번째 파트를 쓰지 않음"
        case .riff: return "멜로디가 쉬는 마디와 간주 섹션에서만 리프가 나옴 (Riff 로 생성해야 반영)"
        }
    }

    /// 리프 음역. 멜로디(60..88)보다 아래에 두고, 벗어나면 옥타브로 접는다.
    static let riffRange = 43...76

    /// 섹션 하나 분량의 두 번째 파트. start 는 섹션 시작 박.
    func notes(section sec: SectionSpec, start: Double, beats: Double, channel: UInt8) -> [NoteEvent] {
        switch self {
        case .off: return []
        case .riff: return Self.riffNotes(sec, start: start, beats: beats, channel: channel)
        }
    }

    /// 리프는 멜로디 밑에 깔리지 않는다. 멜로디가 쉬는 마디(그 마디에서 시작하는 멜로디 음이 없음)에만
    /// 프레이즈 사이의 대답으로 놓고, 멜로디가 없는 섹션(간주)에서는 처음부터 끝까지 조금 더 세게 이끈다.
    /// 2마디 리프는 두 마디가 모두 비어야 통째로 놓고, 한 마디만 비면 앞 마디만 놓는다.
    /// 앞 프레이즈에서 이어지는 멜로디 음과 같은 음이거나 반음으로 부딪히면 한 옥타브 내려 보고, 그래도 부딪히면 뺀다.
    static func riffNotes(_ sec: SectionSpec, start: Double, beats: Double, channel: UInt8) -> [NoteEvent] {
        guard !sec.riff.isEmpty, beats > 0 else { return [] }
        let riffBars = max(1, sec.riffBars)
        let bars = Int((beats / 4).rounded(.up))
        let melody = sec.melody.filter { $0.beat >= 0 && $0.beat < beats }
        let velocity = melody.isEmpty ? 84 : 74
        func rests(_ bar: Int) -> Bool { bar < bars && !melody.contains { Int($0.beat / 4) == bar } }
        func clashes(_ p: Int, _ s: Double, _ l: Double) -> Bool {
            melody.contains { m in m.beat < s + l && s < m.beat + m.length && abs(m.pitch - p) <= 1 }
        }
        var out: [NoteEvent] = []
        var bar = 0
        while bar < bars {
            guard rests(bar) else { bar += 1; continue }
            let span = (1..<riffBars).allSatisfy { rests(bar + $0) } ? riffBars : 1
            let offset = Double(bar) * 4
            let end = min(beats, offset + Double(span) * 4)
            for n in sec.riff where n.beat >= 0 && n.beat < Double(span) * 4 && offset + n.beat < end - 1e-9 {
                let s = offset + n.beat
                let l = max(0.1, min(n.length, end - s))
                var p = n.pitch
                while p > riffRange.upperBound { p -= 12 }
                while p < riffRange.lowerBound { p += 12 }
                if clashes(p, s, l) {
                    p -= 12
                    if p < 36 || clashes(p, s, l) { continue }
                }
                out.append(NoteEvent(channel: channel, pitch: p, velocity: velocity, start: start + s, length: l))
            }
            bar += span
        }
        return out
    }
}
