import XCTest
@testable import KeyScore

/// OPENROUTER_API_KEY 가 있고 KEYSCORE_LIVE=1 일 때만 실제 호출한다.
final class OpenRouterLiveTests: XCTestCase {
    func testLiveGeneration() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["KEYSCORE_LIVE"] == "1", "KEYSCORE_LIVE=1 필요")
        let key = try XCTUnwrap(env["OPENROUTER_API_KEY"])
        let client = OpenRouterClient(apiKey: key, model: env["OPENROUTER_MODEL"] ?? "anthropic/claude-sonnet-4.5")
        let req = GenerateRequest(root: 2, scale: Theory.scales[7], bpm: 96, complexity: 2, minutes: 3)
        let arr = try await Generator.generate(req, client: client)
        let song = Arranger.build(arr, options: ArrangeOptions(bpm: 96, minutes: 3))
        print("LIVE title=\(arr.title) form=\(arr.form) sections=\(arr.sections.mapValues { "\($0.bars)bars \($0.chords.count)ch \($0.melody.count)n" }) seconds=\(song.seconds) events=\(song.events.count)")
        XCTAssertGreaterThan(song.events.count, 50)
        XCTAssertEqual(song.seconds, 180, accuracy: 40)
    }
}
