import Foundation

/// 청취 옵션. kornflake 의 Audition 옵션(순차/동시, 내림차순, 오르내리기, 2옥타브,
/// 코드 확장, 진행 간격, 음 길이, 레가토, 옥타브)을 차용했다.
struct ListenOptions: Equatable {
    var together = false  // false: Sequential, true: Together
    var descending = false
    var upDown = false
    var twoOctaves = false
    var rate: Double = 0.5  // 순차 재생에서 다음 음까지의 간격 (박)
    var noteLength: Double = 0  // 0 = Auto (rate 의 90%)
    var legato = false
    var extendUp = 0
    var extendDown = 0
    var octave = 0
    var varyMelody = false  // 멜로디 프레이즈에 변주를 준다
    var melodySeed: UInt64 = 0  // 변주 시드. 멜로디를 새로 들을 때마다 다시 뽑는다
    /// 진행 · 프레이즈에 묶인 드럼 그루브를 함께 연주한다 (GM 드럼, 리듬 채널).
    /// 묶인 그루브가 없으면 패턴 듣기는 리듬 패턴 설정을, 멜로디 듣기는 드럼 없이 그대로 둔다.
    var groove = false

    static let rates: [Double] = [0.25, 0.5, 1, 2]
    static let lengths: [Double] = [0, 0.25, 0.5, 1, 2, 4, 8]
    static let maxExtend = 6
    /// 레가토: 다음 음이 시작된 뒤 이 시간(초)만큼 이전 음을 더 울린다.
    static let legatoOverlapSeconds = 0.05

    /// 박 길이를 음표 표기로 (1박 = 1/4)
    static func label(beats: Double) -> String {
        switch beats {
        case 0: return "Auto"
        case 0.25: return "1/16"
        case 0.5: return "1/8"
        case 1: return "1/4"
        case 2: return "1/2"
        case 4: return "1"
        case 8: return "2"
        default: return String(format: "%g", beats)
        }
    }
}

enum Preview {
    private static func clamp(_ pitches: [Int]) -> [Int] { pitches.filter { (0...127).contains($0) } }

    /// 옥타브 이동과 위/아래 확장을 적용. 확장은 코드의 음 패턴을 이어서 위나 아래에 더한다.
    static func shape(_ pitches: [Int], _ o: ListenOptions) -> [Int] {
        let base = pitches.sorted().map { $0 + 12 * o.octave }
        let n = base.count
        guard n > 0 else { return [] }
        var up: [Int] = []
        for k in 0..<o.extendUp { up.append(base[k % n] + 12 * (k / n + 1)) }
        var down: [Int] = []
        for k in 0..<o.extendDown { down.append(base[n - 1 - (k % n)] - 12 * (k / n + 1)) }
        return clamp(down.reversed() + base + up)
    }

    /// 음들을 순차(rate 간격) 또는 동시에 NoteEvent 로 만든다. 반환: 이벤트와 전체 박 수.
    private static func play(_ pitches: [Int], channel: Int, o: ListenOptions, bpm: Double, velocity: Int = 90)
        -> (events: [NoteEvent], beats: Double)
    {
        let ch = UInt8(channel - 1)
        if o.together {
            let len = o.noteLength == 0 ? 4 : o.noteLength
            let unique = Array(Set(pitches)).sorted()
            return (unique.map { NoteEvent(channel: ch, pitch: $0, velocity: velocity, start: 0, length: len) }, len + 0.5)
        }
        let overlap = ListenOptions.legatoOverlapSeconds * bpm / 60
        let len = o.legato ? o.rate + overlap : (o.noteLength == 0 ? o.rate * 0.9 : o.noteLength)
        let events = pitches.enumerated().map { i, p in
            NoteEvent(channel: ch, pitch: p, velocity: velocity, start: Double(i) * o.rate, length: len)
        }
        return (events, Double(pitches.count) * o.rate + max(0, len - o.rate) + 0.5)
    }

    /// 순차 재생 순서: 내림차순이면 뒤집고, 오르내리기면 같은 길을 되짚어 돌아온다 (꼭대기 음은 한 번만).
    static func order(_ asc: [Int], _ o: ListenOptions) -> [Int] {
        var seq = o.descending ? Array(asc.reversed()) : asc
        if o.upDown { seq += seq.reversed().dropFirst() }
        return clamp(seq)
    }

    /// 스케일은 한 옥타브를 올라갔다가 다시 내려온다 (꼭대기 음은 한 번만). 청취 옵션 중 옥타브만 따른다.
    static func scalePitches(root: Int, type: ScaleType, octave: Int = 0) -> [Int] {
        let base = 60 + root - (root > 6 ? 12 : 0) + 12 * octave
        let asc = type.intervals.map { base + $0 } + [base + 12]
        return clamp(asc + asc.reversed().dropFirst())
    }

