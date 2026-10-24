import Foundation

/// 프레이즈의 음 하나. degree 는 스케일 디그리(0 = 으뜸음, 음수는 아래), alter 는 반음 조정(임시표).
struct PhraseNote: Hashable {
    var degree: Int
    var alter = 0
    var beat: Double
    var length: Double
}

/// 멜로디 듣기용 프레이즈. 음색을 고를 때 귀에 익은 선율로 감을 잡는 것이 목적이라
/// 유명한 멜로디, 훅 라인, 테마의 클라이맥스를 그대로 담았다 (개인용 비공개 바이너리).
/// 유명 프레이즈는 원곡의 장/단조(scale)를 따르고 Key 만 선택한 Key 로 옮긴다. 에튀드(scale == nil)는 선택한 스케일을 따른다.
struct Phrase: Identifiable, Hashable {
    enum Category: String, CaseIterable {
        case classical = "클래식"
        case folk = "민요 · 캐럴"
        case hook = "훅 · 리프"
        case theme = "테마 · 클라이맥스"
        case game = "게임"
        case etude = "에튀드"
    }

    let name: String
    let category: Category
    /// 출처와 성격 (화면 표시용)
    let summary: String
    /// 원곡의 조성. nil 이면 현재 선택한 스케일을 따른다.
    let scale: ScaleType?
    /// 한 마디의 박 수 (3 또는 4). 전체 길이는 마디 단위로 올림한다.
    let meter: Int
    /// 함께 묶인 드럼 그루브. Groove 옵션을 켜면 이 패턴이 리듬 채널로 함께 나간다. 3박자나 클래식은 없음.
    let drums: DrumPattern?
    /// 곡 생성 프롬프트용 영문 성격 설명. 곡명은 넣지 않고 선율의 모양만 적는다.
    let character: String
    let notes: [PhraseNote]

    var id: String { name }

    /// 마디 단위로 올림한 전체 박 수. 셋잇단(1/3 박) 누적 오차로 마디 하나가 더 붙지 않게 1e-6 안은 같은 값으로 본다.
    var totalBeats: Double {
        let end = notes.map { $0.beat + $0.length }.max() ?? 0
        return max(Double(meter), ((end - 1e-6) / Double(meter)).rounded(.up) * Double(meter))
    }

    var bars: Int { Int(totalBeats) / meter }

    /// 곡 생성 프롬프트용 마디당 음 수 범위. 곡은 늘 4/4 이므로 3박자 프레이즈도 4박 기준으로 환산한다.
    /// 셋잇단을 쓰는 프레이즈면 분수 박이 허용된다는 힌트를 붙인다.
    var notesPerBar: String {
        let d = max(1, Int((Double(notes.count) / max(1, totalBeats) * 4).rounded()))
        let triplet = usesTriplets ? " (triplet eighths, fractional beats such as 0.333 are allowed)" : ""
        return "roughly \(max(1, d - 1)) to \(d + 1) notes per bar" + triplet
    }

    /// 1/3 박 격자에는 있고 1/2 박 격자에는 없는 음이 있으면 셋잇단
    var usesTriplets: Bool {
        notes.contains { n in
            let onThirds = abs(n.beat * 3 - (n.beat * 3).rounded()) < 1e-6
            let onHalves = abs(n.beat * 2 - (n.beat * 2).rounded()) < 1e-6
            return onThirds && !onHalves
        }
    }

    init(name: String, category: Category, summary: String, scale: ScaleType?, meter: Int, drums: DrumPattern?,
         character: String, notes: [PhraseNote]) {
        precondition(meter == 4 || drums == nil, "3박자 프레이즈에는 4/4 드럼을 묶을 수 없다: \(name)")
        self.name = name
        self.category = category
        self.summary = summary
        self.scale = scale
        self.meter = meter
        self.drums = drums
        self.character = character
        self.notes = notes
    }

