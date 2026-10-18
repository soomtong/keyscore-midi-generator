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
    var rhythm = 10  // 드럼. 16채널 악기는 보통 10번, 8채널 악기는 8번
}

struct ArrangeOptions {
    var bpm: Double
    var minutes: Double
    var channels = ChannelMap()
    var chordPattern: ChordPattern = .block
    var drumPattern: DrumPattern = .off
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

    static func targetBars(minutes: Double, bpm: Double, beatsPerBar: Int = 4) -> Int {
        max(1, Int((minutes * bpm / Double(beatsPerBar)).rounded()))
    }

    static func build(_ arr: Arrangement, options o: ArrangeOptions) -> Song {
        let bpb = Double(o.beatsPerBar)
        let targetBars = targetBars(minutes: o.minutes, bpm: o.bpm, beatsPerBar: o.beatsPerBar)
        let order = expandForm(arr.form, sections: arr.sections, targetBars: targetBars)
        let ch = o.channels
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

            // 리듬: 섹션이 바뀔 때 크래시
            events += o.drumPattern.notes(start: cursor, beats: secBeats, channel: UInt8(ch.rhythm - 1), crashOnStart: true)

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
