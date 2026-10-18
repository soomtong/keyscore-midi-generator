import Foundation

struct GenerateRequest {
    var root: Int
    var scale: ScaleType
    var bpm: Double
    var complexity: Int
    var minutes: Double
    var mood: String = ""
    var melodyStyle: MelodyStyle = .free
    var chordPattern: ChordPattern = .block
    var progression: Theory.Progression? = nil
    var secondPart: SecondPart = .off
    var drumPattern: DrumPattern = .off
    var formPreset: FormPreset = .free
}

/// 곡은 여러 번의 LLM 호출로 쌓아 올린다. 화음을 먼저 정하고, 그 위에 베이스와 리듬(바탕),
/// 마지막으로 멜로디와 리프를 얹는다. 뒤 단계는 앞 단계의 결과를 보고 작곡한다.
enum Generator {
    enum Stage: Equatable {
        case harmony, bass, rhythm, melody

        var label: String {
            switch self {
            case .harmony: return "화음"
            case .bass: return "베이스"
            case .rhythm: return "리듬"
            case .melody: return "멜로디"
            }
        }
    }

    static let system = """
    You are a composer assistant. Reply with a single JSON object only, no prose, no code fences.
    You write short reusable song sections; the host program repeats them to reach the required length.
    You compose one layer at a time: harmony first, then bass and drums, then melody. Layers already written are given to you and are final.
    """

    /// 생성 순서. 리듬이 켜져 있으면 화음 다음에 베이스와 리듬을 함께 짜는데, 그루브가 곡의 성격을 정하는 패턴은
    /// 리듬을 먼저 정해 베이스를 킥에 맞추고, 그 밖에는 베이스를 먼저 짜서 드럼 편성을 베이스 흐름에 맞춘다.
    static func stages(_ r: GenerateRequest) -> [Stage] {
        let foundation: [Stage]
        switch r.drumPattern {
        case .off: foundation = [.bass]
        case .fourOnFloor, .funk, .bossa, .shuffle: foundation = [.rhythm, .bass]
        case .rock, .ballad: foundation = [.bass, .rhythm]
        }
        return [.harmony] + foundation + [.melody]
    }

    /// 선택된 진행을 현재 Key/Scale/복잡도의 코드로 풀어 쓴다 (예: "D min7 - G 7 - C maj7").
    /// 복잡도에 맞는 코드 종류가 없으면 구성음을 줄여 가장 가까운 종류를 찾고, 그래도 없으면 nil.
    static func progressionText(_ r: GenerateRequest) -> String? {
        guard let prog = r.progression else { return nil }
        var parts: [String] = []
        for d in prog.degrees {
            let ivs = Theory.diatonicIntervals(scale: r.scale, degree: d, complexity: r.complexity)
            guard let q = (1...ivs.count).reversed().lazy.compactMap({ Theory.quality(matching: Array(ivs.prefix($0))) }).first
            else { return nil }
            let pc = (r.root + r.scale.intervals[d % r.scale.intervals.count]) % 12
            parts.append("\(noteNames[pc]) \(q.symbol)")
        }
        return parts.joined(separator: " - ")
    }

    /// 목표 길이에 맞춘 구성 크기. 짧은 곡에 섹션을 많이 요구하면 한 바퀴도 못 돈다.
    static func layout(targetBars: Int) -> (sections: String, formEntries: String, maxBars: Int) {
        switch targetBars {
        case ..<24: return ("2 or 3", "3 to 5", 8)
        case ..<64: return ("3 or 4", "5 to 8", 16)
        default: return ("3 or 4", "6 to 10", 16)
        }
    }

    /// 템포가 주는 리듬 감각.
    static func tempoFeel(_ bpm: Double) -> String {
        switch bpm {
        case ..<80: return "slow: favor long notes, space and lyrical phrasing"
        case ..<110: return "moderate: balanced rhythm with room to breathe"
        default: return "fast: favor rhythmic drive and shorter, more energetic figures"
        }
    }

