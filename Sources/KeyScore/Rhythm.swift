import Foundation

/// 리듬 채널용 드럼 패턴. General MIDI 드럼 맵(노트 번호)을 쓰므로 리듬 채널은 보통
/// 16채널 악기에서는 10번, 8채널 악기에서는 8번을 지정한다.
enum DrumPattern: String, CaseIterable, Identifiable {
    case off = "Off"
    case rock = "Rock 8th"
    case fourOnFloor = "Four on the Floor"
    case ballad = "Ballad"
    case shuffle = "Shuffle"
    case bossa = "Bossa"
    case funk = "Funk 16th"
    case swing = "Swing"
    case pop = "Pop 16th"
    case halfTime = "Half-time"
    case disco = "Disco"
    case motown = "Motown"
    case breakbeat = "Breakbeat"
    case boomBap = "Boom Bap"
    case trap = "Trap"
    case reggaeton = "Reggaeton"
    case afrobeats = "Afrobeats"

    var id: String { rawValue }

    /// 메뉴 묶음
    enum Group: String, CaseIterable {
        case classic = "기본"
        case modern = "모던 팝"
        case urban = "어반"
    }

    var group: Group {
        switch self {
        case .off, .rock, .fourOnFloor, .ballad, .shuffle, .bossa, .funk, .swing: return .classic
        case .pop, .halfTime, .disco, .motown, .breakbeat: return .modern
        case .boomBap, .trap, .reggaeton, .afrobeats: return .urban
        }
    }

    static func grouped() -> [(Group, [DrumPattern])] {
        Group.allCases.map { g in (g, allCases.filter { $0.group == g }) }
    }

    var summary: String {
        switch self {
        case .off: return "리듬 채널을 쓰지 않음"
        case .rock: return "킥-스네어 백비트에 8분음표 하이햇"
        case .fourOnFloor: return "4분음표 킥, 2·4박 스네어, 뒷박 오픈 하이햇 (댄스/하우스)"
        case .ballad: return "느린 하프타임: 3박 사이드스틱, 여린 하이햇"
        case .shuffle: return "셋잇단 스윙 하이햇과 백비트"
        case .bossa: return "보사노바: 사이드스틱 클라베와 하이햇 8분음표"
        case .funk: return "16분음표 하이햇과 고스트 노트 스네어"
        case .swing: return "재즈 라이드 심벌(딩-딩가-딩)과 2·4박 페달 하이햇, 여린 킥"
        case .pop: return "16분음표 하이햇, 스네어+클랩 백비트, 당김음 킥 (현대 팝)"
        case .halfTime: return "3박에만 스네어, 넓게 깔리는 하프타임 (팝 발라드 · 시네마틱)"
        case .disco: return "4분음표 킥, 뒷박 오픈 하이햇, 16분음표 하이햇과 클랩 (디스코 · 누디스코)"
        case .motown: return "매 박 스네어와 탬버린 8분음표 (모타운 · 60s 소울)"
        case .breakbeat: return "아멘 브레이크 풍 킥 당김음과 고스트 스네어"
        case .boomBap: return "묵직한 킥과 스네어, 느긋한 8분음표 하이햇 (90s 힙합 · 네오소울)"
        case .trap: return "하프타임 스네어+클랩, 16분음표 하이햇과 마디 끝 롤 (트랩 · R&B)"
        case .reggaeton: return "뎀보우: 4분음표 킥 위에 당김음 스네어 (레게톤 · 라틴 팝)"
        case .afrobeats: return "당김음 킥과 림, 탬버린 16분음표 (아프로비츠)"
        }
    }

