import Foundation

let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

func pitchClass(of name: String) -> Int? {
    let s = name.trimmingCharacters(in: .whitespaces)
    guard let first = s.first, let base = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][String(first).uppercased()] else {
        return nil
    }
    var pc = base
    for ch in s.dropFirst() {
        if ch == "#" || ch == "♯" { pc += 1 } else if ch == "b" || ch == "♭" { pc -= 1 }
    }
    return ((pc % 12) + 12) % 12
}

struct ScaleType: Identifiable, Hashable {
    let name: String
    let intervals: [Int]
    var id: String { name }
}

struct ChordQuality: Identifiable, Hashable {
    let symbol: String
    let intervals: [Int]
    /// 1 = triad, 2 = seventh, 3 = 9th / suspended, 4 = 11th / 13th, 5 = altered / jazz
    let complexity: Int
    var id: String { symbol }
}

enum Theory {
    static let scales: [ScaleType] = [
        ScaleType(name: "Major", intervals: [0, 2, 4, 5, 7, 9, 11]),
        ScaleType(name: "Natural Minor", intervals: [0, 2, 3, 5, 7, 8, 10]),
        ScaleType(name: "Harmonic Minor", intervals: [0, 2, 3, 5, 7, 8, 11]),
        ScaleType(name: "Melodic Minor", intervals: [0, 2, 3, 5, 7, 9, 11]),
        ScaleType(name: "Major Pentatonic", intervals: [0, 2, 4, 7, 9]),
        ScaleType(name: "Minor Pentatonic", intervals: [0, 3, 5, 7, 10]),
        ScaleType(name: "Blues", intervals: [0, 3, 5, 6, 7, 10]),
        ScaleType(name: "Dorian", intervals: [0, 2, 3, 5, 7, 9, 10]),
        ScaleType(name: "Phrygian", intervals: [0, 1, 3, 5, 7, 8, 10]),
        ScaleType(name: "Lydian", intervals: [0, 2, 4, 6, 7, 9, 11]),
        ScaleType(name: "Mixolydian", intervals: [0, 2, 4, 5, 7, 9, 10]),
        ScaleType(name: "Diminished (W-H)", intervals: [0, 2, 3, 5, 6, 8, 9, 11]),
        ScaleType(name: "Diminished (H-W)", intervals: [0, 1, 3, 4, 6, 7, 9, 10]),
        ScaleType(name: "Whole Tone", intervals: [0, 2, 4, 6, 8, 10]),
    ]

