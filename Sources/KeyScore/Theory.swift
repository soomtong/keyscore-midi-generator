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
        ChordQuality(symbol: "sus2", intervals: [0, 2, 7], complexity: 3),
        ChordQuality(symbol: "sus4", intervals: [0, 5, 7], complexity: 3),
        ChordQuality(symbol: "add9", intervals: [0, 4, 7, 14], complexity: 3),
        ChordQuality(symbol: "maj9", intervals: [0, 4, 7, 11, 14], complexity: 3),
        ChordQuality(symbol: "min9", intervals: [0, 3, 7, 10, 14], complexity: 3),
        ChordQuality(symbol: "9", intervals: [0, 4, 7, 10, 14], complexity: 3),
        // 4: 11th / 13th 계열
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
        "min6": "min", "m6": "min",
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

    struct Progression: Identifiable, Hashable {
        let name: String
        let degrees: [Int]  // 0-based 스케일 디그리
        var id: String { name }
    }

    static let progressions: [Progression] = [
        Progression(name: "I–V–vi–IV", degrees: [0, 4, 5, 3]),
        Progression(name: "I–vi–IV–V", degrees: [0, 5, 3, 4]),
        Progression(name: "ii–V–I", degrees: [1, 4, 0]),
        Progression(name: "I–IV–V–I", degrees: [0, 3, 4, 0]),
        Progression(name: "i–VI–III–VII", degrees: [0, 5, 2, 6]),
        Progression(name: "i–iv–v–i", degrees: [0, 3, 4, 0]),
        Progression(name: "i–VII–VI–VII", degrees: [0, 6, 5, 6]),
        Progression(name: "I–iii–IV–V", degrees: [0, 2, 3, 4]),
    ]
}
