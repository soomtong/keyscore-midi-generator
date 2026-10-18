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
        }
    }

    typealias PhraseNote = (degree: Int, beat: Double, length: Double)

    /// 스케일 디그리(0 = 으뜸음) 기준 4마디(16박) 프레이즈. free 는 비어 있음.
    func phrase() -> [PhraseNote] {
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
        }
    }

    static func pitch(degree: Int, root: Int, scale: ScaleType) -> Int {
        let base = 60 + root - (root > 6 ? 12 : 0)
        let n = scale.intervals.count
        return base + scale.intervals[degree % n] + 12 * (degree / n)
    }
}
