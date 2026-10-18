import Foundation

struct NoteEvent: Equatable {
    var channel: UInt8  // 0-based
    var pitch: Int
    var velocity: Int
    var start: Double  // beats
    var length: Double  // beats
}

struct Song {
    var title: String
    var bpm: Double
    var events: [NoteEvent]
    var totalBeats: Double

    var seconds: Double { totalBeats * 60 / bpm }
}

enum ChordPattern: String, CaseIterable, Identifiable {
    case block = "Block"
    case arpUp = "Arpeggio Up"
    case arpDown = "Arpeggio Down"
    case arpUpDown = "Arpeggio Up-Down"
    case alberti = "Alberti"
    case strum = "Strum"
    case pulse = "8th Pulse"

    var id: String { rawValue }

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
        switch self {
        case .block:
            return pitches.map { ev($0, 0, beats * 0.95) }
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
        case .strum:
            return pitches.enumerated().map { i, p in ev(p, Double(i) * 0.06, beats * 0.95 - Double(i) * 0.06, -Int(i)) }
        case .pulse:
            var out: [NoteEvent] = []
            var t = 0.0
            while t < beats - 1e-9 {
                let accent = t.truncatingRemainder(dividingBy: 1) == 0 ? 0 : -14
                out += pitches.map { ev($0, t, min(0.45, beats - t), accent) }
                t += 0.5
            }
            return out
        }
    }
}

/// 코드 한 마디(또는 몇 박) 분량.
struct ChordSpec {
    var root: Int  // pitch class
    var quality: ChordQuality
    var beats: Double

    var symbol: String { noteNames[root] + quality.symbol }

    /// 코드 구성음을 48...71 부근에 배치.
    var voicing: [Int] {
        let base = 48 + root - (root > 6 ? 12 : 0) + 12
        return quality.intervals.map { base + $0 }
    }

    var bassNote: Int { 36 + root }
}
