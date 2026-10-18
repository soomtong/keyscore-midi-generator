import Foundation

enum MelodyStyle: String, CaseIterable, Identifiable {
    case free = "Free (AI)"
    case motif = "Motif"
    case scalarRun = "Scale Run"
    case arpeggio = "Arpeggio"
    case callResponse = "Call & Response"
    case syncopated = "Syncopated"
    case sparse = "Sparse"
    case sequence = "Sequence"
    case pedalPoint = "Pedal Point"
    case pentatonicRiff = "Pentatonic Riff"
    case tripletRun = "Triplet Run"
    case inversion = "Inversion"
    case walking = "Walking"
    case descent = "Descent"
    case question = "Question"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .free: return "AI 가 알아서 구성 (곡 생성에만 적용)"
        case .motif: return "짧은 동기를 반복하며 끝에서 변형"
        case .scalarRun: return "스케일을 따라 오르내리는 8분음표 런"
        case .arpeggio: return "코드톤 위주로 넓게 도약하는 선율"
        case .callResponse: return "질문 프레이즈에 답하는 2+2마디 구조"
        case .syncopated: return "당김음 리듬으로 밀고 당기는 선율"
        case .sparse: return "긴 음과 쉼표, 여백이 많은 선율"
        case .sequence: return "같은 모양을 음높이만 올려가며 반복"
        case .pedalPoint: return "으뜸음을 계속 두드리며 위의 선율만 움직임"
        case .pentatonicRiff: return "5음 위주의 짧은 리프를 반복하고 끝에서 변형"
        case .tripletRun: return "셋잇단 8분음표로 물결치듯 오르내리는 런"
        case .inversion: return "동기를 원형 → 거꾸로 뒤집기 → 역행 순으로 변형"
        case .walking: return "4분음표로 걷듯 이어지는 스텝 라인"
        case .descent: return "높은 음에서 으뜸음까지 천천히 내려오는 선율"
        case .question: return "으뜸음으로 돌아가지 않고 5도에서 끝나는 열린 프레이즈"
        }
    }

    var promptHint: String {
        switch self {
        case .free: return ""
        case .motif: return "build the melody from a short 3-5 note motif that repeats and is varied at phrase ends"
        case .scalarRun: return "use stepwise eighth-note scale runs going up and down"
        case .arpeggio: return "outline chord tones with wide leaps and arpeggiated figures"
        case .callResponse: return "use 2-bar question phrases answered by 2-bar response phrases"
        case .syncopated: return "use syncopated rhythms with off-beat accents and ties over the beat"
        case .sparse: return "use long sustained notes, generous rests and space"
        case .sequence: return "repeat a small melodic shape while moving it step by step up or down the scale (melodic sequence)"
        case .pedalPoint: return "keep returning to a repeated tonic pedal tone while the upper voice moves above it"
        case .pentatonicRiff: return "use a short pentatonic-flavored riff that repeats and changes at the end"
        case .tripletRun: return "use flowing eighth-note triplet runs that rise and fall"
        case .inversion: return "state a short motif, then its melodic inversion (mirrored), then its retrograde"
        case .walking: return "use steady quarter-note stepwise walking lines with passing tones"
        case .descent: return "descend slowly from a high note down to the tonic in long notes"
        case .question: return "write an open-ended phrase that ends on the dominant (5th degree) without resolving"
        }
    }

    typealias PhraseNote = (degree: Int, beat: Double, length: Double)

    /// 스케일 디그리(0 = 으뜸음) 기준 4마디(16박) 프레이즈. free 는 비어 있음.
    /// seed 를 주면 같은 뼈대에서 약박의 음과 끝음을 조금씩 바꾼 변주를 만든다 (같은 seed 는 같은 결과).
    func phrase(seed: UInt64? = nil) -> [PhraseNote] {
        let base = basePhrase()
        guard let seed, let last = base.indices.max(by: { base[$0].beat < base[$1].beat }) else { return base }
        var rng = SplitMix64(seed: seed)
        let top = (base.map(\.degree).max() ?? 0) + 1
        return base.enumerated().map { i, n in
            // 끝음은 안정음(1·3·5도)으로. 열린 프레이즈(question)는 5도 종지를 유지한다.
            if i == last { return self == .question ? n : ([0, 2, 4].randomElement(using: &rng)!, n.beat, n.length) }
            // 마디 첫 박은 뼈대를 지키고, 나머지는 일정 확률로 이웃음으로 바꾼다.
            guard n.beat.truncatingRemainder(dividingBy: 4) != 0, Double.random(in: 0..<1, using: &rng) < 0.3 else { return n }
            let d = n.degree + (Bool.random(using: &rng) ? 1 : -1)
            return (min(top, max(0, d)), n.beat, n.length)
        }
    }

    private func basePhrase() -> [PhraseNote] {
        switch self {
        case .free:
            return []
        case .motif:
            return (0..<4).flatMap { bar -> [PhraseNote] in
                let b = Double(bar) * 4
                let shift = bar == 2 ? 1 : 0
                return [
                    (shift, b, 1), (2 + shift, b + 1, 0.5), (1 + shift, b + 1.5, 0.5),
                    bar == 3 ? (0, b + 2, 2) : (3 + shift, b + 2, 1.5),
                ]
            }
        case .scalarRun:
            return (0..<32).map { k in
                let m = k % 14
                return (m <= 7 ? m : 14 - m, Double(k) * 0.5, 0.45)
            }
        case .arpeggio:
            let shapes = [0, 2, 4, 7, 4, 2]
            let roots = [0, 5, 3, 4]
            return (0..<32).map { k in
                (roots[k / 8] + shapes[k % shapes.count], Double(k) * 0.5, 0.45)
            }
        case .callResponse:
            let call: [PhraseNote] = [(0, 0, 1), (2, 1, 1), (4, 2, 1), (2, 3, 1)]
            let resp: [PhraseNote] = [(4, 0, 1), (2, 1, 1), (1, 2, 1), (0, 3, 2)]
            let ask = call + call.map { ($0.degree + 1, $0.beat + 4, $0.length) }
            return ask + resp.map { ($0.degree, $0.beat + 8, $0.length) }
        case .syncopated:
            let beats: [Double] = [0, 0.75, 1.5, 2.5, 3, 3.5]
            let degrees = [0, 2, 4, 2, 3, 1]
            let shifts = [0, 0, 2, 0]
            return (0..<4).flatMap { bar in
                beats.indices.map { i in (degrees[i] + shifts[bar], Double(bar) * 4 + beats[i], 0.5) }
            }
        case .sparse:
            return [(0, 0, 3), (4, 4, 2.5), (2, 8, 3), (0, 12, 4)]
        case .sequence:
            let cell: [PhraseNote] = [(0, 0, 0.5), (1, 0.5, 0.5), (2, 1, 1)]
            let steps = (0..<7).flatMap { i in cell.map { ($0.degree + i, $0.beat + Double(i) * 2, $0.length) } }
            return steps + [(0, 14, 2)]
        case .pedalPoint:
            let upper = [2, 4, 3, 5, 2, 4, 6, 5, 3, 4, 2, 3]
            return upper.enumerated().flatMap { i, d -> [PhraseNote] in
                [(0, Double(i), 0.5), (d, Double(i) + 0.5, 0.5)]
            } + [(0, 12, 4)]
        case .pentatonicRiff:
            // 7음 스케일에서 디그리 0·1·2·4·5 가 5음 음계(1 2 3 5 6)에 해당한다.
            let cell: [PhraseNote] = [(0, 0, 0.5), (1, 0.5, 0.5), (2, 1, 0.5), (4, 1.5, 0.5), (5, 2, 1), (4, 3, 0.5), (2, 3.5, 0.5)]
            let ending: [PhraseNote] = [(5, 12, 0.5), (4, 12.5, 0.5), (2, 13, 0.5), (1, 13.5, 0.5), (0, 14, 2)]
            return (0..<3).flatMap { bar in cell.map { ($0.degree, $0.beat + Double(bar) * 4, $0.length) } } + ending
        case .tripletRun:
            let wave = [0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 0, 1]
            let shifts = [0, 1, 2]
            return shifts.enumerated().flatMap { bar, shift in
                wave.enumerated().map { k, d in (d + shift, Double(bar) * 4 + Double(k) / 3, 0.3) }
            } + [(2, 12, 1), (1, 13, 1), (0, 14, 2)]
        case .inversion:
            let motif = [0, 2, 1, 3]
            let bars = [motif, motif.map { 4 - $0 }, Array(motif.reversed())]
            return bars.enumerated().flatMap { bar, ds in
                ds.enumerated().map { k, d in (d, Double(bar) * 4 + Double(k), 1.0) }
            } + [(1, 12, 1), (2, 13, 1), (0, 14, 2)]
        case .walking:
            let bars = [[0, 2, 4, 3], [2, 4, 5, 4], [3, 5, 4, 2]]
            return bars.enumerated().flatMap { bar, ds in
                ds.enumerated().map { k, d in (d, Double(bar) * 4 + Double(k), 0.9) }
            } + [(1, 12, 1), (2, 13, 1), (0, 14, 2)]
        case .descent:
            return [7, 6, 5, 4, 3, 2, 1].enumerated().map { ($1, Double($0) * 2, 1.9) } + [(0, 14, 2)]
        case .question:
            return [(0, 0, 1), (2, 1, 1), (1, 2, 1), (2, 3, 1),
                    (3, 4, 1), (2, 5, 1), (1, 6, 1), (2, 7, 1),
                    (4, 8, 1.5), (3, 9.5, 0.5), (2, 10, 1), (3, 11, 1),
                    (4, 12, 4)]
        }
    }

    static func pitch(degree: Int, root: Int, scale: ScaleType) -> Int {
        let base = 60 + root - (root > 6 ? 12 : 0)
        let n = scale.intervals.count
        return base + scale.intervals[degree % n] + 12 * (degree / n)
    }
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