    static func == (a: Phrase, b: Phrase) -> Bool { a.name == b.name }
    func hash(into h: inout Hasher) { h.combine(name) }

    /// seed 를 주면 같은 뼈대에서 약박의 음과 끝음을 조금씩 바꾼 변주를 만든다 (같은 seed 는 같은 결과).
    /// 마디 첫 박과 임시표가 붙은 음은 지키고, 나머지는 일정 확률로 이웃 스케일 음으로 바꾼다. 끝음은 안정음(1·3·5도)으로.
    func notes(seed: UInt64?, in userScale: ScaleType) -> [PhraseNote] {
        guard let seed, let last = notes.indices.max(by: { notes[$0].beat < notes[$1].beat }) else { return notes }
        let s = scale ?? userScale
        let n = s.intervals.count
        let stable = s.intervals.indices.filter { [0, 3, 4, 7].contains(s.intervals[$0]) }
        var rng = SplitMix64(seed: seed)
        let top = (notes.map(\.degree).max() ?? 0) + 1
        let bottom = (notes.map(\.degree).min() ?? 0) - 1
        return notes.enumerated().map { i, note in
            var v = note
            if i == last {
                let oct = Int((Double(note.degree) / Double(n)).rounded(.down))
                v.degree = oct * n + (stable.randomElement(using: &rng) ?? 0)
                v.alter = 0
                return v
            }
            guard note.alter == 0, note.beat.truncatingRemainder(dividingBy: Double(meter)) != 0,
                  Double.random(in: 0..<1, using: &rng) < 0.3 else { return note }
            v.degree = min(top, max(bottom, note.degree + (Bool.random(using: &rng) ? 1 : -1)))
            return v
        }
    }

    /// 디그리를 MIDI 음높이로. 으뜸음은 가운데 C 부근(60 + root, F# 이상은 한 옥타브 아래)에 둔다.
    static func pitch(_ note: PhraseNote, root: Int, scale: ScaleType) -> Int {
        let base = 60 + root - (root > 6 ? 12 : 0)
        let n = scale.intervals.count
        let oct = Int((Double(note.degree) / Double(n)).rounded(.down))
        return base + scale.intervals[note.degree - oct * n] + 12 * oct + note.alter
    }

    func pitch(_ note: PhraseNote, root: Int, userScale: ScaleType) -> Int {
        Self.pitch(note, root: root, scale: scale ?? userScale)
    }

    // MARK: 표기

    /// 간단한 표기로 프레이즈를 적는다. 토큰은 공백으로 나누고 `|` 는 읽기용 마디선이라 무시한다.
    /// 토큰: `디그리[#|b][/길이]` 또는 쉼표 `r[/길이]`. 길이를 생략하면 unit, `t` 는 셋잇단 8분음표(1/3박), `T` 는 셋잇단 4분음표(2/3박).
    /// 예: "2 2 3 4 | 4 3 2 1 | 0 0 1 2 | 2/1.5 1/.5 1/2"
    static func parse(_ text: String, unit: Double = 1) -> [PhraseNote] {
        var out: [PhraseNote] = []
        var t = 0.0
        for raw in text.split(whereSeparator: { $0 == " " || $0 == "\n" }) where raw != "|" {
            let parts = raw.split(separator: "/", maxSplits: 1)
            var len = unit
            if parts.count == 2 {
                switch parts[1] {
                case "t": len = 1.0 / 3
                case "T": len = 2.0 / 3
                default:
                    precondition(Double(parts[1]) != nil, "잘못된 프레이즈 길이: \(raw)")
                    len = Double(parts[1])!
                }
            }
            var head = String(parts[0])
            if head != "r" {
                var alter = 0
                while let c = head.last, c == "#" || c == "b" {
                    alter += c == "#" ? 1 : -1
                    head.removeLast()
                }
                precondition(Int(head) != nil, "잘못된 프레이즈 토큰: \(raw)")
                out.append(PhraseNote(degree: Int(head)!, alter: alter, beat: t, length: len))
            }
            t += len
        }
        return out
    }

