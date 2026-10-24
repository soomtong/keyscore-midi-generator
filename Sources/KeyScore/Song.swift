import Foundation

struct NoteEvent: Equatable, Sendable {
    var channel: UInt8  // 0-based
    var pitch: Int
    var velocity: Int
    var start: Double  // beats
    var length: Double  // beats
}

struct Song: Sendable {
    var title: String
    var bpm: Double
    var events: [NoteEvent]
    var totalBeats: Double

    var seconds: Double { totalBeats * 60 / bpm }
}

extension Int {
    /// 음높이를 옥타브 단위로 옮겨 range 안에 넣는다. range 가 한 옥타브보다 좁으면 가장 가까운 끝으로 자른다.
    /// 반복문 대신 나눗셈으로 접으므로 입력이 아무리 커도 한 번에 끝난다.
    func foldedIntoOctaveRange(_ range: ClosedRange<Int>) -> Int {
        // 음높이로서 의미 없는 극단값은 먼저 잘라 아래 산술이 넘치지 않게 한다
        var p = Swift.min(1_000_000, Swift.max(-1_000_000, self))
        if p > range.upperBound { p -= 12 * ((p - range.upperBound + 11) / 12) }
        if p < range.lowerBound { p += 12 * ((range.lowerBound - p + 11) / 12) }
        return Swift.min(range.upperBound, Swift.max(range.lowerBound, p))
    }
}