    /// 드럼 패턴의 킥 위치 (마디 안 박). 보사노바처럼 마디마다 같으므로 첫 마디만 본다.
    static func kickBeats(_ p: DrumPattern) -> String {
        p.bar(0).filter { $0.note == DrumPattern.Kit.kick }.map { fmt($0.beat) }.joined(separator: ", ")
    }

    private static func fmt(_ x: Double) -> String { String(format: "%g", x) }

    // MARK: 프롬프트

    /// 모든 단계가 공유하는 곡 설명.
    static func brief(_ r: GenerateRequest) -> String {
        let scaleNotes = r.scale.intervals.map { noteNames[(r.root + $0) % 12] }.joined(separator: " ")
        return """
        Song brief:
        - key: \(noteNames[r.root]), scale: \(r.scale.name) (notes: \(scaleNotes))
        - tempo: \(Int(r.bpm)) BPM, 4/4 (\(tempoFeel(r.bpm)))
        - accompaniment: the host plays every chord as \(r.chordPattern.promptHint), voiced around MIDI 48..71.
        \(r.drumPattern == .off ? "- drums: none" : "- drums: the host plays a \(r.drumPattern.promptHint); kick on beats \(kickBeats(r.drumPattern)) of every bar.")
        \(r.mood.isEmpty ? "" : "- mood: \(r.mood)")
        """
    }

    static func prompt(_ stage: Stage, _ r: GenerateRequest, _ arr: Arrangement) -> String {
        switch stage {
        case .harmony: return harmonyPrompt(r)
        case .bass: return bassPrompt(r, arr)
        case .rhythm: return rhythmPrompt(r, arr)
        case .melody: return melodyPrompt(r, arr)
        }
    }

    /// 1단계: 곡 구성과 섹션별 코드 진행.
    static func harmonyPrompt(_ r: GenerateRequest) -> String {
        let target = Arranger.targetBars(minutes: r.minutes, bpm: r.bpm)
        let lay = layout(targetBars: target)
        let progression = progressionText(r)
        let qualities = Theory.chordQualities.filter { $0.complexity <= r.complexity }.map(\.symbol).joined(separator: ", ")
        let riff = r.secondPart == .riff
        let complexityText = [
            "", "triads only", "triads and seventh chords", "seventh, ninth, sus and add chords",
            "also 11th, 13th, 6/9 and maj7#11 colour chords",
            "also altered dominants (7b9, 7#9, 7#11, 7b13, 7alt), mMaj7 and quartal chords",
        ][r.complexity]
        return """
        Step 1 of \(stages(r).count): write the form and the harmony (chords) of a piece. Bass, drums and melody are written later on top of these chords, so the chords must carry the song's structure on their own.
        \(brief(r))
        - chord complexity \(r.complexity)/\(Theory.maxComplexity): \(complexityText)
        - total length about \(fmt(r.minutes)) minutes, roughly \(target) bars. The host plays the intro sections once, repeats the loop sections to fill the length, then plays the outro sections once to end the song; do not write the full length.
        \(r.formPreset.promptHint.map { "- form: \($0)" } ?? "")
        \(progression.map { "- harmonic backbone: use this progression for the main section: \($0). Other sections may vary or reharmonize it." } ?? "")
        \(riff && r.formPreset != .kpop ? "- interlude: include one dramatic break section in the loop (role break), an instrumental moment over contrasting, more intense chords." : "")

        JSON schema:
        {
          "title": string,
          "form": {"intro": [section names played once at the start, may be empty], "loop": [section names in play order, repeated to fill the length, may repeat names], "outro": [section names played once at the end]},
          "sections": {
            "<name>": {
              "role": one of "intro" | "verse" | "prechorus" | "break" | "chorus" | "bridge" | "outro",
              "bars": integer 4..\(lay.maxBars) (a break may be 1 to 4),
              "chords": [{"root": "C", "quality": one of [\(qualities)], "beats": 4}]
            }
          }
        }
        Rules:
        - \(r.formPreset == .free ? "Define \(lay.sections) sections (for example Intro, A, B, Outro) with contrasting character; the loop has \(lay.formEntries) entries." : "Define exactly the sections of the given form; keep sections short (4 to \(lay.maxBars) bars) so the loop can repeat.")
        - chords: the beats of each section's chords add up to exactly bars*4. Chord roots should be diatonic to the scale unless a borrowed chord is musically intended.
        - harmonic rhythm: usually one chord per bar or two per bar; hold chords longer in calm sections and change faster where the music builds.
        - roles: verse is calm and stays near the tonic; prechorus builds tension and ends on a dominant or other unresolved chord; chorus is the strongest, resolving firmly to the tonic at its start or end; a break is an instrumental moment; bridge contrasts (for example starts on IV, vi or a borrowed chord); intro and outro are short and lighter, and the outro ends on the tonic.
        - the last chord of each loop section should lead smoothly into the section that follows it in the form, and the end of the loop back to its start.
        - No other fields.
        """
    }