    /// 16분음표로 4옥타브를 올라갔다 내려오는 분산화음 (맨 위 음은 한 번만).
    private static func rolled(_ shape: [Int], from: Int, octaves: Int, start: Double) -> [PhraseNote] {
        let up = (0..<octaves).flatMap { o in shape.map { from + $0 + 7 * o } }
        let seq = up + up.reversed().dropFirst()
        return seq.enumerated().map { PhraseNote(degree: $1, beat: start + Double($0) * 0.25, length: 0.22) }
    }

    // MARK: 카탈로그

    private static let major = Theory.scales[0]
    private static let minor = Theory.scales[1]

    static let all: [Phrase] = classical + folk + hooks + themes + games + etudes

    static func named(_ name: String) -> Phrase? { all.first { $0.name == name } }

    static func grouped() -> [(Category, [Phrase])] {
        Category.allCases.map { c in (c, all.filter { $0.category == c }) }
    }

    private static let classical: [Phrase] = [
        Phrase(name: "Ode to Joy", category: .classical, summary: "베토벤 교향곡 9번 · 장조 · 8마디 순차진행",
               scale: major, meter: 4, drums: nil,
               character: "hymn-like stepwise melody in even quarter notes within a fifth, phrases ending on the tonic",
               notes: parse("""
               2 2 3 4 | 4 3 2 1 | 0 0 1 2 | 2/1.5 1/.5 1/2
               2 2 3 4 | 4 3 2 1 | 0 0 1 2 | 1/1.5 0/.5 0/2
               """)),
        Phrase(name: "Für Elise", category: .classical, summary: "베토벤 · 단조 · 16분음표 트릴 동기",
               scale: minor, meter: 3, drums: nil,
               character: "a delicate rocking semitone trill figure that falls into an arpeggio, light and lyrical",
               notes: parse("""
               11 10# 11 10# 11 8 10 9 7/.5 r 2 4 7 8/.5 r 4 6# 8 9/.5 r 4
               11 10# 11 10# 11 8 10 9 7/.5 r 2 4 7 8/.5 r 4 9 8 7/1
               """, unit: 0.25)),
        Phrase(name: "Canon in D", category: .classical, summary: "파헬벨 · 장조 · 2분음표 하행 선율",
               scale: major, meter: 4, drums: nil,
               character: "slow descending stepwise line in half notes over a ground bass, serene",
               notes: parse("9 8 7 6 5 4 5 6", unit: 2)),
        Phrase(name: "Eine kleine Nachtmusik", category: .classical, summary: "모차르트 · 장조 · 도약하는 팡파르 동기",
               scale: major, meter: 4, drums: nil,
               character: "bright fanfare motif leaping between tonic and dominant, crisp and detached",
               notes: parse("""
               7/1 r 4 7/1 r 4 | 7 4 7 9 11/2 | 10/1 r 8 10/1 r 8 | 10 8 6 8 4/2
               """, unit: 0.5)),
        Phrase(name: "Minuet in G", category: .classical, summary: "바흐 (페촐트) · 장조 · 3박자 8마디",
               scale: major, meter: 3, drums: nil,
               character: "graceful minuet feel mixing quarter notes with running eighths, light and courtly",
               notes: parse("""
               11 7/.5 8/.5 9/.5 10/.5 | 11 7 7 | 12 10/.5 11/.5 12/.5 13/.5 | 14 7 7
               10 11/.5 10/.5 9/.5 8/.5 | 9 10/.5 9/.5 8/.5 7/.5 | 6 7/.5 8/.5 9/.5 7/.5 | 9 8/2
               """)),
        Phrase(name: "Symphony No. 5", category: .classical, summary: "베토벤 운명 · 단조 · 짧은-짧은-짧은-긴 동기",
               scale: minor, meter: 4, drums: nil,
               character: "a terse short-short-short-long motif repeated a step lower, dramatic and forceful",
               notes: parse("r 4 4 4 2/2 | r 3 3 3 1/4", unit: 0.5)),
        Phrase(name: "Moonlight Sonata", category: .classical, summary: "베토벤 · 단조 · 셋잇단 분산화음 반주형",
               scale: minor, meter: 4, drums: nil,
               character: "slow continuous triplet arpeggios that barely move, hushed and nocturnal",
               notes: parse("""
               -3 0 2 -3 0 2 -3 0 2 -3 0 2 | -3 0 2 -3 0 2 -3 0 2 -3 0 2
               -2 0 2 -2 0 2 -2 1 3 -2 1 3 | -3 -1# 3 -3 -1# 3 -3 0 2 -3 0 2
               """, unit: 1.0 / 3)),
        Phrase(name: "In the Hall of the Mountain King", category: .classical, summary: "그리그 · 단조 · 순차 상행 리프",
               scale: minor, meter: 4, drums: nil,
               character: "creeping stepwise riff in eighth notes that climbs and repeats, building menace",
               notes: parse("""
               0 1 2 3 4 2 4/1 | 4b/1 2/1 4b/2 | 3/1 1/1 3/2 | 0 1 2 3 4 2 4 7 | 6 4 2 4 6/2
               """, unit: 0.5)),
    ]

