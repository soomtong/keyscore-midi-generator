import Foundation

struct GenerateRequest {
    var root: Int
    var scale: ScaleType
    var bpm: Double
    var complexity: Int
    var minutes: Double
    var mood: String = ""
    var melodyStyle: MelodyStyle = .free
}

enum Generator {
    static let system = """
    You are a composer assistant. Reply with a single JSON object only, no prose, no code fences.
    You write short reusable song sections; the host program repeats them to reach the required length.
    """

    static func prompt(_ r: GenerateRequest) -> String {
        let scaleNotes = r.scale.intervals.map { noteNames[(r.root + $0) % 12] }.joined(separator: " ")
        let qualities = Theory.chordQualities.filter { $0.complexity <= r.complexity }.map(\.symbol).joined(separator: ", ")
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
        - tempo: \(Int(r.bpm)) BPM, 4/4
        - chord complexity \(r.complexity)/\(Theory.maxComplexity): \(complexityText)
        - melodic complexity: \(melodicText)
        - total length about \(String(format: "%g", r.minutes)) minutes (the host will repeat the form; do not write the full length)
        \(r.mood.isEmpty ? "" : "- mood: \(r.mood)")
        \(r.melodyStyle == .free ? "" : "- melody style (\(r.melodyStyle.rawValue)): \(r.melodyStyle.promptHint)")

        JSON schema:
        {
          "title": string,
          "form": [section names in play order, 6 to 10 entries, may repeat names],
          "sections": {
            "<name>": {
              "bars": integer 4..16,
              "chords": [{"root": "C", "quality": one of [\(qualities)], "beats": 4}],
              "melody": [[beat, midi_pitch, length_in_beats], ...]
            }
          }
        }
        Rules:
        - Define 3 or 4 sections (for example Intro, A, B, Outro) with contrasting character.
        - chords: cover the whole section; the list loops if shorter. Chord roots should be diatonic to the scale unless a borrowed chord is musically intended.
        - melody: beat is the offset from the section start (0 <= beat < bars*4), pitches within MIDI 60..88 and mostly from the scale notes, with rests, repeated motifs and phrase shape. Roughly 2 to 5 notes per bar. Notes must not overlap.
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
            sections[name] = SectionSpec(name: name, bars: bars, chords: chords, melody: melody)
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
