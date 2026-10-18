import XCTest
@testable import KeyScore

/// OPENROUTER_API_KEY 가 있고 KEYSCORE_LIVE=1 일 때만 실제 호출한다.
final class OpenRouterLiveTests: XCTestCase {
    func testLiveGeneration() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["KEYSCORE_LIVE"] == "1", "KEYSCORE_LIVE=1 필요")
        let key = try XCTUnwrap(env["OPENROUTER_API_KEY"])
        let client = OpenRouterClient(apiKey: key, model: env["OPENROUTER_MODEL"] ?? "anthropic/claude-sonnet-4.5")
        var req = GenerateRequest(root: 2, scale: Theory.scales[7], bpm: 96, complexity: Int(env["KEYSCORE_COMPLEXITY"] ?? "") ?? 2, minutes: 3)
        req.drumPattern = DrumPattern(rawValue: env["KEYSCORE_DRUMS"] ?? "") ?? .off
        req.secondPart = env["KEYSCORE_RIFF"] == "1" ? .riff : .off
        let started = Date()
        let arr = try await Generator.generate(req, client: client) { stage, step, total in
            print("LIVE stage \(step)/\(total) \(stage.label) +\(Int(Date().timeIntervalSince(started)))s")
        }
        for (name, s) in arr.sections.sorted(by: { $0.key < $1.key }) {
            print("LIVE \(name) \(s.role?.rawValue ?? "-") \(s.bars)bars chords=\(s.chords.map(\.symbol)) bass=\(s.bass.count) melody=\(s.melody.count) riff=\(s.riff.count) drums=\(s.drums.map { "\($0.energy)\($0.fill ? "+fill" : "")" } ?? "-")")
        }
        let song = Arranger.build(arr, options: ArrangeOptions(bpm: 96, minutes: 3))
        print("LIVE title=\(arr.title) form=\(arr.form) total=\(Int(Date().timeIntervalSince(started)))s seconds=\(song.seconds) events=\(song.events.count)")
        let symbols = arr.sections.values.flatMap { $0.chords.map(\.quality.symbol) }
        print("LIVE chords=\(Dictionary(grouping: symbols, by: { $0 }).mapValues(\.count).sorted { $0.key < $1.key })")
        // 튜닝 지표: 강박(0·2박) 멜로디 음 중 그때 울리는 코드의 구성음 비율, 코드가 바뀌는 박에 베이스가 근음을 치는 비율
        var strong = (hit: 0, all: 0), roots = (hit: 0, all: 0)
        for s in arr.sections.values {
            let tl = Generator.chordTimeline(s)
            func chord(at b: Double) -> ChordSpec? { tl.last { $0.beat <= b + 1e-9 }?.chord }
            for n in s.melody where n.beat.truncatingRemainder(dividingBy: 2) == 0 {
                guard let c = chord(at: n.beat) else { continue }
                strong.all += 1
                if c.quality.intervals.contains(((n.pitch - c.root) % 12 + 12) % 12) { strong.hit += 1 }
            }
            for (b, c) in tl {
                guard let n = s.bass.first(where: { abs($0.beat - b) < 1e-9 }) else { continue }
                roots.all += 1
                if n.pitch % 12 == c.root { roots.hit += 1 }
            }
        }
        print("LIVE strong-beat chord tones \(strong.hit)/\(strong.all), bass roots on changes \(roots.hit)/\(roots.all)")
        XCTAssertGreaterThan(song.events.count, 50)
        XCTAssertTrue(arr.sections.values.contains { !$0.bass.isEmpty })
        XCTAssertTrue(arr.sections.values.contains { !$0.melody.isEmpty })
        XCTAssertEqual(song.seconds, 180, accuracy: 40)
    }
}
