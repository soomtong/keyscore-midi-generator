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
    ///
    /// 멜로디는 마디별 시작 여부와 음높이별 울림 구간으로 먼저 정리한다. 리프 음마다 멜로디 전체를 훑으면
    /// LLM 이 상한(음 2048개)까지 채운 섹션에서 수 초씩 걸리는데, 이렇게 하면 음 하나에 이분 탐색 세 번이다.
    static func riffNotes(_ sec: SectionSpec, start: Double, beats: Double, channel: UInt8) -> [NoteEvent] {
        guard !sec.riff.isEmpty, beats > 0 else { return [] }
        let riffBars = max(1, sec.riffBars)
        let bars = Int((beats / 4).rounded(.up))
        let melody = sec.melody.filter { $0.beat >= 0 && $0.beat < beats }
        let velocity = melody.isEmpty ? 84 : 74
        var starts = [Bool](repeating: false, count: bars)
        for m in melody { starts[min(bars - 1, Int(m.beat / 4))] = true }
        let sounding = SoundingMap(melody)
        func rests(_ bar: Int) -> Bool { bar < bars && !starts[bar] }
        func clashes(_ p: Int, _ s: Double, _ l: Double) -> Bool {
            (p - 1...p + 1).contains { sounding.overlaps(pitch: $0, from: s, to: s + l) }
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
                var p = n.pitch.foldedIntoOctaveRange(riffRange)
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

/// 음높이별로 음이 울리는 구간 [start, end) 을 겹치는 것끼리 합쳐 정렬해 둔 표.
/// 어떤 구간과 겹치는 음이 있는지를 이분 탐색으로 답한다.
struct SoundingMap {
    private var spans: [Int: [(start: Double, end: Double)]] = [:]

    init(_ notes: [MelodyNote]) {
        for (pitch, group) in Dictionary(grouping: notes, by: \.pitch) {
            var merged: [(start: Double, end: Double)] = []
            for n in group.sorted(by: { $0.beat < $1.beat }) {
                let end = n.beat + max(0, n.length)
                if let last = merged.last, n.beat <= last.end {
                    merged[merged.count - 1].end = max(last.end, end)
                } else {
                    merged.append((n.beat, end))
                }
            }
            spans[pitch] = merged
        }
    }

    /// pitch 의 음이 [from, to) 와 겹쳐 울리는가 (끝점이 맞닿기만 하면 겹치지 않는다).
    func overlaps(pitch: Int, from: Double, to: Double) -> Bool {
        guard let list = spans[pitch] else { return false }
        // end > from 인 첫 구간을 찾는다 (구간은 서로 겹치지 않고 정렬되어 있다)
        var lo = 0, hi = list.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if list[mid].end <= from { lo = mid + 1 } else { hi = mid }
        }
        return lo < list.count && list[lo].start < to
    }
}
