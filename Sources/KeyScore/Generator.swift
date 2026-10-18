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
}

enum Generator {
    static let system = """
    You are a composer assistant. Reply with a single JSON object only, no prose, no code fences.
    You write short reusable song sections; the host program repeats them to reach the required length.
    """

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

    static func prompt(_ r: GenerateRequest) -> String {
        let target = Arranger.targetBars(minutes: r.minutes, bpm: r.bpm)
        let lay = layout(targetBars: target)
        let progression = progressionText(r)
        let scaleNotes = r.scale.intervals.map { noteNames[(r.root + $0) % 12] }.joined(separator: " ")
        let qualities = Theory.chordQualities.filter { $0.complexity <= r.complexity }.map(\.symbol).joined(separator: ", ")
        let riff = r.secondPart == .riff
        let drums = r.drumPattern != .off
        let drumRules = """
        - drums: per section choose "energy" ("none" = no drums, "light" = hi-hats and side stick only, "full" = the whole groove) to shape the form, for example a lighter intro and verses, full choruses, a quiet breakdown. "fill": true plays a drum fill in the section's last bar, leading into the next section; use it before a bigger section, not everywhere.
        """
        let riffRules = """
        - riff: a short, memorable instrumental hook (1 or 2 bars) for a second instrument. It is NOT played under the melody: the host plays it only in bars where no melody note starts (as an answer between phrases) and throughout sections whose melody is empty. beat < riff bars*4, pitches within MIDI 48..72, about 2 to 8 notes per bar. It may land on any chord of the section, so prefer notes common to those chords (roots, fifths, shared scale tones). Use an empty notes list when a section should have no riff.
        - melody phrasing: end phrases with rests of at least one full bar (no new note in that bar) so the riff can answer the melody.
        """
        let complexityText = [
            "", "triads only", "triads and seventh chords", "seventh, ninth, sus and add chords",
            "also 11th, 13th, 6/9 and maj7#11 colour chords",
            "also altered dominants (7b9, 7#9, 7#11, 7b13, 7alt), mMaj7 and quartal chords",
        ][r.complexity]
        let melodicText = [
            "", "simple, mostly stepwise, built from chord tones",
            "chord tones mixed with scale passing tones",
            "include 9ths and suspensions resolving to chord tones",
            "use 11th/13th tensions, chromatic approach notes and syncopated phrasing",
            "use altered tensions, chromatic enclosures, wide leaps and rhythmic displacement",
        ][r.complexity]
        return """
        Compose a piece with these constraints:
        - key: \(noteNames[r.root]), scale: \(r.scale.name) (notes: \(scaleNotes))
        - tempo: \(Int(r.bpm)) BPM, 4/4 (\(tempoFeel(r.bpm)))
        - chord complexity \(r.complexity)/\(Theory.maxComplexity): \(complexityText)
        - melodic complexity: \(melodicText)
        - total length about \(String(format: "%g", r.minutes)) minutes, roughly \(target) bars (the host will repeat the form; do not write the full length)
        - accompaniment: the host plays every chord as \(r.chordPattern.promptHint). Write chords and a melody that fit this accompaniment.
        \(progression.map { "- harmonic backbone: use this progression for the main section: \($0). Other sections may vary or reharmonize it." } ?? "")
        \(r.mood.isEmpty ? "" : "- mood: \(r.mood)")
        \(r.melodyStyle == .free ? "" : "- melody style (\(r.melodyStyle.rawValue)): \(r.melodyStyle.promptHint)")
        \(drums ? "- drums: the host plays a \(r.drumPattern.promptHint). Write a melody that sits in this groove." : "")
        \(riff ? "- interlude: include one dramatic instrumental section (for example Interlude or Break) with an empty melody, where the riff carries the music over contrasting, more intense chords." : "")

        JSON schema:
        {
          "title": string,
          "form": [section names in play order, \(lay.formEntries) entries, may repeat names],
          "sections": {
            "<name>": {
              "bars": integer 4..\(lay.maxBars),
              "chords": [{"root": "C", "quality": one of [\(qualities)], "beats": 4}],
              "melody": [[beat, midi_pitch, length_in_beats], ...]\(riff ? ",\n      \"riff\": {\"bars\": 1 or 2, \"notes\": [[beat, midi_pitch, length_in_beats], ...]}" : "")\(drums ? ",\n      \"drums\": {\"energy\": \"none\" | \"light\" | \"full\", \"fill\": true or false}" : "")
            }
          }
        }
        Rules:
        - Define \(lay.sections) sections (for example Intro, A, B, Outro) with contrasting character.
        - chords: cover the whole section; the list loops if shorter. Chord roots should be diatonic to the scale unless a borrowed chord is musically intended.
        - melody: beat is the offset from the section start (0 <= beat < bars*4), pitches within MIDI 60..88 and mostly from the scale notes, with rests, repeated motifs and phrase shape. Density: \(r.melodyStyle.notesPerBar). Notes must not overlap.
        \(riff ? riffRules : "")
        \(drums ? drumRules : "")
        - No other fields.
        """
    }

    static func parse(_ text: String) throws -> Arrangement {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw OpenRouterError.badJSON("JSON 객체 없음")
        }
        let slice = String(text[start...end])
        guard let obj = try JSONSerialization.jsonObject(with: Data(slice.utf8)) as? [String: Any],
              let secs = obj["sections"] as? [String: Any]
        else { throw OpenRouterError.badJSON("sections 없음") }

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
            var melody: [MelodyNote] = []
            for n in (s["melody"] as? [[NSNumber]]) ?? [] where n.count >= 3 {
                melody.append(MelodyNote(beat: n[0].doubleValue, pitch: n[1].intValue, length: n[2].doubleValue))
            }
            var spec = SectionSpec(name: name, bars: bars, chords: chords, melody: melody)
            if let riff = s["riff"] as? [String: Any] {
                spec.riffBars = max(1, min(4, (riff["bars"] as? NSNumber)?.intValue ?? 1))
                for n in (riff["notes"] as? [[NSNumber]]) ?? [] where n.count >= 3 {
                    spec.riff.append(MelodyNote(beat: n[0].doubleValue, pitch: n[1].intValue, length: n[2].doubleValue))
                }
            }
            if let d = s["drums"] as? [String: Any] {
                spec.drums.energy = (d["energy"] as? String).flatMap { DrumPlan.Energy(rawValue: $0.lowercased()) } ?? .full
                spec.drums.fill = (d["fill"] as? Bool) ?? false
            }
            sections[name] = spec
        }
        guard !sections.isEmpty else { throw OpenRouterError.badJSON("유효한 section 없음") }
        let form = (obj["form"] as? [String]) ?? []
        return Arrangement(title: (obj["title"] as? String) ?? "Untitled", sections: sections, form: form)
    }

    static func generate(_ r: GenerateRequest, client: OpenRouterClient) async throws -> Arrangement {
        let text = try await client.complete(system: system, user: prompt(r))
        return try parse(text)
    }
}
