import Foundation

/// 섹션의 역할. 이름은 LLM 이 마음대로 붙여도 되고, 앱은 역할로 판단한다.
enum SectionRole: String, CaseIterable {
    case intro, verse, prechorus, `break`, chorus, bridge, outro

    /// LLM 이 drums 를 주지 않았을 때(리듬 Off 로 생성했거나 값을 빠뜨림)의 기본 편성.
    var defaultDrums: DrumPlan {
        switch self {
        case .intro: return DrumPlan(energy: .light)
        case .verse: return DrumPlan(energy: .light)
        case .prechorus: return DrumPlan(energy: .light, fill: true)
        case .break: return DrumPlan(energy: .full, fill: true)
        case .chorus: return DrumPlan(energy: .full)
        case .bridge: return DrumPlan(energy: .light, fill: true)
        case .outro: return DrumPlan(energy: .light)
        }
    }

    /// "Pre-Chorus", "pre_chorus" 같은 표기도 받는다.
    init?(loose text: String) {
        let key = text.lowercased().filter(\.isLetter)
        guard let role = Self(rawValue: key) ?? (key == "interlude" ? .break : nil) else { return nil }
        self = role
    }

    /// role 이 없을 때 섹션 이름으로 추정. 모르면 verse.
    init(guessing name: String) {
        let n = name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        if has("intro", "인트로") { self = .intro }
        else if has("outro", "ending", "coda", "아웃트로", "엔딩") { self = .outro }
        else if has("pre", "프리", "build") { self = .prechorus }
        else if has("chorus", "hook", "후렴", "refrain") { self = .chorus }
        else if has("break", "interlude", "간주", "solo", "drop") { self = .break }
        else if has("bridge", "브릿지") { self = .bridge }
        else { self = .verse }
    }
}

/// 곡 구조: intro 는 처음에 한 번, loop 는 길이를 채울 때까지 반복, outro 는 끝에 한 번.
struct SongForm: Equatable, ExpressibleByArrayLiteral {
    var intro: [String] = []
    var loop: [String] = []
    var outro: [String] = []

    var all: [String] { intro + loop + outro }

    init(intro: [String] = [], loop: [String], outro: [String] = []) {
        self.intro = intro
        self.loop = loop
        self.outro = outro
    }

    /// 순서만 있는 배열(이전 형식)은 loop 로 본다. 이름/역할로 나누려면 split(_:sections:) 를 쓴다.
    init(arrayLiteral names: String...) {
        loop = names
    }

    /// 순서만 있는 배열을 맨 앞의 intro 역할, 맨 뒤의 outro 역할로 나눈다. 나머지가 비면 전부 loop.
    static func split(_ names: [String], sections: [String: SectionSpec]) -> SongForm {
        func role(_ n: String) -> SectionRole { sections[n]?.role ?? SectionRole(guessing: n) }
        var rest = names[...]
        var intro: [String] = []
        var outro: [String] = []
        while let f = rest.first, role(f) == .intro { intro.append(f); rest = rest.dropFirst() }
        while let l = rest.last, role(l) == .outro { outro.insert(l, at: 0); rest = rest.dropLast() }
        guard !rest.isEmpty else { return SongForm(loop: names) }
        return SongForm(intro: intro, loop: Array(rest), outro: outro)
    }
}

/// 곡 생성 탭의 FORM 선택. 프롬프트에 역할 순서를 지정한다.
enum FormPreset: String, CaseIterable, Identifiable {
    case free = "Free (AI)"
    case kpop = "A-B-간주-후렴"
    case verseChorus = "Verse-Chorus"
    case aaba = "AABA"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .free: return "LLM 이 구성을 정함 (intro / loop / outro)"
        case .kpop: return "인트로 | A · B · 간주 · 후렴 반복 | 후렴 · 아웃트로"
        case .verseChorus: return "인트로 | A · 후렴 반복 | 후렴 · 아웃트로"
        case .aaba: return "A · A · B(브릿지) · A 반복 | 짧은 엔딩"
        }
    }

    /// 프롬프트용 형식 지시. free 면 nil.
    var promptHint: String? {
        switch self {
        case .free:
            return nil
        case .kpop:
            return """
            use this K-pop style form exactly: intro ["Intro" (intro)], loop ["A" (verse: low, calm, storytelling), "B" (prechorus: rising register and density, builds tension), "Break" (break: 1 to 4 bars, empty melody, instrumental lead-in that holds the breath before the chorus), "Chorus" (chorus: highest register, the main hook)], outro ["Chorus", "Outro" (outro)]
            """
        case .verseChorus:
            return """
            use this verse-chorus form exactly: intro ["Intro" (intro)], loop ["Verse" (verse), "Chorus" (chorus: highest register, the main hook)], outro ["Chorus", "Outro" (outro)]
            """
        case .aaba:
            return """
            use this AABA (32-bar standard) form exactly: no intro, loop ["A" (verse), "A", "B" (bridge: contrasting key area and melody), "A"], outro ["Ending" (outro: a short 2 to 4 bar tag)]. Each A and B is 8 bars.
            """
        }
    }
}