    private static let folk: [Phrase] = [
        Phrase(name: "Twinkle Twinkle", category: .folk, summary: "동요 · 장조 · 4마디",
               scale: major, meter: 4, drums: nil,
               character: "simple nursery tune in repeated quarter notes, rising a fifth then stepping back down",
               notes: parse("0 0 4 4 5 5 4/2 | 3 3 2 2 1 1 0/2")),
        Phrase(name: "Happy Birthday", category: .folk, summary: "생일 축하 · 장조 · 3박자",
               scale: major, meter: 3, drums: nil,
               character: "a celebratory tune with dotted pickups and an octave leap at the climax",
               notes: parse("""
               4/.75 4/.25 | 5 4 7 | 6/2 4/.75 4/.25 | 5 4 8 | 7/2 4/.75 4/.25
               11 9 7 | 6 5 10/.75 10/.25 | 9 7 8 | 7/2
               """)),
        Phrase(name: "Amazing Grace", category: .folk, summary: "찬송가 · 장조(5음) · 3박자",
               scale: major, meter: 3, drums: nil,
               character: "pentatonic hymn with long held notes and gentle leaps, warm and unhurried",
               notes: parse("""
               4 | 7/2 9/.5 7/.5 | 9/2 8 | 7/2 5 | 4/2 4 | 7/2 9/.5 7/.5 | 9/2 8 | 11/3
               """)),
        Phrase(name: "Jingle Bells", category: .folk, summary: "캐럴 · 장조 · 후렴 8마디",
               scale: major, meter: 4, drums: .rock,
               character: "bouncy repeated-note chorus with short phrases and a cheerful lift at the end",
               notes: parse("""
               9 9 9/2 | 9 9 9/2 | 9 11 7/1.5 8/.5 | 9/4
               10 10 10/1.5 10/.5 | 10 9 9 9/.5 9/.5 | 9 8 8 9 | 8/2 11/2
               """)),
        Phrase(name: "Greensleeves", category: .folk, summary: "영국 민요 · 단조 · 6/8",
               scale: minor, meter: 3, drums: nil,
               character: "lilting minor folk melody with raised leading tones at cadences, wistful",
               notes: parse("""
               7 | 9/1 10/.5 11/1 12/.5 | 11/1 10/.5 8/1 6/.5 | 7/1 8/.5 9/1 7/.5 | 7/1 6#/.5 7/1 8/.5
               6#/1.5 4/1 7/.5 | 9/1 10/.5 11/1 12/.5 | 11/1 10/.5 8/1 6/.5 | 7/1 8/.5 9/.5 8/.5 7/.5
               6#/1 5#/.5 6#/1.5 | 7/3
               """)),
        Phrase(name: "Silent Night", category: .folk, summary: "캐럴 · 장조 · 3박자",
               scale: major, meter: 3, drums: nil,
               character: "gentle lullaby with dotted rhythms, long notes and a soft descent to the tonic",
               notes: parse("""
               4/1.5 5/.5 4 2/3 | 4/1.5 5/.5 4 2/3 | 8/2 8 6/3 | 7/2 7 4/3
               7 4 2 | 4/1.5 3/.5 1 | 0/3 r/3
               """)),
    ]