    /// 코드 순차 재생 음 목록: 구성음(옥타브/확장 적용)을 2옥타브, 내림차순, 오르내리기 옵션에 따라 늘어놓는다.
    static func chordSequence(_ voicing: [Int], _ o: ListenOptions) -> [Int] {
        var asc = shape(voicing, o)
        if o.twoOctaves { asc += asc.map { $0 + 12 } }
        return order(asc, o)
    }

    /// 스케일 듣기: 순서·간격·음 길이는 기본값(1/8 순차)으로 고정한다.
    static func scale(root: Int, type: ScaleType, channel: Int, octave: Int = 0, bpm: Double = 100) -> Song {
        let (events, beats) = play(scalePitches(root: root, type: type, octave: octave), channel: channel, o: ListenOptions(), bpm: bpm)
        return Song(title: "\(noteNames[root]) \(type.name)", bpm: bpm, events: events, totalBeats: beats)
    }

    /// 멜로디 듣기: 프레이즈를 선택한 Key 로 옮겨 연주한다. 유명 프레이즈는 원곡의 조성을, 에튀드는 선택한 스케일을 따른다.
    /// drums 가 꺼져 있지 않으면 프레이즈 길이만큼 리듬 채널로 함께 보낸다.
    static func melody(root: Int, scale: ScaleType, phrase: Phrase, channel: Int, drums: DrumPattern = .off, rhythmChannel: Int = 10,
                       options o: ListenOptions = ListenOptions(), bpm: Double = 100) -> Song {
        var events = phrase.notes(seed: o.varyMelody ? o.melodySeed : nil, in: scale).map {
            NoteEvent(channel: UInt8(channel - 1), pitch: phrase.pitch($0, root: root, userScale: scale) + 12 * o.octave,
                      velocity: 90, start: $0.beat, length: $0.length)
        }.filter { (0...127).contains($0.pitch) }
        let total = phrase.totalBeats
        events += drums.notes(start: 0, beats: total, channel: UInt8(rhythmChannel - 1))  // 3박자 프레이즈는 drums 가 없다 (Phrase init 불변식)
        let key = "\(noteNames[root]) \((phrase.scale ?? scale).name)"
        return Song(title: "\(phrase.name) · \(key)\(o.varyMelody ? " (변주)" : "")", bpm: bpm, events: events, totalBeats: total)
    }

    /// 코드 듣기: 코드 종류와 구성음만 들려준다 (코드 패턴과 무관).
    /// Sequential 은 음을 하나씩(2옥타브/내림차순/오르내리기 적용), Together 는 한 번에.
    static func chord(root: Int, quality: ChordQuality, channel: Int,
                      options o: ListenOptions = ListenOptions(), bpm: Double = 100) -> Song {
        let c = ChordSpec(root: root, quality: quality, beats: 4)
        let pitches = o.together ? shape(c.voicing, o) : chordSequence(c.voicing, o)
        let (events, beats) = play(pitches, channel: channel, o: o, bpm: bpm)
        return Song(title: c.symbol, bpm: bpm, events: events, totalBeats: beats)
    }

    /// 패턴 듣기(코드 진행): 진행의 코드마다 자기 박 수만큼 코드 패턴과 베이스를 깐다. 한 마디 안에서 코드가 바뀌면 패턴도 거기서 끊긴다.
    /// 슬래시 코드는 베이스 채널이 지정된 베이스 음을 친다.
    static func progression(root: Int, scale: ScaleType, prog: Theory.Progression, complexity: Int, pattern: ChordPattern,
                            channels: ChannelMap, drums: DrumPattern = .off,
                            options o: ListenOptions = ListenOptions(), bpm: Double = 90) -> Song {
        var events: [NoteEvent] = []
        var t = 0.0
        let chords = Theory.chords(of: prog, root: root, scale: scale, complexity: complexity)
        // 위 성부는 성부 이동이 작은 전위로 잇는다. 베이스는 따로 근음(또는 슬래시 베이스)을 친다.
        for (c, voicing) in zip(chords, Theory.voiceLead(chords.map(\.voicing))) {
            events += pattern.notes(pitches: shape(voicing, o), start: t, beats: c.beats,
                                    channel: UInt8(channels.chords - 1), velocity: 75)
            events.append(NoteEvent(channel: UInt8(channels.bass - 1), pitch: c.bassNote + 12 * o.octave, velocity: 90, start: t, length: c.beats * 0.95))
            t += c.beats
        }
        events += drums.notes(start: 0, beats: t, channel: UInt8(channels.rhythm - 1))
        return Song(title: prog.name, bpm: bpm, events: events.filter { (0...127).contains($0.pitch) }, totalBeats: t)
    }
}