    /// 곡 생성 프롬프트용 영문 설명: 드럼 그루브와 그에 맞는 멜로디 프레이징.
    var promptHint: String {
        switch self {
        case .off: return ""
        case .rock: return "straight rock beat, eighth-note hi-hats and a backbeat on 2 and 4"
        case .fourOnFloor: return "four-on-the-floor dance groove with off-beat open hi-hats: steady, repetitive phrasing fits"
        case .ballad: return "soft half-time ballad groove: sparse, leave room for long melodic notes"
        case .shuffle: return "triplet shuffle groove: swing the melody (off-beat eighths on triplet offsets such as 0.667)"
        case .bossa: return "bossa nova groove with a clave-like side stick: gently syncopated, anticipated phrasing fits"
        case .funk: return "sixteenth-note funk groove with ghost notes: short, syncopated, percussive phrasing fits"
        case .swing: return "jazz swing ride pattern with hi-hat on 2 and 4: swing the melody (off-beat eighths on triplet offsets such as 0.667), a walking bass fits"
        case .pop: return "modern pop groove with sixteenth-note hi-hats, snare and clap on 2 and 4 and a syncopated kick: catchy, rhythmic phrasing fits"
        case .halfTime: return "half-time groove with the snare only on beat 3: slow, wide phrasing with long notes fits"
        case .disco: return "disco groove, four-on-the-floor with off-beat open hi-hats and claps: steady, danceable phrasing fits"
        case .motown: return "Motown groove with the snare on every beat and tambourine eighths: bright, bouncing phrasing fits"
        case .breakbeat: return "breakbeat groove with syncopated kicks and ghost snares: energetic, syncopated phrasing fits"
        case .boomBap: return "boom bap hip-hop groove, heavy kick and snare with laid-back eighth-note hi-hats: relaxed, behind-the-beat phrasing fits"
        case .trap: return "trap groove, half-time snare and clap with rapid sixteenth hi-hats and rolls: sparse melody with space fits"
        case .reggaeton: return "reggaeton dembow groove, kick on every beat with syncopated snares at 0.75 and 1.5: syncopated, rhythmic phrasing fits"
        case .afrobeats: return "afrobeats groove with syncopated kick and rim pattern over tambourine sixteenths: lilting, syncopated phrasing fits"
        }
    }

    /// General MIDI 드럼 노트
    enum Kit {
        static let kick = 36, sideStick = 37, snare = 38, clap = 39, closedHat = 42, pedalHat = 44, openHat = 46, crash = 49, ride = 51, tambourine = 54
        static let floorTom = 43, lowTom = 45, midTom = 47, highTom = 50
    }

    struct Hit: Equatable {
        var note: Int
        var beat: Double
        var velocity: Int
    }

    private static func hits(_ note: Int, _ beats: [Double], _ vel: Int) -> [Hit] {
        beats.map { Hit(note: note, beat: $0, velocity: vel) }
    }

    /// 클로즈 하이햇. open 자리에는 넣지 않는다 (GM 에서 두 하이햇은 초크 그룹이라 같은 tick 에 치면 오픈이 바로 끊긴다).
    private static func hats(every step: Double, count: Int, accentEvery: Int = 2, loud: Int = 78, soft: Int = 56, open: [Double] = []) -> [Hit] {
        (0..<count).map { Hit(note: Kit.closedHat, beat: Double($0) * step, velocity: $0 % accentEvery == 0 ? loud : soft) }
            .filter { h in !open.contains { abs($0 - h.beat) < 1e-9 } }
    }

