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

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .off: return "리듬 채널을 쓰지 않음"
        case .rock: return "킥-스네어 백비트에 8분음표 하이햇"
        case .fourOnFloor: return "4분음표 킥, 2·4박 스네어, 뒷박 오픈 하이햇 (댄스/하우스)"
        case .ballad: return "느린 하프타임: 3박 사이드스틱, 여린 하이햇"
        case .shuffle: return "셋잇단 스윙 하이햇과 백비트"
        case .bossa: return "보사노바: 사이드스틱 클라베와 하이햇 8분음표"
        case .funk: return "16분음표 하이햇과 고스트 노트 스네어"
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
        }
    }

    /// General MIDI 드럼 노트
    enum Kit {
        static let kick = 36, sideStick = 37, snare = 38, closedHat = 42, openHat = 46, crash = 49
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

    private static func hats(every step: Double, count: Int, accentEvery: Int = 2, loud: Int = 78, soft: Int = 56) -> [Hit] {
        (0..<count).map { Hit(note: Kit.closedHat, beat: Double($0) * step, velocity: $0 % accentEvery == 0 ? loud : soft) }
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
                out.append(NoteEvent(channel: channel, pitch: h.note, velocity: max(1, min(127, h.velocity)),
                                     start: start + offset + h.beat, length: 0.2))
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
