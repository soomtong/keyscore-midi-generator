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
    /// 두 번째 파트용 리프. riffBars 마디 길이로 섹션 끝까지 반복한다. 비어 있으면 이 섹션은 쉼.
    var riff: [MelodyNote] = []
    var riffBars = 1
    /// LLM 이 쓴 베이스 라인. 비어 있으면 코드 근음을 2박씩 친다.
    var bass: [MelodyNote] = []
    /// 섹션 역할. LLM 이 주지 않으면 이름으로 추정한다 (Generator.parse).
    var role: SectionRole? = nil
    /// LLM 이 정한 드럼 편성. 없으면 역할의 기본값, 역할도 없으면 full.
    var drums: DrumPlan? = nil

    var drumPlan: DrumPlan { drums ?? role?.defaultDrums ?? DrumPlan() }
}

struct Arrangement {
    var title: String
    var sections: [String: SectionSpec]
    var form: SongForm
}

struct ChannelMap: Equatable {
    var melody = 1
    var chords = 2
    var bass = 3
    var second = 4  // 두 번째 파트 (리프)
    var rhythm = 10  // 드럼. 16채널 악기는 보통 10번, 8채널 악기는 8번
}

struct ArrangeOptions {
    var bpm: Double
    var minutes: Double
    var channels = ChannelMap()
    var chordPattern: ChordPattern = .block
    var drumPattern: DrumPattern = .off
    var secondPart: SecondPart = .off
    var beatsPerBar = 4
}

enum Arranger {
    /// LLM 이 쓴 베이스 음은 이 음역으로 접는다.
    static let bassRange = 24...60

    /// intro 를 한 번, loop 를 한 바퀴 이상, outro 를 한 번 놓아 목표 마디 수에 가장 가깝게 섹션 목록을 만든다.
    /// 남는 길이는 loop 의 뒷부분(후렴 쪽)으로 채운다. 반복 절의 앞(A)을 줄이는 셈이라 간주 → 후렴 흐름이 유지된다.
    /// 곡이 짧아도 intro · loop 한 바퀴 · outro 는 남긴다.
    static func expandForm(_ form: SongForm, sections: [String: SectionSpec], targetBars: Int) -> [String] {
        func valid(_ names: [String]) -> [String] { names.filter { sections[$0] != nil } }
        var intro = valid(form.intro), loop = valid(form.loop), outro = valid(form.outro)
        if loop.isEmpty { (loop, intro, outro) = (intro + outro, [], []) }
        if loop.isEmpty { loop = sections.keys.sorted() }
        guard !loop.isEmpty else { return [] }
        func bars<C: Collection>(_ names: C) -> Int where C.Element == String {
            names.reduce(0) { $0 + max(1, sections[$1]!.bars) }
        }
        let fixed = bars(intro) + bars(outro)
        let loopBars = bars(loop)
        var best = (passes: 1, tail: 0, diff: Int.max, total: Int.max)
        var passes = 1
        while true {
            for tail in 0..<loop.count {
                let total = fixed + passes * loopBars + bars(loop.suffix(tail))
                let diff = abs(total - targetBars)
                if diff < best.diff || (diff == best.diff && total < best.total) { best = (passes, tail, diff, total) }
            }
            if fixed + passes * loopBars >= targetBars { break }
            passes += 1
        }
        return intro + Array(repeating: loop, count: best.passes).flatMap { $0 } + loop.suffix(best.tail) + outro
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
        events.reserveCapacity(order.count * 64)
        var cursor = 0.0
        var seen: [String: Int] = [:]
        var previous = DrumPlan(energy: .light)  // 곡 첫 섹션은 full 일 때만 크래시

        for name in order {
            guard let sec = arr.sections[name] else { continue }
            let secBeats = Double(sec.bars) * bpb
            let pass = seen[name, default: 0]
            seen[name] = pass + 1

            // 코드 + 베이스: 코드 목록을 섹션 길이만큼 순환. 베이스 라인이 있으면 근음 대신 그것을 친다
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
                    while sec.bass.isEmpty && bt < len - 1e-9 {
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

            for n in sec.bass where n.beat >= 0 && n.beat < secBeats {
                events.append(NoteEvent(
                    channel: UInt8(ch.bass - 1), pitch: n.pitch.foldedIntoOctaveRange(Self.bassRange),
                    velocity: n.beat.truncatingRemainder(dividingBy: bpb) == 0 ? 92 : 80,
                    start: cursor + n.beat, length: max(0.1, min(n.length, secBeats - n.beat) * 0.95)))
            }

            // 리듬: 앞 섹션보다 세지거나 앞 섹션이 필인으로 끝났을 때만 크래시
            let plan = sec.drumPlan
            events += o.drumPattern.notes(start: cursor, beats: secBeats, channel: UInt8(ch.rhythm - 1),
                                          crashOnStart: previous.energy < plan.energy || previous.fill,
                                          energy: plan.energy, fill: plan.fill)
            previous = plan

            events += o.secondPart.notes(section: sec, start: cursor, beats: secBeats, channel: UInt8(ch.second - 1))

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