enum ChordPattern: String, CaseIterable, Identifiable {
    case block = "Block"
    case strum = "Strum"
    case harpRoll = "Harp Roll"
    case arpUp = "Arpeggio Up"
    case arpDown = "Arpeggio Down"
    case arpUpDown = "Arpeggio Up-Down"
    case alberti = "Alberti"
    case broken = "Broken"
    case ballad = "Ballad"
    case oomPah = "Oom-Pah"
    case pulse = "8th Pulse"
    case popStrum = "Pop Strum"
    case offbeat = "Offbeat Skank"
    case stabs = "Syncopated Stabs"
    case staccato = "Staccato"
    case tremolo = "Tremolo"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .block: return "모든 구성음을 한 번에 길게 누름"
        case .strum: return "아래로 훑듯 빠르게 차례로 울림"
        case .harpRoll: return "느리게 아래에서 위로 펼치고 길게 유지"
        case .arpUp: return "8분음표로 낮은 음에서 높은 음으로 분산"
        case .arpDown: return "8분음표로 높은 음에서 낮은 음으로 분산"
        case .arpUpDown: return "8분음표로 올라갔다 내려오는 분산"
        case .alberti: return "낮은-높은-중간-높은 음 반복, 클래식 반주"
        case .broken: return "근음-5도-3도-5도를 4분음표로 느긋하게"
        case .ballad: return "근음은 길게 깔고 위에서 8분음표 분산"
        case .oomPah: return "1·3박 근음, 2·4박 화음 (행진곡/컨트리)"
        case .pulse: return "8분음표로 화음을 계속 두드림"
        case .popStrum: return "↓ ↓↑ ↑↓↑ 팝/포크 스트러밍 리듬"
        case .offbeat: return "뒷박(and)에만 짧게 치는 레게 스카"
        case .stabs: return "3+3+2 당김음으로 끊어 치는 스탭"
        case .staccato: return "1·3박에 아주 짧게 끊어 침"
        case .tremolo: return "16분음표로 빠르게 떨며 반복"
        }
    }

    /// 곡 생성 프롬프트용 영문 설명: 반주가 어떻게 울리는지와 그 위에 얹을 멜로디의 여백.
    var promptHint: String {
        switch self {
        case .block: return "sustained block chords (open, spacious: the melody can move more)"
        case .strum: return "quick downward strums on each chord"
        case .harpRoll: return "slow rolled chords held long (very spacious: the melody can be active)"
        case .arpUp: return "steady eighth-note arpeggios rising (busy: keep the melody simpler)"
        case .arpDown: return "steady eighth-note arpeggios falling (busy: keep the melody simpler)"
        case .arpUpDown: return "steady eighth-note arpeggios rising and falling (busy: keep the melody simpler)"
        case .alberti: return "Alberti bass figures, classical style (busy: keep the melody simpler)"
        case .broken: return "relaxed quarter-note broken chords (root, fifth, third, fifth)"
        case .ballad: return "long bass roots with eighth-note arpeggios above (moderately busy)"
        case .oomPah: return "oom-pah accompaniment, bass on beats 1 and 3 and chords on beats 2 and 4 (march or country feel)"
        case .pulse: return "continuous eighth-note chord pulse (busy: use long notes and rests in the melody)"
        case .popStrum: return "pop/folk strumming rhythm (down, down-up, up-down-up)"
        case .offbeat: return "short reggae-style chops on the off-beats only (leave space on the beat)"
        case .stabs: return "syncopated 3+3+2 chord stabs (keep the melody out of the stab rhythm)"
        case .staccato: return "very short chord hits on beats 1 and 3 (spacious: the melody can be active)"
        case .tremolo: return "fast sixteenth-note tremolo (very busy: keep the melody long-noted and simple)"
        }
    }

    /// 4박 패턴 안의 한 번의 타건. idx 가 nil 이면 모든 구성음, 있으면 해당 구성음만(구성음 수로 나머지 처리).
    private struct Hit {
        var at: Double
        var len: Double
        var vel = 0
        var idx: [Int]? = nil
        var rollStep = 0.0
    }

    func notes(pitches: [Int], start: Double, beats: Double, channel: UInt8, velocity: Int) -> [NoteEvent] {
        guard !pitches.isEmpty, beats > 0 else { return [] }
        func ev(_ p: Int, _ s: Double, _ l: Double, _ v: Int = 0) -> NoteEvent {
            NoteEvent(channel: channel, pitch: p, velocity: max(1, min(127, velocity + v)), start: start + s, length: l)
        }
        func stepped(_ seq: [Int], step: Double) -> [NoteEvent] {
            var out: [NoteEvent] = []
            var t = 0.0
            var i = 0
            while t < beats - 1e-9 {
                out.append(ev(seq[i % seq.count], t, min(step, beats - t), i % 2 == 0 ? 0 : -10))
                t += step
                i += 1
            }
            return out
        }
        /// 4박 단위 패턴을 beats 끝까지 반복
        func grid(_ hits: [Hit]) -> [NoteEvent] {
            var out: [NoteEvent] = []
            var bar = 0.0
            while bar < beats - 1e-9 {
                for h in hits where bar + h.at < beats - 1e-9 {
                    let len = min(h.len, beats - bar - h.at)
                    let chosen = h.idx.map { $0.map { pitches[$0 % pitches.count] } } ?? pitches
                    for (i, p) in chosen.enumerated() {
                        out.append(ev(p, bar + h.at + Double(i) * h.rollStep, max(0.05, len - Double(i) * h.rollStep), h.vel))
                    }
                }
                bar += 4
            }
            return out
        }

        switch self {
        case .block:
            return pitches.map { ev($0, 0, beats * 0.95) }
        case .strum:
            return pitches.enumerated().map { i, p in ev(p, Double(i) * 0.06, beats * 0.95 - Double(i) * 0.06, -i) }
        case .harpRoll:
            return grid([Hit(at: 0, len: 4, rollStep: 0.25)])
        case .arpUp:
            return stepped(pitches, step: 0.5)
        case .arpDown:
            return stepped(pitches.reversed(), step: 0.5)
        case .arpUpDown:
            let down = pitches.dropFirst().dropLast().reversed()
            return stepped(pitches + down, step: 0.5)
        case .alberti:
            guard pitches.count >= 3 else { return stepped(pitches, step: 0.5) }
            return stepped([pitches[0], pitches[2], pitches[1], pitches[2]], step: 0.5)
        case .broken:
            return grid([
                Hit(at: 0, len: 1, idx: [0]), Hit(at: 1, len: 1, vel: -8, idx: [2]),
                Hit(at: 2, len: 1, vel: -4, idx: [1]), Hit(at: 3, len: 1, vel: -8, idx: [2]),
            ])
        case .ballad:
            return grid([Hit(at: 0, len: 4, idx: [0])]
                + (1..<8).map { k in Hit(at: Double(k) * 0.5, len: 0.5, vel: -12, idx: [k % max(1, pitches.count - 1) + 1]) })
        case .oomPah:
            let upper = Array(1..<max(2, pitches.count))
            return grid([
                Hit(at: 0, len: 0.9, vel: 6, idx: [0]), Hit(at: 1, len: 0.9, vel: -6, idx: upper),
                Hit(at: 2, len: 0.9, idx: [0]), Hit(at: 3, len: 0.9, vel: -6, idx: upper),
            ])
        case .pulse:
            return grid((0..<8).map { k in Hit(at: Double(k) * 0.5, len: 0.45, vel: k % 2 == 0 ? 0 : -14) })
        case .popStrum:
            let times: [(Double, Int)] = [(0, 6), (1, 0), (1.5, -8), (2.5, -8), (3, 2), (3.5, -8)]
            return grid(times.map { Hit(at: $0.0, len: 0.5, vel: $0.1, rollStep: 0.03) })
        case .offbeat:
            return grid((0..<4).map { Hit(at: Double($0) + 0.5, len: 0.3, vel: -4) })
        case .stabs:
            return grid([Hit(at: 0, len: 0.5, vel: 10), Hit(at: 1.5, len: 0.5, vel: 4), Hit(at: 3, len: 0.5, vel: 8)])
        case .staccato:
            return grid([Hit(at: 0, len: 0.25, vel: 8), Hit(at: 2, len: 0.25)])
        case .tremolo:
            return grid((0..<16).map { k in Hit(at: Double(k) * 0.25, len: 0.22, vel: k % 4 == 0 ? 0 : -18) })
        }
    }
}

/// 코드 한 마디(또는 몇 박) 분량.
struct ChordSpec {
    var root: Int  // pitch class
    var quality: ChordQuality
    var beats: Double
    /// 슬래시 코드의 베이스 pitch class. nil 이면 근음.
    var bass: Int? = nil

    var symbol: String { noteNames[root] + quality.symbol }

    /// 코드 구성음을 48...71 부근에 배치.
    var voicing: [Int] {
        let base = 48 + root - (root > 6 ? 12 : 0) + 12
        return quality.intervals.map { base + $0 }
    }

    var bassNote: Int { 36 + (bass ?? root) }
}
