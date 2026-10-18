import XCTest
@testable import KeyScore

final class KeyScoreTests: XCTestCase {
    func testPitchClass() {
        XCTAssertEqual(pitchClass(of: "C#"), 1)
        XCTAssertEqual(pitchClass(of: "Bb"), 10)
        XCTAssertNil(pitchClass(of: "H"))
    }

    func testDiatonicSeventh() {
        let major = Theory.scales[0]
        XCTAssertEqual(Theory.diatonicIntervals(scale: major, degree: 0, complexity: 2), [0, 4, 7, 11])
        XCTAssertEqual(Theory.diatonicIntervals(scale: major, degree: 4, complexity: 2), [0, 4, 7, 10])
        XCTAssertEqual(Theory.diatonicIntervals(scale: major, degree: 1, complexity: 1), [0, 3, 7])
    }

    func testParseAndBuildLength() throws {
        let json = """
        ```json
        {"title":"T","form":["A","B"],"sections":{
          "A":{"bars":8,"chords":[{"root":"C","quality":"maj7","beats":4},{"root":"A","quality":"m7","beats":4}],"melody":[[0,72,1],[1,74,1]]},
          "B":{"bars":8,"chords":[{"root":"F","quality":"maj","beats":8}],"melody":[[0,69,2]]}}}
        ```
        """
        let arr = try Generator.parse(json)
        let song = Arranger.build(arr, options: ArrangeOptions(bpm: 120, minutes: 3))
        XCTAssertEqual(song.seconds, 180, accuracy: 16)  // 섹션 단위(8마디=16초) 오차
        XCTAssertTrue(song.events.contains { $0.channel == 0 })
        XCTAssertTrue(song.events.contains { $0.channel == 2 })
    }
}