    /// 2단계: 베이스 라인.
    static func bassPrompt(_ r: GenerateRequest, _ arr: Arrangement) -> String {
        let drums = r.drumPattern != .off
        let drumsKnown = arr.sections.values.contains { $0.drums != nil }
        return """
        Step \(stepNumber(.bass, r)) of \(stages(r).count): write the bass line. The chords\(drumsKnown ? " and the drum plan" : "") below are final; do not change them.
        \(brief(r))

        \(sheet(arr, bass: false, drums: drumsKnown, tones: 28...55))

        JSON schema:
        {"sections": {"<name>": {"bass": [[beat, midi_pitch, length_in_beats], ...]}}}
        Rules:
        - write a bass line for every section above, using the same section names.
        - beat is the offset from the section start (0 <= beat < bars*4); cover the whole section; notes must not overlap. Pitches within MIDI 28..55, below the accompaniment.
        - play the chord root on the beat where each chord starts (pick a "root" pitch from the MIDI list above); between changes use fifths, octaves and other chord tones, and lead into the next chord with scale or chromatic approach notes.
        - \(drums ? "lock with the drums: put most bass attacks on the kick beats (\(kickBeats(r.drumPattern))) and use the gaps for short pickups." : "there are no drums, so the bass and the accompaniment carry the pulse together: keep a steady, clear rhythm.")
        \(drumsKnown ? "- follow the drum plan: in sections with drums \"none\" or \"light\", play sparser and longer notes; with \"full\", drive harder; before a fill, the bass may rise or walk into the next section." : "")
        - shape by role: intro, verse and outro simpler (roots and fifths, longer notes); prechorus builds (repeated eighths or a rising line); chorus is the most driving and memorable; a bridge may use a pedal or a walking line; a break may play a bold unison-like figure or hold long notes.
        - tempo: \(r.bpm < 80 ? "slow, so mostly half and whole notes with occasional passing notes." : r.bpm < 110 ? "moderate, so mostly quarter and eighth notes with rests." : "fast, so steady eighths or punchy quarters; avoid busy sixteenth runs.")
        - No other fields.
        """
    }

    /// 2단계: 섹션별 드럼 편성 (패턴은 앱이 연주하고 강약과 필인만 정한다).
    static func rhythmPrompt(_ r: GenerateRequest, _ arr: Arrangement) -> String {
        let bassKnown = arr.sections.values.contains { !$0.bass.isEmpty }
        return """
        Step \(stepNumber(.rhythm, r)) of \(stages(r).count): plan the drums. The host plays a \(r.drumPattern.promptHint); you decide per section how much of it plays. The chords\(bassKnown ? " and the bass line" : "") below are final.
        \(brief(r))

        \(sheet(arr, bass: bassKnown, drums: false))

        JSON schema:
        {"sections": {"<name>": {"drums": {"energy": "none" | "light" | "full", "fill": true or false}}}}
        Rules:
        - give every section above a drum plan, using the same section names.
        - energy: "none" = no drums, "light" = hi-hats and side stick only, "full" = the whole groove. Shape an arc over the play order: for example a lighter intro and verses, full choruses, a quiet breakdown.
        - fill: true plays a drum fill in the section's last bar, leading into the next section; use it before a bigger section, not everywhere.
        \(bassKnown ? "- support the bass: a busy, driving bass line suits full drums; a sparse or sustained bass suits light or none." : "- the bass line will be written after the drums and will lock to their energy.")
        - No other fields.
        """
    }