    static let chordQualities: [ChordQuality] = [
        ChordQuality(symbol: "maj", intervals: [0, 4, 7], complexity: 1),
        ChordQuality(symbol: "min", intervals: [0, 3, 7], complexity: 1),
        ChordQuality(symbol: "dim", intervals: [0, 3, 6], complexity: 1),
        ChordQuality(symbol: "aug", intervals: [0, 4, 8], complexity: 1),
        ChordQuality(symbol: "maj7", intervals: [0, 4, 7, 11], complexity: 2),
        ChordQuality(symbol: "min7", intervals: [0, 3, 7, 10], complexity: 2),
        ChordQuality(symbol: "7", intervals: [0, 4, 7, 10], complexity: 2),
        ChordQuality(symbol: "m7b5", intervals: [0, 3, 6, 10], complexity: 2),
        ChordQuality(symbol: "dim7", intervals: [0, 3, 6, 9], complexity: 2),
        ChordQuality(symbol: "6", intervals: [0, 4, 7, 9], complexity: 2),
        ChordQuality(symbol: "min6", intervals: [0, 3, 7, 9], complexity: 2),
        ChordQuality(symbol: "sus2", intervals: [0, 2, 7], complexity: 3),
        ChordQuality(symbol: "sus4", intervals: [0, 5, 7], complexity: 3),
        ChordQuality(symbol: "7sus4", intervals: [0, 5, 7, 10], complexity: 3),
        ChordQuality(symbol: "add9", intervals: [0, 4, 7, 14], complexity: 3),
        ChordQuality(symbol: "m(add9)", intervals: [0, 3, 7, 14], complexity: 3),
        ChordQuality(symbol: "maj9", intervals: [0, 4, 7, 11, 14], complexity: 3),
        ChordQuality(symbol: "min9", intervals: [0, 3, 7, 10, 14], complexity: 3),
        ChordQuality(symbol: "9", intervals: [0, 4, 7, 10, 14], complexity: 3),
        // 4: 11th / 13th 계열
        ChordQuality(symbol: "9sus4", intervals: [0, 5, 7, 10, 14], complexity: 4),
        ChordQuality(symbol: "11", intervals: [0, 4, 7, 10, 14, 17], complexity: 4),
        ChordQuality(symbol: "min11", intervals: [0, 3, 7, 10, 14, 17], complexity: 4),
        ChordQuality(symbol: "13", intervals: [0, 4, 7, 10, 14, 21], complexity: 4),
        ChordQuality(symbol: "maj13", intervals: [0, 4, 7, 11, 14, 21], complexity: 4),
        ChordQuality(symbol: "6/9", intervals: [0, 4, 7, 9, 14], complexity: 4),
        ChordQuality(symbol: "maj7#11", intervals: [0, 4, 7, 11, 18], complexity: 4),
        // 5: 얼터드 / 재즈 색채
        ChordQuality(symbol: "7b9", intervals: [0, 4, 7, 10, 13], complexity: 5),
        ChordQuality(symbol: "7#9", intervals: [0, 4, 7, 10, 15], complexity: 5),
        ChordQuality(symbol: "7#11", intervals: [0, 4, 7, 10, 18], complexity: 5),
        ChordQuality(symbol: "7b13", intervals: [0, 4, 7, 10, 20], complexity: 5),
        ChordQuality(symbol: "7alt", intervals: [0, 4, 6, 10, 13, 15], complexity: 5),
        ChordQuality(symbol: "mMaj7", intervals: [0, 3, 7, 11], complexity: 5),
        ChordQuality(symbol: "quartal", intervals: [0, 5, 10, 15], complexity: 5),
    ]

    static let complexityNames = ["", "Triad", "7th", "9th/sus", "11th/13th", "Altered"]
    static let maxComplexity = 5

    private static let aliases: [String: String] = [
        "": "maj", "major": "maj", "m": "min", "minor": "min", "-": "min",
        "°": "dim", "o": "dim", "+": "aug", "dom7": "7", "m7": "min7", "-7": "min7",
        "M7": "maj7", "major7": "maj7", "ø": "m7b5", "min7b5": "m7b5", "°7": "dim7",
        "m9": "min9", "dom9": "9", "major9": "maj9", "suspended4": "sus4", "suspended2": "sus2",
        "m6": "min6", "madd9": "m(add9)", "min(add9)": "m(add9)", "sus": "sus4", "7sus": "7sus4", "9sus": "9sus4",
        "m11": "min11", "dom11": "11", "dom13": "13", "major13": "maj13", "69": "6/9", "maj7#11": "maj7#11",
        "alt": "7alt", "m(maj7)": "mMaj7", "minmaj7": "mMaj7", "mmaj7": "mMaj7", "7#9": "7#9",
    ]

