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

    func testFormPlaysIntroOnceAndEndsWithOutro() {
        func sec(_ n: String, _ b: Int) -> SectionSpec { SectionSpec(name: n, bars: b, chords: [], melody: []) }
        let s = ["Intro": sec("Intro", 4), "A": sec("A", 8), "B": sec("B", 4), "Break": sec("Break", 2),
                 "Chorus": sec("Chorus", 8), "Outro": sec("Outro", 4)]
        let form = SongForm(intro: ["Intro"], loop: ["A", "B", "Break", "Chorus"], outro: ["Chorus", "Outro"])
        for target in [8, 13, 25, 40, 75, 150, 300] {
            let out = Arranger.expandForm(form, sections: s, targetBars: target)
            XCTAssertEqual(out.first, "Intro", "\(target)")
            XCTAssertEqual(out.filter { $0 == "Intro" }.count, 1, "\(target)")
            XCTAssertEqual(Array(out.suffix(2)), ["Chorus", "Outro"], "\(target)")
            XCTAssertEqual(out.filter { $0 == "Outro" }.count, 1, "\(target)")
            XCTAssertEqual(Array(out[1..<5]), ["A", "B", "Break", "Chorus"], "\(target)")  // 한 바퀴는 반드시
            // 간주 다음은 언제나 후렴
            for i in out.indices where out[i] == "Break" { XCTAssertEqual(out[i + 1], "Chorus", "\(target)") }
            let bars = out.reduce(0) { $0 + s[$1]!.bars }
            if target >= 40 { XCTAssertLessThanOrEqual(abs(bars - target), 4, "\(target): \(out)") }
        }
    }

    func testFlatFormIsSplitByRoleAndName() throws {
        let json = """
        {"title":"T","form":["Opening","Verse","후렴","Verse","후렴","Ending"],"sections":{
          "Opening":{"role":"intro","bars":4,"chords":[{"root":"C","quality":"maj","beats":4}],"melody":[]},
          "Verse":{"role":"Verse","bars":8,"chords":[{"root":"C","quality":"maj","beats":4}],"melody":[]},
          "후렴":{"bars":8,"chords":[{"root":"F","quality":"maj","beats":4}],"melody":[]},
          "Ending":{"bars":4,"chords":[{"root":"C","quality":"maj","beats":4}],"melody":[]}}}
        """
        let arr = try Generator.parse(json)
        XCTAssertEqual(arr.form, SongForm(intro: ["Opening"], loop: ["Verse", "후렴", "Verse", "후렴"], outro: ["Ending"]))
        XCTAssertEqual(arr.sections["후렴"]?.role, .chorus)  // 이름으로 추정
        XCTAssertEqual(arr.sections["Ending"]?.role, .outro)
        XCTAssertEqual(SectionRole(loose: "Pre-Chorus"), .prechorus)
        XCTAssertEqual(SectionRole(loose: "interlude"), .break)
        XCTAssertEqual(SectionRole(guessing: "간주"), .break)
    }

    func testStructuredFormAndRoleDefaultDrums() throws {
        let json = """
        {"title":"T","form":{"intro":["Intro"],"loop":["A","B","Break","Chorus"],"outro":["Chorus","Outro"]},"sections":{
          "Intro":{"role":"intro","bars":4,"chords":[{"root":"C","quality":"maj","beats":4}],"melody":[]},
          "A":{"role":"verse","bars":8,"chords":[{"root":"C","quality":"maj","beats":4}],"melody":[]},
          "B":{"role":"prechorus","bars":4,"chords":[{"root":"D","quality":"min","beats":4}],"melody":[]},
          "Break":{"role":"break","bars":2,"chords":[{"root":"G","quality":"maj","beats":4}],"melody":[],"drums":{"energy":"none"}},
          "Chorus":{"role":"chorus","bars":8,"chords":[{"root":"F","quality":"maj","beats":4}],"melody":[]},
          "Outro":{"role":"outro","bars":4,"chords":[{"root":"C","quality":"maj","beats":4}],"melody":[]}}}
        """
        let arr = try Generator.parse(json)
        XCTAssertEqual(arr.form.intro, ["Intro"])
        XCTAssertEqual(arr.form.outro, ["Chorus", "Outro"])
        XCTAssertEqual(arr.sections["B"]?.drumPlan, DrumPlan(energy: .light, fill: true))  // drums 가 없으면 역할 기본값
        XCTAssertEqual(arr.sections["Chorus"]?.drumPlan, DrumPlan(energy: .full))
        XCTAssertEqual(arr.sections["Break"]?.drumPlan, DrumPlan(energy: .none))  // LLM 값이 우선
        XCTAssertEqual(SectionSpec(name: "x", bars: 1, chords: [], melody: []).drumPlan, DrumPlan())  // 역할도 없으면 full
    }

    func testPromptDescribesFormPreset() {
        var r = GenerateRequest(root: 0, scale: Theory.scales[0], bpm: 100, complexity: 2, minutes: 3)
        let free = Generator.prompt(r)
        XCTAssertTrue(free.contains("\"loop\": [section names"))
        XCTAssertTrue(free.contains("plays the intro sections once"))
        XCTAssertFalse(free.contains("- form:"))
        r.formPreset = .kpop
        r.secondPart = .riff
        let kpop = Generator.prompt(r)
        XCTAssertTrue(kpop.contains("- form: use this K-pop style form exactly"))
        XCTAssertTrue(kpop.contains("\"Break\" (break"))
        XCTAssertFalse(kpop.contains("- interlude:"))  // 간주가 이미 있으므로 따로 요청하지 않는다
        for p in FormPreset.allCases { XCTAssertEqual(p.promptHint == nil, p == .free, p.rawValue) }
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

    func testRiffParsesAndPlaysOnlyWhereMelodyRests() throws {
        let json = """
        {"title":"T","form":["A"],"sections":{
          "A":{"bars":4,"chords":[{"root":"C","quality":"maj","beats":4}],"melody":[[0,61,5],[8,72,1]],
               "riff":{"bars":2,"notes":[[0,60,0.5],[1,84,0.5],[2,67,0.5],[6,64,1],[9,50,1]]}}}}
        """
        let arr = try Generator.parse(json)
        let sec = try XCTUnwrap(arr.sections["A"])
        XCTAssertEqual(sec.riffBars, 2)
        XCTAssertEqual(sec.riff.count, 5)

        // 멜로디가 시작하는 0·2마디에는 리프가 없고, 쉬는 1·3마디에만 나온다
        let riff = SecondPart.riffNotes(sec, start: 0, beats: 16, channel: 3)
        XCTAssertFalse(riff.isEmpty)
        XCTAssertTrue(riff.allSatisfy { (4..<8).contains($0.start) || (12..<16).contains($0.start) })
        XCTAssertTrue(riff.contains { $0.start == 4 && $0.pitch == 48 })  // 이어지는 멜로디(61)와 반음 충돌 → 옥타브 아래
        XCTAssertTrue(riff.contains { $0.start == 5 && $0.pitch == 72 })  // 84 는 음역 안으로 접힘
        XCTAssertFalse(riff.contains { $0.pitch == 64 })  // 빈 마디가 하나뿐이면 2마디 리프의 앞 마디만
        XCTAssertFalse(riff.contains { $0.pitch == 50 })  // 리프 길이 밖의 음은 무시
        XCTAssertTrue(riff.allSatisfy { $0.velocity == 74 })

        // 멜로디가 없는 간주 섹션은 처음부터 끝까지, 더 세게
        var interlude = sec
        interlude.melody = []
        let lead = SecondPart.riffNotes(interlude, start: 32, beats: 16, channel: 3)
        XCTAssertEqual(lead.filter { $0.pitch == 64 }.map(\.start), [38, 46])
        XCTAssertTrue(lead.allSatisfy { $0.velocity == 84 && $0.start >= 32 })

        // Off 이면 리프 데이터가 있어도 보내지 않는다
        var o = ArrangeOptions(bpm: 120, minutes: 0.5)
        o.channels.second = 5
        XCTAssertFalse(Arranger.build(arr, options: o).events.contains { $0.channel == 4 })
        o.secondPart = .riff
        XCTAssertTrue(Arranger.build(arr, options: o).events.contains { $0.channel == 4 })
    }

    func testPromptAsksRiffAndInterludeOnlyForRiff() {
        var r = GenerateRequest(root: 0, scale: Theory.scales[0], bpm: 100, complexity: 2, minutes: 3)
        let off = Generator.prompt(r)
        XCTAssertFalse(off.contains("\"riff\""))
        XCTAssertFalse(off.contains("riff:"))
        XCTAssertFalse(off.contains("interlude:"))
        r.secondPart = .riff
        let riff = Generator.prompt(r)
        XCTAssertTrue(riff.contains("\"riff\": {\"bars\""))
        XCTAssertTrue(riff.contains("NOT played under the melody"))
        XCTAssertTrue(riff.contains("interlude:"))
    }

    func testDrumEnergyLightAndFill() {
        let full = DrumPattern.rock.notes(start: 0, beats: 8, channel: 9)
        XCTAssertTrue(DrumPattern.rock.notes(start: 0, beats: 8, channel: 9, crashOnStart: true, energy: .none).isEmpty)
        let light = DrumPattern.rock.notes(start: 0, beats: 8, channel: 9, energy: .light)
        XCTAssertFalse(light.contains { $0.pitch == DrumPattern.Kit.snare })  // 백비트는 사이드스틱으로
        XCTAssertTrue(light.contains { $0.pitch == DrumPattern.Kit.sideStick })
        XCTAssertEqual(light.filter { $0.pitch == DrumPattern.Kit.kick }.count, 2)  // 마디마다 첫 박만
        XCTAssertLessThan(light.map(\.velocity).reduce(0, +), full.map(\.velocity).reduce(0, +))

        let fill = DrumPattern.funk.notes(start: 0, beats: 8, channel: 9, fill: true)
        let toms = [DrumPattern.Kit.floorTom, DrumPattern.Kit.lowTom, DrumPattern.Kit.midTom, DrumPattern.Kit.highTom]
        XCTAssertTrue(fill.filter { toms.contains($0.pitch) }.allSatisfy { $0.start >= 6 && $0.start < 8 })  // 마지막 마디 후반 두 박
        XCTAssertFalse(fill.contains { $0.pitch == DrumPattern.Kit.closedHat && $0.start >= 6 })
        XCTAssertTrue(fill.allSatisfy { (35...59).contains($0.pitch) && $0.start < 8 })
        // 절반 박자만 남은 짧은 섹션에는 필인을 넣지 않는다
        XCTAssertFalse(DrumPattern.rock.notes(start: 0, beats: 2, channel: 9, fill: true).contains { toms.contains($0.pitch) })
    }

    func testDrumPlanParsesAndCrashesOnlyWhenRising() throws {
        let json = """
        {"title":"T","form":["I","V","C","O"],"sections":{
          "I":{"bars":4,"chords":[{"root":"C","quality":"maj","beats":4}],"melody":[],"drums":{"energy":"none"}},
          "V":{"bars":4,"chords":[{"root":"C","quality":"maj","beats":4}],"melody":[],"drums":{"energy":"Light","fill":true}},
          "C":{"bars":4,"chords":[{"root":"C","quality":"maj","beats":4}],"melody":[],"drums":{"energy":"full"}},
          "O":{"bars":4,"chords":[{"root":"C","quality":"maj","beats":4}],"melody":[],"drums":{"energy":"loud"}}}}
        """
        let arr = try Generator.parse(json)
        XCTAssertEqual(arr.sections["I"]?.drums, DrumPlan(energy: .none))
        XCTAssertEqual(arr.sections["V"]?.drums, DrumPlan(energy: .light, fill: true))
        XCTAssertEqual(arr.sections["O"]?.drums, DrumPlan())  // 알 수 없는 값은 full

        var o = ArrangeOptions(bpm: 120, minutes: 0.5)  // 15마디 → I V C O
        o.drumPattern = .rock
        let drums = Arranger.build(arr, options: o).events.filter { $0.channel == 9 }
        XCTAssertFalse(drums.contains { $0.start < 16 })  // Intro: 드럼 없음
        let crashes = drums.filter { $0.pitch == DrumPattern.Kit.crash }.map(\.start)
        XCTAssertEqual(crashes, [16, 32])  // none → light, 필인 뒤 Chorus. full → full(Outro)은 크래시 없음
    }

    func testPromptAsksDrumsOnlyWhenRhythmIsOn() {
        var r = GenerateRequest(root: 0, scale: Theory.scales[0], bpm: 100, complexity: 2, minutes: 3)
        let off = Generator.prompt(r)
        XCTAssertFalse(off.contains("\"drums\""))
        XCTAssertFalse(off.contains("groove"))
        r.drumPattern = .shuffle
        let on = Generator.prompt(r)
        XCTAssertTrue(on.contains("\"drums\": {\"energy\""))
        XCTAssertTrue(on.contains("triplet shuffle groove"))
        XCTAssertTrue(on.contains("\"fill\": true plays a drum fill"))
        for p in DrumPattern.allCases {
            XCTAssertEqual(p.promptHint.isEmpty, p == .off, p.rawValue)
        }
    }

    func testSongInfoFollowsArrangedSongNotLiveSettings() async {
        let m = await AppModel()
        await MainActor.run {
            func sec(_ n: String, _ b: Int) -> SectionSpec { SectionSpec(name: n, bars: b, chords: [], melody: []) }
            let arr = Arrangement(title: "t", sections: ["I": sec("I", 4), "A": sec("A", 8), "O": sec("O", 4)],
                                  form: SongForm(intro: ["I"], loop: ["A"], outro: ["O"]))
            m.bpm = 100
            m.minutes = 3
            XCTAssertTrue(m.layout.isEmpty)
            _ = m.adopt(arr, prompt: m.promptSettings, arrange: m.arrangeSettings)
            let before = m.layout.map(\.name)
            XCTAssertEqual(before.count, 2 + 8)  // 4 + 8x8 + 4 = 72마디 ≈ 75
            XCTAssertTrue(m.pendingArrange.isEmpty && m.pendingPrompt.isEmpty)

            // 설정을 바꿔도 화면의 곡 정보는 그대로, 바뀐 항목만 알린다
            m.bpm = 140
            m.root = (m.root + 1) % 12
            m.formPreset = .kpop
            XCTAssertEqual(m.layout.map(\.name), before)
            XCTAssertEqual(m.pendingArrange, ["BPM"])
            XCTAssertEqual(m.pendingPrompt, ["Key", "FORM"])

            // 다시 전개하면 새 BPM 으로 전개되고 전개 배지는 사라진다. 프롬프트 배지는 다시 생성해야 사라진다.
            _ = m.buildSong()
            XCTAssertGreaterThan(m.layout.count, before.count)
            XCTAssertTrue(m.pendingArrange.isEmpty)
            XCTAssertEqual(m.pendingPrompt, ["Key", "FORM"])
        }
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