    /// 3단계: 멜로디와 (Riff 이면) 리프. 완성된 반주 위에 얹는다.
    static func melodyPrompt(_ r: GenerateRequest, _ arr: Arrangement) -> String {
        let riff = r.secondPart == .riff
        let drumsKnown = arr.sections.values.contains { $0.drums != nil }
        let melodicText = [
            "", "simple, mostly stepwise, built from chord tones",
            "chord tones mixed with scale passing tones",
            "include 9ths and suspensions resolving to chord tones",
            "use 11th/13th tensions, chromatic approach notes and syncopated phrasing",
            "use altered tensions, chromatic enclosures, wide leaps and rhythmic displacement",
        ][r.complexity]
        let riffRules = """
        - riff: a short, memorable instrumental hook (1 or 2 bars) for a second instrument. It is NOT played under the melody: the host plays it only in bars where no melody note starts (as an answer between phrases) and throughout sections whose melody is empty. beat < riff bars*4, pitches within MIDI 48..72, about 2 to 8 notes per bar. It may land on any chord of the section, so prefer notes common to those chords (roots, fifths, shared scale tones), and let its rhythm interlock with the bass. Use an empty notes list when a section should have no riff.
        - melody phrasing: end phrases with rests of at least one full bar (no new note in that bar) so the riff can answer the melody. A break section has an empty melody and the riff carries it.
        """
        return """
        Step \(stages(r).count) of \(stages(r).count): write the melody\(riff ? " and the riff" : "") on top of the finished backing track. The chords, bass line\(drumsKnown ? " and drum plan" : "") below are final.
        \(brief(r))
        - melodic complexity: \(melodicText)
        \(r.melodyStyle == .free ? "" : "- melody style (\(r.melodyStyle.rawValue)): \(r.melodyStyle.promptHint)")

        \(sheet(arr, bass: true, drums: drumsKnown, tones: 60...88))

        JSON schema:
        {"sections": {"<name>": {"melody": [[beat, midi_pitch, length_in_beats], ...]\(riff ? ", \"riff\": {\"bars\": 1 or 2, \"notes\": [[beat, midi_pitch, length_in_beats], ...]}" : "")}}}
        Rules:
        - write every section above, using the same section names.
        - melody: beat is the offset from the section start (0 <= beat < bars*4), pitches within MIDI 60..88 and mostly from the scale notes, with rests, repeated motifs and phrase shape. Density: \(r.melodyStyle.notesPerBar). Notes must not overlap.
        - harmony: on strong beats (beats 0 and 2 of a bar) and wherever a chord changes, use a tone of the chord sounding at that beat (pick from its "all tones" MIDI list above); never sit a semitone above or below the bass note sounding at the same time. Non-chord tones are passing or neighbour notes that resolve by step.
        - roles: verse is calm and low, prechorus rises in register and density, chorus is the highest and most memorable hook (repeat its motif), a break has an empty melody (an instrumental moment), bridge contrasts, intro and outro are short and lighter or empty.
        - leave room for the accompaniment: \(r.chordPattern.promptHint).
        \(drumsKnown ? "- follow the drum plan: phrases may be more rhythmic in full-energy sections and more lyrical in light ones; land a phrase ending or pickup into the next section where a fill plays." : "")
        \(riff ? riffRules : "")
        - No other fields.
        """
    }

    private static func stepNumber(_ s: Stage, _ r: GenerateRequest) -> Int {
        (stages(r).firstIndex(of: s) ?? 0) + 1
    }