    /// 4박 한 마디의 타격. bar 는 0부터 세는 마디 번호 (보사노바 클라베가 2마디 주기).
    func bar(_ bar: Int) -> [Hit] {
        switch self {
        case .off:
            return []
        case .rock:
            return Self.hits(Kit.kick, [0, 2, 2.5], 100) + Self.hits(Kit.snare, [1, 3], 96) + Self.hats(every: 0.5, count: 8)
        case .fourOnFloor:
            return Self.hits(Kit.kick, [0, 1, 2, 3], 100) + Self.hits(Kit.snare, [1, 3], 90)
                + Self.hits(Kit.openHat, [0.5, 1.5, 2.5, 3.5], 70)
        case .ballad:
            return Self.hits(Kit.kick, [0, 2.5], 88) + Self.hits(Kit.sideStick, [2], 80) + Self.hats(every: 0.5, count: 8, accentEvery: 2, loud: 56, soft: 40)
        case .shuffle:
            let swing = (0..<4).flatMap { b in [Hit(note: Kit.closedHat, beat: Double(b), velocity: 80),
                                                Hit(note: Kit.closedHat, beat: Double(b) + 2.0 / 3, velocity: 58)] }
            return Self.hits(Kit.kick, [0, 2], 100) + Self.hits(Kit.snare, [1, 3], 94) + swing
        case .bossa:
            let clave = bar % 2 == 0 ? [0, 1.5, 3] : [1, 2]
            return Self.hits(Kit.kick, [0, 1.5, 2, 3.5], 90) + Self.hits(Kit.sideStick, clave, 84) + Self.hats(every: 0.5, count: 8, loud: 66, soft: 50)
        case .funk:
            return Self.hits(Kit.kick, [0, 1.75, 2.5], 100) + Self.hits(Kit.snare, [1, 3], 98)
                + Self.hits(Kit.snare, [0.75, 2.25, 3.5], 34)
                + Self.hats(every: 0.25, count: 16, accentEvery: 4, loud: 80, soft: 48)
        case .swing:
            let ride = [(0.0, 88), (1.0, 80), (1 + 2.0 / 3, 60), (2.0, 88), (3.0, 80), (3 + 2.0 / 3, 60)]
                .map { Hit(note: Kit.ride, beat: $0.0, velocity: $0.1) }
            return Self.hits(Kit.kick, [0, 2], 48) + Self.hits(Kit.pedalHat, [1, 3], 72) + ride
        case .pop:
            return Self.hits(Kit.kick, [0, 1.75, 2.5], 104) + Self.hits(Kit.snare, [1, 3], 96) + Self.hits(Kit.clap, [1, 3], 84)
                + Self.hats(every: 0.25, count: 16, accentEvery: 2, loud: 70, soft: 44, open: [3.5]) + Self.hits(Kit.openHat, [3.5], 72)
        case .halfTime:
            return Self.hits(Kit.kick, [0, 1.5], 104) + Self.hits(Kit.snare, [2], 100) + Self.hits(Kit.clap, [2], 80)
                + Self.hats(every: 0.5, count: 8, loud: 66, soft: 46, open: [3.5]) + Self.hits(Kit.openHat, [3.5], 68)
        case .disco:
            let open = [0.5, 1.5, 2.5, 3.5]
            return Self.hits(Kit.kick, [0, 1, 2, 3], 104) + Self.hits(Kit.snare, [1, 3], 94) + Self.hits(Kit.clap, [1, 3], 76)
                + Self.hits(Kit.openHat, open, 78) + Self.hats(every: 0.25, count: 16, accentEvery: 4, loud: 52, soft: 40, open: open)
        case .motown:
            return Self.hits(Kit.kick, [0, 2], 96) + Self.hits(Kit.snare, [0, 1, 2, 3], 84)
                + (0..<8).map { Hit(note: Kit.tambourine, beat: Double($0) * 0.5, velocity: $0 % 2 == 0 ? 72 : 52) }
        case .breakbeat:
            return Self.hits(Kit.kick, [0, 0.5, 2.5], 104) + Self.hits(Kit.snare, [1, 3], 100) + Self.hits(Kit.snare, [1.75, 2.25, 3.75], 38)
                + Self.hats(every: 0.5, count: 8, loud: 76, soft: 54)
        case .boomBap:
            return Self.hits(Kit.kick, [0, 0.75, 2.5], 108) + Self.hits(Kit.snare, [1, 3], 106)
                + Self.hats(every: 0.5, count: 8, loud: 64, soft: 42)
        case .trap:
            let roll = [3.5, 3.625, 3.75, 3.875].enumerated().map { Hit(note: Kit.closedHat, beat: $1, velocity: 50 + $0 * 8) }
            return Self.hits(Kit.kick, [0, 1.5, 3.25], 110) + Self.hits(Kit.snare, [2], 104) + Self.hits(Kit.clap, [2], 88)
                + Self.hats(every: 0.25, count: 14, accentEvery: 2, loud: 64, soft: 44) + roll
        case .reggaeton:
            return Self.hits(Kit.kick, [0, 1, 2, 3], 104) + Self.hits(Kit.snare, [0.75, 1.5, 2.75, 3.5], 92)
                + Self.hats(every: 0.5, count: 8, loud: 60, soft: 44)
        case .afrobeats:
            return Self.hits(Kit.kick, [0, 1.5, 2.5], 100) + Self.hits(Kit.sideStick, [1, 2.75, 3.5], 86) + Self.hits(Kit.clap, [3], 70)
                + (0..<16).map { Hit(note: Kit.tambourine, beat: Double($0) * 0.25, velocity: $0 % 4 == 0 ? 58 : 36) }
        }
    }

