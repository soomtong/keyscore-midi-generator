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

    func testChordPatternsStayInsideChord() {
        let pitches = [48, 52, 55, 59]
        for p in ChordPattern.allCases {
            for beats in [2.0, 4.0, 8.0] {
                let ev = p.notes(pitches: pitches, start: 10, beats: beats, channel: 1, velocity: 70)
                XCTAssertFalse(ev.isEmpty, "\(p.rawValue) \(beats)")
                for e in ev {
                    XCTAssertTrue(pitches.contains(e.pitch), p.rawValue)
                    XCTAssertGreaterThanOrEqual(e.start, 10, p.rawValue)
                    XCTAssertLessThanOrEqual(e.start, 10 + beats, p.rawValue)
                    XCTAssertGreaterThan(e.length, 0, p.rawValue)
                }
            }
            XCTAssertFalse(p.summary.isEmpty)
        }
    }

    func testMelodyPhrasesFitFourBars() {
        for style in MelodyStyle.allCases where style != .free {
            let notes = style.phrase()
            XCTAssertFalse(notes.isEmpty, style.rawValue)
            XCTAssertEqual(style.phrase(seed: 7).count, notes.count, style.rawValue)
            XCTAssertTrue(style.phrase(seed: 7).elementsEqual(style.phrase(seed: 7), by: { $0 == $1 }), style.rawValue)
            for n in notes + style.phrase(seed: 1) + style.phrase(seed: 2) {
                XCTAssertTrue(n.beat >= 0 && n.beat + n.length <= 16.01, "\(style.rawValue) \(n)")
                let pitch = MelodyStyle.pitch(degree: n.degree, root: 7, scale: Theory.scales[4])
                XCTAssertTrue((48...96).contains(pitch), "\(style.rawValue) \(pitch)")
            }
        }
    }

    @MainActor
    func testLengthSnapsToHalfMinutes() {
        XCTAssertEqual(AppModel.snapLength(4.3), 4.5)
        XCTAssertEqual(AppModel.snapLength(0), 0.5)
        XCTAssertEqual(AppModel.lengthLabel(0.5), "0:30")
        XCTAssertEqual(AppModel.snapLength(99), 12)
        XCTAssertEqual(AppModel.lengthLabel(2.5), "2:30")
    }

    func testTargetBarsAndLayoutFollowLength() {
        XCTAssertEqual(Arranger.targetBars(minutes: 5, bpm: 100), 125)
        XCTAssertEqual(Arranger.targetBars(minutes: 1, bpm: 40), 10)
        let sec = SectionSpec(name: "A", bars: 8, chords: [], melody: [])
        let order = Arranger.expandForm(["A"], sections: ["A": sec], targetBars: 125)
        XCTAssertEqual(order.count, 16)  // 128마디가 125에 가장 가까움
    }

    // MARK: 청취 옵션

    func testScaleSequenceOptions() {
        let major = Theory.scales[0]
        var o = ListenOptions()
        o.upDown = false
        XCTAssertEqual(Preview.scalePitches(root: 0, type: major, options: o), [60, 62, 64, 65, 67, 69, 71, 72])

        o.descending = true
        XCTAssertEqual(Preview.scalePitches(root: 0, type: major, options: o), [72, 71, 69, 67, 65, 64, 62, 60])

        o.descending = false
        o.upDown = true  // 꼭대기 음은 한 번만
        let ud = Preview.scalePitches(root: 0, type: major, options: o)
        XCTAssertEqual(ud.count, 15)
        XCTAssertEqual(ud.filter { $0 == 72 }.count, 1)

        o.upDown = false
        o.twoOctaves = true
        XCTAssertEqual(Preview.scalePitches(root: 0, type: major, options: o).last, 84)

        o.twoOctaves = false
        o.octave = 1
        XCTAssertEqual(Preview.scalePitches(root: 0, type: major, options: o).first, 72)
    }

    func testChordExtendContinuesPattern() {
        var o = ListenOptions()
        XCTAssertEqual(Preview.shape([60, 64, 67], o), [60, 64, 67])
        o.extendUp = 2  // C E G -> 위로 C E (한 옥타브 위)
        XCTAssertEqual(Preview.shape([60, 64, 67], o), [60, 64, 67, 72, 76])
        o.extendUp = 0
        o.extendDown = 1  // 아래로 G
        XCTAssertEqual(Preview.shape([60, 64, 67], o), [55, 60, 64, 67])
        o.extendDown = 6
        o.octave = -5  // MIDI 범위를 벗어나는 음은 버린다
        XCTAssertTrue(Preview.shape([60, 64, 67], o).allSatisfy { (0...127).contains($0) })
    }

    func testLegatoOverlapsAndTogetherStacks() {
        var o = ListenOptions()
        o.legato = true
        let seq = Preview.scale(root: 0, type: Theory.scales[0], channel: 1, options: o, bpm: 120)
        let first = seq.events[0], second = seq.events[1]
        XCTAssertGreaterThan(first.start + first.length, second.start)  // 다음 음 시작 뒤에도 울림
        XCTAssertEqual((first.start + first.length - second.start) * 60 / 120, ListenOptions.legatoOverlapSeconds, accuracy: 1e-9)

        o.legato = false
        o.together = true
        let block = Preview.scale(root: 0, type: Theory.scales[0], channel: 1, options: o)
        XCTAssertTrue(block.events.allSatisfy { $0.start == 0 })
    }

    func testComplexityLevelsFourAndFive() {
        let major = Theory.scales[0]
        // 쌓는 음 수: 3화음, 7th, 9th, 11th, 13th
        for (level, count) in [(1, 3), (2, 4), (3, 5), (4, 6), (5, 7)] {
            XCTAssertEqual(Theory.diatonicIntervals(scale: major, degree: 0, complexity: level).count, count, "level \(level)")
        }
        // C 메이저 13th: C E G B D F A
        XCTAssertEqual(Theory.diatonicIntervals(scale: major, degree: 0, complexity: 5), [0, 4, 7, 11, 14, 17, 21])
        // 모든 단계에 코드 종류가 있고, 단계가 오를수록 사용 가능한 종류가 늘어난다
        var previous = 0
        for level in 1...Theory.maxComplexity {
            let n = Theory.chordQualities.filter { $0.complexity <= level }.count
            XCTAssertGreaterThan(n, previous, "level \(level)")
            previous = n
        }
        XCTAssertEqual(Theory.quality(named: "7alt")?.complexity, 5)
        XCTAssertEqual(Theory.quality(named: "m11")?.symbol, "min11")
        let prompt = Generator.prompt(GenerateRequest(root: 0, scale: major, bpm: 100, complexity: 5, minutes: 3))
        XCTAssertTrue(prompt.contains("7alt") && prompt.contains("melodic complexity"))
    }

    func testPromptReflectsPatternProgressionAndTempo() {
        let dorian = Theory.scales.first { $0.name.contains("Dorian") } ?? Theory.scales[0]
        let ii = Theory.progressions[2]
        let r = GenerateRequest(root: 2, scale: dorian, bpm: 70, complexity: 2, minutes: 0.5,
                                melodyStyle: .sparse, chordPattern: .tremolo, progression: ii)
        let prompt = Generator.prompt(r)
        XCTAssertTrue(prompt.contains("tremolo"))
        XCTAssertTrue(prompt.contains("only 1 or 2 notes per bar"))
        XCTAssertTrue(prompt.contains("slow:"))
        XCTAssertTrue(prompt.contains("harmonic backbone"))
        XCTAssertTrue(prompt.contains("2 or 3 sections"))
        XCTAssertFalse(prompt.contains("Roughly 2 to 5"))
        XCTAssertEqual(Generator.progressionText(r)?.split(separator: "-").count, 3)
        // 진행을 고르지 않으면 해당 줄이 없다
        var none = r
        none.progression = nil
        XCTAssertFalse(Generator.prompt(none).contains("harmonic backbone"))
    }

    func testDrumPatternsUseRhythmChannelAndGMNotes() {
        XCTAssertTrue(DrumPattern.off.notes(start: 0, beats: 16, channel: 9).isEmpty)
        for p in DrumPattern.allCases where p != .off {
            let ev = p.notes(start: 0, beats: 16, channel: 9, crashOnStart: true)
            XCTAssertFalse(ev.isEmpty, p.rawValue)
            XCTAssertTrue(ev.allSatisfy { $0.channel == 9 && (35...59).contains($0.pitch) && $0.start >= 0 && $0.start < 16 }, p.rawValue)
            XCTAssertEqual(ev.filter { $0.pitch == DrumPattern.Kit.crash }.count, 1, p.rawValue)
        }
        // 마지막 마디가 잘리면 범위를 넘는 타격이 없어야 한다
        XCTAssertTrue(DrumPattern.funk.notes(start: 8, beats: 2, channel: 9).allSatisfy { $0.start < 10 })
    }

    func testArrangerSendsDrumsOnlyWhenEnabled() {
        let sec = SectionSpec(name: "A", bars: 4, chords: [ChordSpec(root: 0, quality: Theory.chordQualities[0], beats: 4)],
                              melody: [MelodyNote(beat: 0, pitch: 60, length: 1)])
        let arr = Arrangement(title: "t", sections: ["A": sec], form: ["A"])
        var o = ArrangeOptions(bpm: 120, minutes: 0.5)
        o.channels.rhythm = 8
        XCTAssertFalse(Arranger.build(arr, options: o).events.contains { $0.channel == 7 })
        o.drumPattern = .rock
        let ev = Arranger.build(arr, options: o).events
        XCTAssertTrue(ev.contains { $0.channel == 7 && $0.pitch == DrumPattern.Kit.kick })
        XCTAssertTrue(ev.contains { $0.channel == 0 })  // 멜로디는 그대로 1번 채널
    }

    func testSelectionShiftWrapsAround() async {
        let m = await AppModel()
        await MainActor.run {
            m.shiftScale(-1)
            XCTAssertEqual(m.scaleIndex, Theory.scales.count - 1)
            m.shiftChordQuality(-1)
            XCTAssertEqual(m.chordQualityIndex, Theory.chordQualities.count - 1)
            m.shiftChordQuality(1)
            XCTAssertEqual(m.chordQualityIndex, 0)
            m.shiftProgression(-1)
            XCTAssertEqual(m.progressionIndex, Theory.progressions.count - 1)
            m.cycleMelodyStyle(-1)
            XCTAssertEqual(m.melodyStyle, MelodyStyle.allCases.last)
            m.cycleMelodyStyle(1)
            XCTAssertEqual(m.melodyStyle, MelodyStyle.allCases.first)
            m.cycleChordPattern(-1)
            XCTAssertEqual(m.chordPattern, ChordPattern.allCases.last)
        }
    }

    func testChordListenHasNoPatternAndProgressionFollowsPattern() {
        let q = Theory.chordQualities[0]
        var o = ListenOptions()
        o.together = true
        // 코드 듣기는 패턴 인자가 없다: 한 번에 울리는 블록
        let block = Preview.chord(root: 0, quality: q, channel: 2, options: o)
        XCTAssertTrue(block.events.allSatisfy { $0.start == 0 })
        o.together = false
        let seq = Preview.chord(root: 0, quality: q, channel: 2, options: o)
        XCTAssertEqual(seq.events.map(\.start), [0, 0.5, 1])

        // 패턴 듣기(코드 진행)는 선택한 코드 패턴에 따라 달라진다
        let prog = Theory.progressions[0]
        let a = Preview.progression(root: 0, scale: Theory.scales[0], prog: prog, complexity: 2, pattern: .block, channels: ChannelMap())
        let b = Preview.progression(root: 0, scale: Theory.scales[0], prog: prog, complexity: 2, pattern: .tremolo, channels: ChannelMap())
        XCTAssertNotEqual(a.events, b.events)
    }

    @MainActor
    func testShortcutPanelToggleIsRemembered() {
        let key = "ui.showShortcuts"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        let first = AppModel()
        XCTAssertTrue(first.showShortcuts, "처음 실행하면 열려 있어야 한다")
        first.toggleShortcuts()
        XCTAssertFalse(first.showShortcuts)
        XCTAssertFalse(AppModel().showShortcuts, "닫은 상태는 다음 실행에도 유지")
        first.toggleShortcuts()
        XCTAssertTrue(AppModel().showShortcuts)
    }
}