    private static let hooks: [Phrase] = [
        Phrase(name: "Seven Nation Army", category: .hook, summary: "The White Stripes · 단조 · 7음 리프",
               scale: minor, meter: 4, drums: .rock,
               character: "a heavy seven-note minor riff on the tonic, repeated verbatim like a chant",
               notes: parse("0/1.5 0/.5 2/.5 0/.5 -1/1 -2/3 -3/1 | 0/1.5 0/.5 2/.5 0/.5 -1/1 -2/3 -3/1")),
        Phrase(name: "Smoke on the Water", category: .hook, summary: "Deep Purple · 단조(블루스) · 4마디 리프",
               scale: minor, meter: 4, drums: .rock,
               character: "a blunt blues-rock riff of parallel fourths climbing a minor third and fourth with a chromatic bend",
               notes: parse("0 2 3/2 | 0 2 3#/.5 3/1.5 | 0 2 3/2 | 2 0/3")),
        Phrase(name: "Sweet Child O' Mine", category: .hook, summary: "Guns N' Roses · 장조 · 8분음표 분산 리프",
               scale: major, meter: 4, drums: .rock,
               character: "wide-leaping eighth-note arpeggio riff circling a high pedal tone, ringing and bright",
               notes: parse("""
               7 14 11 10 17 11 16 11 | 7 14 11 10 17 11 16 11 | 8 14 11 10 17 11 16 11 | 8 14 11 10 17 11 16 11
               """, unit: 0.5)),
        Phrase(name: "Take On Me", category: .hook, summary: "a-ha · 장조 · 신스 훅",
               scale: major, meter: 4, drums: .fourOnFloor,
               character: "fast staccato synth hook of repeated notes and skips in eighths, upbeat 80s pop",
               notes: parse("""
               12 12 10 8 r 8 r 11 r 11 r 11 13 13 14 15 | 14 14 14 11 r 10 r 12 r 12 r 12 11 r 11 12
               """, unit: 0.5)),
        Phrase(name: "Clocks", category: .hook, summary: "Coldplay · 장조 · 3+3+2 하행 아르페지오",
               scale: major, meter: 4, drums: .rock,
               character: "cascading descending piano arpeggio in eighth notes grouped 3+3+2 over shifting chords",
               notes: parse("""
               7 4 2 7 4 2 7 4 | 7 4 2 7 4 2 7 4 | 6b 4 1 6b 4 1 6b 4 | 6b 4 1 6b 4 1 6b 4
               5 3b 1 5 3b 1 5 3b | 5 3b 1 5 3b 1 5 3b | 5 3b 1 5 3b 1 5 3b | 5 3b 1 5 3b 1 5 3b
               """, unit: 0.5)),
        Phrase(name: "Axel F", category: .hook, summary: "Harold Faltermeyer · 단조 · 신스 리드",
               scale: minor, meter: 4, drums: .fourOnFloor,
               character: "syncopated synth lead riff hopping between the tonic and chord tones with sixteenth pickups",
               notes: parse("""
               0/.75 2/.75 0/.5 0/.25 3/.5 0/.5 -1/.75 | 0/.75 4/.75 0/.5 0/.25 5/.5 4/.5 2/.75
               0/.5 4/.5 7/.5 0/.5 6/.5 6/.5 4/.5 1/.5 | 0/2 r/2
               """)),
        Phrase(name: "Pink Panther", category: .hook, summary: "Henry Mancini · 단조 · 반음계 재즈 리프",
               scale: minor, meter: 4, drums: .swing,
               character: "sneaky chromatic jazz riff with semitone slides into long notes, swung and sly",
               notes: parse("""
               r/1.5 -1#/.5 0/1.5 r/.5 1/.5 2/1.5 r/.5 -1# 0 1 2 5 4 7 9 11 11b/3 r/2
               """, unit: 0.5)),
    ]