    static func quality(named raw: String) -> ChordQuality? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let q = chordQualities.first(where: { $0.symbol == s }) { return q }
        if let mapped = aliases[s] ?? aliases[s.lowercased()] {
            return chordQualities.first { $0.symbol == mapped }
        }
        return chordQualities.first { $0.symbol == s.lowercased() }
    }

    static func quality(matching intervals: [Int]) -> ChordQuality? {
        chordQualities.first { $0.intervals == intervals }
    }

    /// 스케일 위에 3도씩 쌓은 다이아토닉 코드의 root 이후 상대 음정들.
    static func diatonicIntervals(scale: ScaleType, degree: Int, complexity: Int) -> [Int] {
        let n = scale.intervals.count
        let count = min(7, max(1, complexity) + 2)  // 3화음, 7th, 9th, 11th, 13th
        let base = scale.intervals[degree % n]
        return (0..<count).map { k in
            let idx = degree + 2 * k
            return scale.intervals[idx % n] + 12 * (idx / n) - base
        }
    }

    /// 고정 코드의 종류. 3도를 쌓을 7음 모드를 정하므로 복잡도(3화음 → 7th → 9th …)가 그대로 적용된다.
    enum ChordFamily: Hashable {
        case major, minor, dominant, diminished, halfDiminished

        var stack: [Int] {
            switch self {
            case .major: return [0, 2, 4, 6, 7, 9, 11]  // Lydian: 11도는 #11 (maj7#11)
            case .minor: return [0, 2, 3, 5, 7, 9, 10]  // Dorian
            case .dominant: return [0, 2, 4, 5, 7, 9, 10]  // Mixolydian
            case .diminished: return [0, 2, 3, 5, 6, 8, 9]  // dim7 까지 감7도
            case .halfDiminished: return [0, 2, 3, 5, 6, 8, 10]  // Locrian ♮2 (m7b5, m9b5)
            }
        }
    }

    /// 진행의 코드 하나. degree 는 스케일 디그리(0-based), alter 는 근음 반음 조정(bVII 등).
    /// 종류는 셋 중 하나로 정한다: quality(카탈로그 심볼로 고정, 복잡도만큼 음 수를 자름) > family(종류별 모드 위에 3도 쌓기) > 스케일 위 다이아토닉.
    /// bass 가 있으면 베이스는 그 디그리(+ bassAlter)를 친다 (슬래시 코드 · 하행 베이스 라인).
    struct ChordStep: Hashable {
        var degree: Int
        var alter = 0
        var family: ChordFamily? = nil
        var quality: String? = nil
        var bass: Int? = nil
        var bassAlter = 0
        var beats: Double = 4
    }

    /// 코드 진행. scale 이 nil 이면 현재 선택한 스케일 위에서 다이아토닉으로 풀고(기본 진행),
    /// 있으면 원곡의 조성으로 고정하고 Key 만 옮긴다(모던 팝 · 유명 코드 라인). drums 는 함께 묶인 드럼 그루브(Groove 옵션).
    struct Progression: Identifiable, Hashable {
        enum Group: String, CaseIterable {
            case basic = "기본"
            case modern = "모던 팝"
            case famous = "유명 코드 라인"
        }

        let name: String
        let group: Group
        let summary: String
        let scale: ScaleType?
        let steps: [ChordStep]
        let drums: DrumPattern?
        var id: String { name }

        var totalBeats: Double { steps.reduce(0) { $0 + $1.beats } }

        static func == (a: Progression, b: Progression) -> Bool { a.name == b.name }
        func hash(into h: inout Hasher) { h.combine(name) }
    }

    /// 진행을 Key · 스케일 · 복잡도에 맞는 코드로 푼다.
    static func chords(of prog: Progression, root: Int, scale userScale: ScaleType, complexity: Int) -> [ChordSpec] {
        let s = prog.scale ?? userScale
        let n = s.intervals.count
        func pc(_ degree: Int, _ alter: Int) -> Int { (root + s.intervals[degree % n] + alter + 120) % 12 }
        return prog.steps.map { st in
            let ivs: [Int]
            if let name = st.quality, let q = quality(named: name) {
                ivs = trimmed(q, complexity: complexity)
            } else if let f = st.family {
                ivs = diatonicIntervals(scale: ScaleType(name: "", intervals: f.stack), degree: 0, complexity: complexity)
            } else {
                ivs = diatonicIntervals(scale: s, degree: st.degree, complexity: complexity)
            }
            let q = quality(matching: ivs) ?? ChordQuality(symbol: "", intervals: ivs, complexity: complexity)
            return ChordSpec(root: pc(st.degree, st.alter), quality: q, beats: st.beats, bass: st.bass.map { pc($0, st.bassAlter) })
        }
    }

    /// 고정 심볼 코드를 복잡도에 맞게 줄인다. 음 수 상한(복잡도 + 2) 안에서 카탈로그에 있는 가장 긴 앞부분을 쓰고,
    /// 앞부분이 카탈로그에 없으면(7alt 의 [0,4,6] 처럼 중요도 순이 아닌 심볼) 3도 · 7도로 종류를 추론해 그 패밀리로 쌓는다.
    static func trimmed(_ q: ChordQuality, complexity: Int) -> [Int] {
        let cap = max(3, min(q.intervals.count, complexity + 2))
        if cap == q.intervals.count { return q.intervals }
        if let hit = (3...cap).reversed().lazy.map({ Array(q.intervals.prefix($0)) }).first(where: { quality(matching: $0) != nil }) {
            return hit
        }
        let minor = q.intervals.contains(3), flatFive = q.intervals.contains(6), seventh = q.intervals.contains(10)
        let family: ChordFamily = minor ? (flatFive ? (seventh ? .halfDiminished : .diminished) : .minor) : (seventh ? .dominant : .major)
        return diatonicIntervals(scale: ScaleType(name: "", intervals: family.stack), degree: 0, complexity: complexity)
    }

    /// 코드열의 보이싱을 성부 이동이 가장 작은 전위로 고른다 (패턴 듣기용). 베이스는 따로 치므로 위 성부는 어느 전위든 된다.
    /// 후보는 각 전위를 옥타브 위아래로 옮긴 것 중 50...86 에 드는 것, 비용은 이전 보이싱과의 양방향 최근접 거리 합에 가운데(center)로 당기는 항을 더한 값.
    static func voiceLead(_ voicings: [[Int]], center: Int = 66) -> [[Int]] {
        var out: [[Int]] = []
        var prev: [Int]? = nil
        for v in voicings {
            let base = v.sorted()
            guard !base.isEmpty else { out.append(base); continue }
            var candidates: [[Int]] = []
            for k in base.indices {
                let inv = (Array(base[k...]) + base[..<k].map { $0 + 12 }).sorted()
                for shift in [-12, 0, 12] { candidates.append(inv.map { $0 + shift }) }
            }
            candidates = candidates.filter { $0.first! >= 50 && $0.last! <= 86 }
            if candidates.isEmpty { candidates = [base] }
            func cost(_ c: [Int]) -> Double {
                let pull = abs(Double(c.reduce(0, +)) / Double(c.count) - Double(center))
                guard let p = prev else { return pull }
                func nearest(_ x: Int, in ys: [Int]) -> Int { ys.map { abs(x - $0) }.min() ?? 0 }
                var move = 0
                for x in c { move += nearest(x, in: p) }
                for y in p { move += nearest(y, in: c) }
                return Double(move) + 0.25 * pull
            }
            let best = candidates.min { cost($0) < cost($1) }!
            out.append(best)
            prev = best
        }
        return out
    }

    static func progressionsGrouped() -> [(Progression.Group, [Progression])] {
        Progression.Group.allCases.map { g in (g, progressions.filter { $0.group == g }) }
    }

    private static func basic(_ name: String, _ degrees: [Int], _ summary: String, drums: DrumPattern?) -> Progression {
        Progression(name: name, group: .basic, summary: summary, scale: nil,
                    steps: degrees.map { ChordStep(degree: $0) }, drums: drums)
    }

    // 고정 코드 표기 도우미. M/m/dom/ø/dim 은 종류(복잡도 따라 확장), q 는 카탈로그 심볼 고정, 슬래시는 bass 디그리.
    private static func M(_ d: Int, _ beats: Double = 4, alter: Int = 0, bass: Int? = nil, bassAlter: Int = 0) -> ChordStep {
        ChordStep(degree: d, alter: alter, family: .major, bass: bass, bassAlter: bassAlter, beats: beats)
    }
    private static func m(_ d: Int, _ beats: Double = 4, bass: Int? = nil) -> ChordStep { ChordStep(degree: d, family: .minor, bass: bass, beats: beats) }
    private static func dom(_ d: Int, _ beats: Double = 4, alter: Int = 0, bass: Int? = nil) -> ChordStep {
        ChordStep(degree: d, alter: alter, family: .dominant, bass: bass, beats: beats)
    }
    private static func ø(_ d: Int, _ beats: Double = 4) -> ChordStep { ChordStep(degree: d, family: .halfDiminished, beats: beats) }
    private static func dim(_ d: Int, _ beats: Double = 4, alter: Int = 0) -> ChordStep { ChordStep(degree: d, alter: alter, family: .diminished, beats: beats) }
    private static func q(_ d: Int, _ quality: String, _ beats: Double = 4, alter: Int = 0, bass: Int? = nil, bassAlter: Int = 0) -> ChordStep {
        ChordStep(degree: d, alter: alter, quality: quality, bass: bass, bassAlter: bassAlter, beats: beats)
    }

    private static func modern(_ name: String, _ scale: ScaleType, _ steps: [ChordStep], _ summary: String, drums: DrumPattern?) -> Progression {
        Progression(name: name, group: .modern, summary: summary, scale: scale, steps: steps, drums: drums)
    }

    private static func famous(_ name: String, _ scale: ScaleType, _ steps: [ChordStep], _ summary: String, drums: DrumPattern?) -> Progression {
        Progression(name: name, group: .famous, summary: summary, scale: scale, steps: steps, drums: drums)
    }

    static let progressions: [Progression] = {
        let major = scales[0], minor = scales[1]
        return [
            // 기본: 현재 스케일 위의 다이아토닉, 한 마디 한 코드
            basic("I–V–vi–IV", [0, 4, 5, 3], "Axis 팝 4코드 (Let It Be, Don't Stop Believin')", drums: .rock),
            basic("I–vi–IV–V", [0, 5, 3, 4], "50s 두왑 (Stand by Me, Earth Angel)", drums: .ballad),
            basic("ii–V–I", [1, 4, 0], "재즈 종지", drums: .swing),
            basic("I–IV–V–I", [0, 3, 4, 0], "기본 종지", drums: .rock),
            basic("vi–IV–I–V", [5, 3, 0, 4], "감성 4코드 (Africa, Despacito)", drums: .fourOnFloor),
            basic("I–iii–IV–V", [0, 2, 3, 4], "iii 로 부드럽게 오르는 팝 진행", drums: .ballad),
            basic("i–VI–III–VII", [0, 5, 2, 6], "단조 팝/록 (Numb, Zombie)", drums: .rock),
            basic("i–iv–v–i", [0, 3, 4, 0], "단조 기본 종지", drums: .ballad),
            basic("i–VII–VI–VII", [0, 6, 5, 6], "단조 록 · 시네마틱", drums: .rock),
            // 모던 팝: 슬래시 코드와 하행 베이스, sus → 해결, 경과 감7, 세컨더리 도미넌트, 텐션, 차용 화음. 보이싱은 성부 진행으로 잇는다.
            modern("Axis Lush", major,
                   [q(0, "add9"), q(4, "sus4", 2), M(4, 2), q(5, "m(add9)"), q(3, "maj9"),
                    q(1, "min9"), q(4, "sus4", 2), dom(4, 2), m(5, 2), q(3, "6/9", 2)],
                   "I–V–vi–IV 를 add9 · sus4 → V · maj9 · 6/9 로 (Coldplay · OneRepublic 풍 피아노 팝)", drums: .pop),
            modern("Descending Bass", major,
                   [q(0, "maj7"), M(4, bass: 6), m(5), M(0, bass: 4), q(3, "maj7"), M(0, bass: 2), m(1), q(4, "7sus4", 2), dom(4, 2)],
                   "C–G/B–Am–C/G–F–C/E–Dm7–G7sus4 → G7 · 베이스가 한 음씩 내려감 (Piano Man · Canon 계열)", drums: .ballad),
            modern("K-Ballad", major,
                   [q(0, "maj7"), M(4, bass: 6), m(5), m(4, 2), dom(0, 2), q(3, "maj7"), m(2, 2), dom(5, 2), m(1), q(4, "7sus4", 2), dom(4, 2)],
                   "Cmaj7–G/B–Am7–Gm7 C7–Fmaj7–Em7 A7–Dm7–G7sus4 G7 · 세컨더리 도미넌트(C7 · A7)로 색을 넣는 발라드", drums: .ballad),
            modern("Gospel Walk-up", major,
                   [M(0, 2), dim(0, 2, alter: 1), m(1, 2), dim(1, 2, alter: 1), M(0, 2, bass: 2), M(3, 2), dim(3, 2, alter: 1), q(4, "7sus4", 2),
                    q(0, "add9"), q(4, "7sus4", 2), dom(4, 2)],
                   "C–C#°7–Dm7–D#°7–C/E–F–F#°7–G7sus4 · 경과 감7화음으로 반음씩 올라가는 가스펠 · R&B", drums: .boomBap),
            modern("Neo-Soul Turnaround", major,
                   [q(1, "min9"), q(4, "13"), q(0, "maj9"), q(5, "7b9"), q(1, "min9"), q(4, "13"), q(0, "maj9"), q(0, "6/9")],
                   "Dm9–G13–Cmaj9–A7b9 · 9th · 13th · b9 텐션의 네오소울 ii–V–I 턴어라운드", drums: .boomBap),
            modern("Tritone Sub", major,
                   [q(1, "min9"), q(1, "7#11", alter: -1), q(0, "maj9"), q(5, "7b9"), q(1, "min9"), q(1, "7#11", alter: -1), q(0, "maj9", 2), q(0, "6/9", 2), q(5, "7alt")],
                   "Dm9–Db7#11–Cmaj9–A7b9 · V 대신 bII7 (트라이톤 대리) · 시티팝 · 재즈 팝", drums: .funk),
            modern("Borrowed iv", major,
                   [q(0, "maj7"), dom(0), q(3, "maj7"), q(3, "min6"), M(0, 2, bass: 2), dom(5, 2), m(1), q(4, "7sus4", 2), dom(4, 2)],
                   "Cmaj7–C7–Fmaj7–Fm6–C/E A7–Dm7–G7sus4 G7 · 단조에서 빌린 iv (In My Life · Creep 계열)", drums: .pop),
            modern("Royal Road Extended", major,
                   [q(3, "maj7"), dom(4, bass: 3), m(2), m(5), q(3, "maj7"), q(4, "7sus4", 2), dom(4, 2), q(0, "maj9"), q(0, "6/9", 2), dom(2, 2)],
                   "Fmaj7–G/F–Em7–Am7–Fmaj7–G7sus4 G7–Cmaj9–C6/9 E7 · 왕도진행을 8마디로, E7 이 Fmaj7 로 되돌림", drums: .pop),
            modern("Epic bVI–bVII", major,
                   [q(0, "add9", 8), q(5, "maj7", 4, alter: -1), q(6, "add9", 4, alter: -1), q(0, "add9", 4), M(5, 4, alter: -1), M(6, 2, alter: -1), q(4, "sus4", 2)],
                   "Cadd9–Abmaj7–Bbadd9–C–Ab–Bb Gsus4 · 차용 bVI · bVII 로 넓어지는 시네마틱 팝", drums: .halfTime),
            modern("R&B Minor Lush", minor,
                   [q(0, "min9"), q(3, "min9"), q(6, "13"), q(2, "maj9"), q(5, "maj9"), ø(1, 2), q(4, "7#9", 2), q(0, "min9"), q(4, "7alt")],
                   "Am9–Dm9–G13–Cmaj9–Fmaj9–Bm7b5 E7#9–Am9–E7alt · 9th 로 두껍게 깐 단조 R&B", drums: .trap),
            modern("Line Cliché", minor,
                   [m(0), q(0, "mMaj7", bass: 6, bassAlter: 1), m(0, bass: 6), M(3, bass: 5, bassAlter: 1), q(5, "maj7"), m(3), q(4, "7sus4", 2), dom(4, 2), q(0, "m(add9)")],
                   "Am–Am(maj7)/G#–Am7/G–D/F#–Fmaj7–Dm7–E7sus4 E7–Am(add9) · 안쪽 성부가 반음씩 내려가는 라인 (Stairway · Something)", drums: .ballad),
            // 유명 코드 라인: 원곡 조성 고정
            famous("Pachelbel Canon", major, [M(0), M(4, bass: 6), m(5), m(2, bass: 4), M(3), M(0, bass: 2), M(3), q(4, "sus4", 2), M(4, 2)],
                   "C–G/B–Am–Em/G–F–C/E–F–Gsus4 G · 하행 베이스의 팝 캐논 8마디", drums: .ballad),
            famous("12-bar Blues", major,
                   [dom(0), dom(0), dom(0), dom(0), dom(3), dom(3), dom(0), dom(0), dom(4), dom(3), dom(0), dom(4)],
                   "I7–IV7–V7 블루스 12마디 · 모두 도미넌트", drums: .shuffle),
            famous("Rhythm Changes", major,
                   [M(0, 2), dom(5, 2), m(1, 2), dom(4, 2), M(0, 2), dom(5, 2), m(1, 2), dom(4, 2),
                    M(0, 2), dom(0, 2), M(3, 2), dim(3, 2, alter: 1), M(0, 2), dom(4, 2), M(0, 4)],
                   "I Got Rhythm A 파트 · 마디당 두 코드 8마디", drums: .swing),
            famous("Autumn Leaves", minor, [m(3), dom(6), M(2), M(5), ø(1), dom(4), m(0, 8)],
                   "iv7–VII7–IIImaj7–VImaj7–iiø–V7–i · 단조 8마디", drums: .swing),
            famous("Fly Me to the Moon", major, [m(5), m(1), dom(4), M(0), M(3), ø(6), dom(2), m(5)],
                   "vi–ii–V–I–IV–viiø–III7–vi · 장조 8마디", drums: .swing),
            famous("Girl from Ipanema", major, [M(0, 8), dom(1, 8), m(1), dom(1, alter: -1), M(0), dom(1, alter: -1)],
                   "Imaj7–II7–ii7–bII7 보사노바 A 파트 8마디", drums: .bossa),
            famous("Just the Two of Us", major, [M(3), dom(2), m(5), m(4, 2), dom(0, 2)],
                   "IVmaj7–III7–vi7–v7 I7 · 시티팝 · R&B, 마지막 마디 두 코드", drums: .funk),
            famous("Komuro (小室進行)", major, [m(5), M(3), dom(4), M(0)],
                   "vi–IV–V–I · 90년대 댄스", drums: .fourOnFloor),
            famous("Creep", major, [M(0, 8), dom(2, 8), M(3, 8), m(3, 8)],
                   "I–III–IV–iv · 2마디씩 8마디", drums: .rock),
            famous("Hotel California", minor, [m(0), dom(4), M(6), M(3), M(5), M(2), m(3), dom(4)],
                   "i–V–VII–IV–VI–III–iv–V · 단조 8마디", drums: .rock),
            famous("I Will Survive", minor, [m(0), m(3), dom(6), M(2), M(5), ø(1), dom(4), m(0)],
                   "i–iv–VII–III–VI–iiø–V–i 단조 5도권 8마디", drums: .disco),
            famous("Andalusian Cadence", minor, [m(0), M(6), M(5), dom(4)],
                   "i–VII–VI–V · 플라멩코 · Hit the Road Jack", drums: .shuffle),
            famous("I–bVII–IV", major, [M(0), M(6, alter: -1), M(3, 8)],
                   "믹솔리디안 록 (Sweet Home Alabama, Sympathy for the Devil)", drums: .rock),
        ]
    }()
}
