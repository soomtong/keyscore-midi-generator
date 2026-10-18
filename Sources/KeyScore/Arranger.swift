import Foundation

struct MelodyNote {
    var beat: Double
    var pitch: Int
    var length: Double
}

struct SectionSpec {
    var name: String
    var bars: Int
    var chords: [ChordSpec]
    var melody: [MelodyNote]
}

struct Arrangement {
    var title: String
    var sections: [String: SectionSpec]
    var form: [String]
}

struct ChannelMap {
    var melody = 1
    var chords = 2
    var bass = 3
}

struct ArrangeOptions {
    var bpm: Double
    var minutes: Double
    var channels = ChannelMap()
    var chordPattern: ChordPattern = .block
    var beatsPerBar = 4
}

enum Arranger {
    /// form 을 순환하며 목표 마디 수에 가장 가깝게 섹션 목록을 만든다.
    static func expandForm(_ form: [String], sections: [String: SectionSpec], targetBars: Int) -> [String] {
        let valid = form.filter { sections[$0] != nil }
        let cycle = valid.isEmpty ? sections.keys.sorted() : valid
        guard !cycle.isEmpty else { return [] }
        var out: [String] = []
        var bars = 0
        var i = 0
        while bars < targetBars {
            let name = cycle[i % cycle.count]
            let b = max(1, sections[name]!.bars)
            // 마지막 섹션은 넘치는 분량이 더 가까울 때만 추가
            if bars + b > targetBars && (bars + b - targetBars) > (targetBars - bars) && !out.isEmpty { break }
            out.append(name)
            bars += b
            i += 1
        }
        return out
    }

    static func build(_ arr: Arrangement, options o: ArrangeOptions) -> Song {
        let bpb = Double(o.beatsPerBar)
        let targetBars = max(1, Int((o.minutes * o.bpm / bpb).rounded()))
        let order = expandForm(arr.form, sections: arr.sections, targetBars: targetBars)
        let ch = ChannelMap(melody: o.channels.melody, chords: o.channels.chords, bass: o.channels.bass)
        var events: [NoteEvent] = []
        var cursor = 0.0
        var seen: [String: Int] = [:]

        for name in order {
            guard let sec = arr.sections[name] else { continue }
            let secBeats = Double(sec.bars) * bpb
            let pass = seen[name, default: 0]
            seen[name] = pass + 1

            // 코드 + 베이스: 코드 목록을 섹션 길이만큼 순환
            if !sec.chords.isEmpty {
                var t = 0.0
                var i = 0
                while t < secBeats - 1e-9 {
                    let c = sec.chords[i % sec.chords.count]
                    let len = min(c.beats, secBeats - t)
                    events += o.chordPattern.notes(
                        pitches: c.voicing, start: cursor + t, beats: len,
                        channel: UInt8(ch.chords - 1), velocity: 70)
                    var bt = 0.0
                    while bt < len - 1e-9 {
                        let l = min(2, len - bt)
                        events.append(NoteEvent(
                            channel: UInt8(ch.bass - 1), pitch: c.bassNote,
                            velocity: bt == 0 ? 92 : 78, start: cursor + t + bt, length: l * 0.95))
                        bt += 2
                    }
                    t += len
                    i += 1
                }
            }

            // 멜로디: 반복될수록 약간 세게
            for n in sec.melody where n.beat >= 0 && n.beat < secBeats {
                let v = 84 + min(pass, 3) * 4 + Int.random(in: -6...6)
                events.append(NoteEvent(
                    channel: UInt8(ch.melody - 1), pitch: max(0, min(127, n.pitch)),
                    velocity: max(1, min(127, v)), start: cursor + n.beat,
                    length: max(0.1, min(n.length, secBeats - n.beat))))
            }
            cursor += secBeats
        }
        return Song(title: arr.title, bpm: o.bpm, events: events, totalBeats: cursor)
    }
}

enum Preview {
    static func scale(root: Int, type: ScaleType, channel: Int) -> Song {
        let base = 60 + root - (root > 6 ? 12 : 0)
        var pitches = type.intervals.map { base + $0 } + [base + 12]
        pitches += pitches.dropLast().reversed()
        let events = pitches.enumerated().map { i, p in
            NoteEvent(channel: UInt8(channel - 1), pitch: p, velocity: 90, start: Double(i) * 0.5, length: 0.45)
        }
        return Song(title: "\(noteNames[root]) \(type.name)", bpm: 100, events: events, totalBeats: Double(pitches.count) * 0.5 + 0.5)
    }

    static func chord(root: Int, quality: ChordQuality, pattern: ChordPattern, channel: Int) -> Song {
        let c = ChordSpec(root: root, quality: quality, beats: 4)
        // 블록 한 번 + 지정 패턴 한 번
        var events = ChordPattern.block.notes(pitches: c.voicing, start: 0, beats: 4, channel: UInt8(channel - 1), velocity: 80)
        events += pattern.notes(pitches: c.voicing, start: 4, beats: 4, channel: UInt8(channel - 1), velocity: 80)
        return Song(title: c.symbol, bpm: 100, events: events, totalBeats: 8)
    }

    static func progression(root: Int, scale: ScaleType, prog: Theory.Progression, complexity: Int,
                            pattern: ChordPattern, channels: ChannelMap) -> Song {
        var events: [NoteEvent] = []
        var t = 0.0
        for d in prog.degrees {
            let ivs = Theory.diatonicIntervals(scale: scale, degree: d, complexity: complexity)
            let pc = (root + scale.intervals[d % scale.intervals.count]) % 12
            let q = Theory.quality(matching: ivs) ?? ChordQuality(symbol: "", intervals: ivs, complexity: complexity)
            let c = ChordSpec(root: pc, quality: q, beats: 4)
            events += pattern.notes(pitches: c.voicing, start: t, beats: 4, channel: UInt8(channels.chords - 1), velocity: 75)
            events.append(NoteEvent(channel: UInt8(channels.bass - 1), pitch: c.bassNote, velocity: 90, start: t, length: 3.8))
            t += 4
        }
        return Song(title: prog.name, bpm: 90, events: events, totalBeats: t)
    }
}