    private static let themes: [Phrase] = [
        Phrase(name: "Also sprach Zarathustra", category: .theme, summary: "R. 슈트라우스 · 장조 · 5도-옥타브 팡파르",
               scale: major, meter: 4, drums: nil,
               character: "a fanfare rising through the open fifth and octave in long notes, ending on a dramatic third",
               notes: parse("0/4 4/4 7/4 9/1 9b/3 | 0/4 4/4 7/4 9b/1 9/3")),
        Phrase(name: "Star Wars", category: .theme, summary: "존 윌리엄스 메인 테마 · 장조 · 셋잇단 픽업",
               scale: major, meter: 4, drums: nil,
               character: "heroic brass theme with triplet pickups leaping a fifth and an octave, broad and triumphant",
               notes: parse("""
               r/3 4/t 4/t 4/t | 7/2 11/2 | 10/t 9/t 8/t 14/2 11/1 | 10/t 9/t 8/t 14/2 11/1 | 10/t 9/t 10/t 8/3
               """)),
        Phrase(name: "Hedwig's Theme", category: .theme, summary: "존 윌리엄스 · 단조 · 3박자 왈츠",
               scale: minor, meter: 3, drums: nil,
               character: "a mysterious waltz-like theme with wide leaps and chromatic colour, like a music box",
               notes: parse("""
               r/2 4 | 7/1.5 9/.5 8 | 7/2 11 | 10/3 | 8/3 | 7/1.5 9/.5 8 | 6#/2 8b | 4/3
               """)),
        Phrase(name: "He's a Pirate", category: .theme, summary: "캐리비안의 해적 · 단조 · 6/8 돌진",
               scale: minor, meter: 3, drums: nil,
               character: "driving minor theme in repeated stepwise cells with a pickup, relentless and swashbuckling",
               notes: parse("""
               r/2 -3/.5 -3/.5 | 0 0/.5 1/.5 2 | 2 3/.5 1 1/.5 | 0/.5 -1/.5 0 -3/.5 -3/.5
               0 0/.5 1/.5 2 | 2 3/.5 1 1/.5 | 0/.5 -1#/.5 0/2
               """)),
        Phrase(name: "Over the Rainbow", category: .theme, summary: "오즈의 마법사 · 장조 · 옥타브 도약 클라이맥스",
               scale: major, meter: 4, drums: .ballad,
               character: "a ballad opening with an octave leap on long notes, then settling by step, tender and expansive",
               notes: parse("0/2 7/2 | 6/1 4/.5 5/.5 6/1 7/1 | 0/2 5/2 | 4/4")),
    ]