    /// 같은 패턴을 여리게: 하이햇·사이드스틱은 살리고, 킥은 첫 박만, 백비트 스네어는 사이드스틱으로, 고스트 노트는 뺀다.
    static func light(_ hits: [Hit]) -> [Hit] {
        hits.compactMap { h in
            switch h.note {
            case Kit.kick: return h.beat == 0 ? Hit(note: h.note, beat: h.beat, velocity: h.velocity - 24) : nil
            case Kit.snare: return h.velocity >= 60 ? Hit(note: Kit.sideStick, beat: h.beat, velocity: h.velocity - 30) : nil
            default: return Hit(note: h.note, beat: h.beat, velocity: max(20, h.velocity - 14))
            }
        }
    }

    /// 마디 후반 두 박을 채우는 필인: 16분음표로 스네어에서 탐으로 내려오며 점점 세게.
    static let fill: [Hit] = zip([Kit.snare, Kit.snare, Kit.snare, Kit.snare, Kit.highTom, Kit.highTom, Kit.midTom, Kit.lowTom],
                                 0...).map { note, i in Hit(note: note, beat: 2 + Double(i) * 0.25, velocity: 70 + i * 5) }
        + [Hit(note: Kit.kick, beat: 2, velocity: 96), Hit(note: Kit.floorTom, beat: 3.75, velocity: 108)]

    /// start 박부터 beats 박 동안의 드럼 노트. crashOnStart 이면 첫 박에 크래시 심벌을 더한다 (섹션 전환 표시).
    /// energy 는 섹션 편성(none 이면 쉼), fill 이면 마지막 마디 후반 두 박을 필인으로 바꾼다.
    func notes(start: Double, beats: Double, channel: UInt8, crashOnStart: Bool = false,
               energy: DrumPlan.Energy = .full, fill: Bool = false) -> [NoteEvent] {
        guard self != .off, energy != .none, beats > 0 else { return [] }
        let bars = Int((beats / 4).rounded(.up))
        var out: [NoteEvent] = []
        for barIndex in 0..<bars {
            let offset = Double(barIndex) * 4
            var hits = energy == .light ? Self.light(bar(barIndex)) : bar(barIndex)
            if fill && barIndex == bars - 1 && beats - offset > 2 {
                hits = hits.filter { $0.beat < 2 } + Self.fill
            }
            for h in hits where offset + h.beat < beats - 1e-9 {
                // 마디 끝의 롤(트랩 3.875박)이 구간을 넘지 않게 길이를 자른다
                out.append(NoteEvent(channel: channel, pitch: h.note, velocity: max(1, min(127, h.velocity)),
                                     start: start + offset + h.beat, length: min(0.2, beats - offset - h.beat)))
            }
        }
        if crashOnStart { out.append(NoteEvent(channel: channel, pitch: Kit.crash, velocity: energy == .light ? 80 : 100, start: start, length: 1)) }
        return out
    }
}

/// 섹션별 드럼 편성. 곡 생성 시 LLM 이 섹션마다 정하고, 없거나 알 수 없는 값이면 full · 필인 없음.
struct DrumPlan: Equatable {
    enum Energy: String, Comparable {
        case none, light, full

        private var rank: Int { self == .none ? 0 : self == .light ? 1 : 2 }
        static func < (a: Energy, b: Energy) -> Bool { a.rank < b.rank }
    }

    var energy: Energy = .full
    var fill = false
}