    /// 앞 단계까지의 결과를 섹션별 악보처럼 적는다. 코드는 섹션 길이만큼 펼쳐 시작 박과 구성음을 함께 보인다.
    /// tones 가 있으면 곡에 나오는 코드마다 그 음역의 구성음을 MIDI 번호로 풀어 준다 (음 이름 → 번호 변환 실수 방지).
    static func sheet(_ arr: Arrangement, bass: Bool, drums: Bool, tones: ClosedRange<Int>? = nil) -> String {
        var names: [String] = []
        for n in arr.form.all + arr.sections.keys.sorted() where arr.sections[n] != nil && !names.contains(n) { names.append(n) }
        var lines = [
            "Title: \(arr.title)",
            "Play order: intro \(arr.form.intro) | loop \(arr.form.loop) | outro \(arr.form.outro)",
            "Sections (beats count from the section start):",
        ]
        for n in names {
            let s = arr.sections[n]!
            lines.append("- \(n) (role \(s.role?.rawValue ?? "verse"), \(s.bars) bars = \(s.bars * 4) beats)")
            let timeline = chordTimeline(s).map { t, c in
                "\(fmt(t)) \(c.symbol) [\(c.quality.intervals.map { noteNames[(c.root + $0) % 12] }.joined(separator: " "))]"
            }
            lines.append("  chords: " + timeline.joined(separator: ", "))
            if bass && !s.bass.isEmpty { lines.append("  bass: " + noteList(s.bass)) }
            if drums, let d = s.drums { lines.append("  drums: \(d.energy.rawValue)\(d.fill ? ", fill into next section" : "")") }
        }
        if let tones {
            var seen: Set<String> = []
            lines.append("Chord tones as MIDI pitches within \(tones.lowerBound)..\(tones.upperBound):")
            for c in names.flatMap({ arr.sections[$0]!.chords }) where seen.insert(c.symbol).inserted {
                let pcs = Set(c.quality.intervals.map { (c.root + $0) % 12 })
                func list(_ f: (Int) -> Bool) -> String { tones.filter(f).map(String.init).joined(separator: " ") }
                lines.append("- \(c.symbol): root \(list { $0 % 12 == c.root }); all tones \(list { pcs.contains($0 % 12) })")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 섹션 길이만큼 순환시킨 코드의 시작 박. Arranger 가 연주하는 것과 같다.
    static func chordTimeline(_ s: SectionSpec) -> [(beat: Double, chord: ChordSpec)] {
        guard !s.chords.isEmpty else { return [] }
        var out: [(Double, ChordSpec)] = []
        var t = 0.0
        var i = 0
        while t < Double(s.bars * 4) - 1e-9 {
            let c = s.chords[i % s.chords.count]
            out.append((t, c))
            t += c.beats
            i += 1
        }
        return out
    }

    private static func noteList(_ notes: [MelodyNote]) -> String {
        "[" + notes.map { "[\(fmt($0.beat)),\($0.pitch),\(fmt($0.length))]" }.joined(separator: ",") + "]"
    }

    // MARK: 해석

    private static func object(_ text: String) throws -> [String: Any] {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw OpenRouterError.badJSON("JSON 객체 없음")
        }
        guard let obj = try JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any]
        else { throw OpenRouterError.badJSON("JSON 객체 없음") }
        return obj
    }

    private static func notes(_ raw: Any?) -> [MelodyNote] {
        ((raw as? [[NSNumber]]) ?? []).filter { $0.count >= 3 }
            .map { MelodyNote(beat: $0[0].doubleValue, pitch: $0[1].intValue, length: $0[2].doubleValue) }
    }

    /// 섹션 JSON 에 있는 파트(멜로디, 리프, 베이스, 드럼)만 덮어쓴다. 없는 키는 건드리지 않는다.
    private static func applyParts(_ s: [String: Any], to spec: inout SectionSpec) {
        if s["melody"] != nil { spec.melody = notes(s["melody"]) }
        if s["bass"] != nil { spec.bass = notes(s["bass"]) }
        if let riff = s["riff"] as? [String: Any] {
            spec.riffBars = max(1, min(4, (riff["bars"] as? NSNumber)?.intValue ?? 1))
            spec.riff = notes(riff["notes"])
        }
        if let d = s["drums"] as? [String: Any] {
            spec.drums = DrumPlan(
                energy: (d["energy"] as? String).flatMap { DrumPlan.Energy(rawValue: $0.lowercased()) } ?? .full,
                fill: (d["fill"] as? Bool) ?? false)
        }
    }

    /// 1단계 응답(또는 한 번에 쓴 곡 전체)을 해석한다.
    static func parse(_ text: String) throws -> Arrangement {
        let obj = try object(text)
        guard let secs = obj["sections"] as? [String: Any] else { throw OpenRouterError.badJSON("sections 없음") }

        var sections: [String: SectionSpec] = [:]
        for (name, raw) in secs {
            guard let s = raw as? [String: Any] else { continue }
            let bars = max(1, min(32, (s["bars"] as? NSNumber)?.intValue ?? 8))
            var chords: [ChordSpec] = []
            for c in (s["chords"] as? [[String: Any]]) ?? [] {
                guard let rootName = c["root"] as? String, let pc = pitchClass(of: rootName) else { continue }
                let q = (c["quality"] as? String).flatMap(Theory.quality(named:)) ?? Theory.chordQualities[0]
                let beats = max(1, min(16, (c["beats"] as? NSNumber)?.doubleValue ?? 4))
                chords.append(ChordSpec(root: pc, quality: q, beats: beats))
            }
            var spec = SectionSpec(name: name, bars: bars, chords: chords, melody: [])
            applyParts(s, to: &spec)
            spec.role = (s["role"] as? String).flatMap(SectionRole.init(loose:)) ?? SectionRole(guessing: name)
            sections[name] = spec
        }
        guard !sections.isEmpty else { throw OpenRouterError.badJSON("유효한 section 없음") }
        let form: SongForm
        if let f = obj["form"] as? [String: Any] {
            let parsed = SongForm(intro: f["intro"] as? [String] ?? [], loop: f["loop"] as? [String] ?? [], outro: f["outro"] as? [String] ?? [])
            // intro/outro 를 비우고 전부 loop 에 넣은 응답도 역할로 다시 나눈다
            form = parsed.intro.isEmpty && parsed.outro.isEmpty ? SongForm.split(parsed.loop, sections: sections) : parsed
        } else {
            form = SongForm.split(obj["form"] as? [String] ?? [], sections: sections)
        }
        return Arrangement(title: (obj["title"] as? String) ?? "Untitled", sections: sections, form: form)
    }

    /// 2·3단계 응답을 이미 있는 섹션에 합친다. 모르는 섹션 이름은 버리고, 하나도 맞지 않으면 실패.
    static func merge(_ text: String, into arr: inout Arrangement) throws {
        guard let secs = try object(text)["sections"] as? [String: Any] else { throw OpenRouterError.badJSON("sections 없음") }
        var matched = 0
        for (name, raw) in secs {
            guard let s = raw as? [String: Any], var spec = arr.sections[name] else { continue }
            applyParts(s, to: &spec)
            arr.sections[name] = spec
            matched += 1
        }
        guard matched > 0 else { throw OpenRouterError.badJSON("알려진 section 없음") }
    }

    /// progress 는 각 단계를 시작할 때 (단계, 몇 번째, 전체 수) 로 불린다.
    static func generate(_ r: GenerateRequest, client: OpenRouterClient,
                         progress: @escaping @MainActor (Stage, Int, Int) -> Void = { _, _, _ in }) async throws -> Arrangement {
        let all = stages(r)
        await progress(.harmony, 1, all.count)
        var arr = try parse(await client.complete(system: system, user: harmonyPrompt(r)))
        for (i, stage) in all.enumerated().dropFirst() {
            await progress(stage, i + 1, all.count)
            try merge(await client.complete(system: system, user: prompt(stage, r, arr)), into: &arr)
        }
        return arr
    }
}