    private static let games: [Phrase] = [
        Phrase(name: "Super Mario Bros.", category: .game, summary: "지상 테마 · 장조 · 당김음",
               scale: major, meter: 4, drums: .rock,
               character: "a playful syncopated chiptune melody with repeated notes, skips and a triplet lift",
               notes: parse("""
               9 9 r 9 r 7 9 r | 11/1.5 r/.5 4/1.5 r/.5 | 7/1.5 4/1.5 2/1.5 5/1 6/1 6b/.5 5/1
               4/T 9/T 11/T 12/1 10/.5 11/.5 | 9/1.5 7/.5 8/.5 6/1.5
               """, unit: 0.5)),
        Phrase(name: "Tetris", category: .game, summary: "Korobeiniki · 단조 · 8마디",
               scale: minor, meter: 4, drums: .fourOnFloor,
               character: "brisk folk-dance melody in a minor key with quick stepwise turns and repeated tonic hits",
               notes: parse("""
               11 8/.5 9/.5 10 9/.5 8/.5 | 7 7/.5 9/.5 11 10/.5 9/.5 | 8/1.5 9/.5 10 11 | 9 7 7 r
               r/.5 10 12/.5 14 13/.5 12/.5 | 11/1.5 9/.5 11 10/.5 9/.5 | 8 8/.5 9/.5 10 11 | 9 7 7 r
               """)),
        Phrase(name: "Final Fantasy Prelude", category: .game, summary: "16분음표 4옥타브 분산화음 · 장조",
               scale: major, meter: 4, drums: nil,
               character: "flowing sixteenth-note arpeggios sweeping up and down four octaves, dreamy and harp-like",
               notes: rolled([0, 1, 2, 4], from: -14, octaves: 4, start: 0) + rolled([-2, -1, 0, 2], from: -14, octaves: 4, start: 8)),
    ]

    /// 음색의 기계적인 면을 시험하는 패턴. 선택한 스케일을 따른다.
    private static let etudes: [Phrase] = [
        Phrase(name: "Scale Run", category: .etude, summary: "스케일을 따라 오르내리는 8분음표 런 · 현재 스케일",
               scale: nil, meter: 4, drums: nil,
               character: "stepwise eighth-note scale runs going up and down",
               notes: (0..<32).map { k in
                   let m = k % 14
                   return PhraseNote(degree: m <= 7 ? m : 14 - m, beat: Double(k) * 0.5, length: 0.45)
               }),
        Phrase(name: "Arpeggio", category: .etude, summary: "코드톤을 넓게 도약하는 8분음표 · 현재 스케일",
               scale: nil, meter: 4, drums: nil,
               character: "chord tones outlined with wide leaps and arpeggiated figures",
               notes: (0..<32).map { k in
                   let shapes = [0, 2, 4, 7, 4, 2], roots = [0, 5, 3, 4]
                   return PhraseNote(degree: roots[k / 8] + shapes[k % shapes.count], beat: Double(k) * 0.5, length: 0.45)
               }),
        Phrase(name: "Triplet Run", category: .etude, summary: "셋잇단 8분음표로 물결치는 런 · 현재 스케일",
               scale: nil, meter: 4, drums: nil,
               character: "flowing eighth-note triplet runs that rise and fall",
               notes: {
                   let wave = [0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 0, 1]
                   return (0..<3).flatMap { bar in
                       wave.enumerated().map { k, d in PhraseNote(degree: d + bar, beat: Double(bar) * 4 + Double(k) / 3, length: 0.3) }
                   } + [PhraseNote(degree: 2, beat: 12, length: 1), PhraseNote(degree: 1, beat: 13, length: 1), PhraseNote(degree: 0, beat: 14, length: 2)]
               }()),
        Phrase(name: "Pentatonic Riff", category: .etude, summary: "5음 위주의 짧은 리프를 반복 · 현재 스케일",
               scale: nil, meter: 4, drums: .funk,
               character: "a short pentatonic-flavored riff that repeats and changes at the end",
               notes: parse("""
               0 1 2 4 5/1 4 2 | 0 1 2 4 5/1 4 2 | 0 1 2 4 5/1 4 2 | 5 4 2 1 0/2
               """, unit: 0.5)),
        Phrase(name: "Long Tones", category: .etude, summary: "긴 음과 쉼표, 여백이 많은 선율 · 현재 스케일",
               scale: nil, meter: 4, drums: nil,
               character: "long sustained notes, generous rests and space",
               notes: parse("0/3 r/1 4/2.5 r/1.5 2/3 r/1 0/4")),
    ]
}

/// 변주를 재현 가능하게 만드는 작은 시드 난수 생성기.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
