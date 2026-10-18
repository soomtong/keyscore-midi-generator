import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let lengths: [Double] = [1, 3, 5, 8, 12]

    enum Tab: Hashable { case generate, listen }
    enum PreviewKind { case scale, chord, progression, melody }

    @Published var tab: Tab = .generate
    @Published var showSettings = false
    /// 하단 단축키 패널. 처음에는 열려 있고, 닫은 상태는 다음 실행에도 기억한다.
    @Published var showShortcuts = UserDefaults.standard.object(forKey: "ui.showShortcuts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showShortcuts, forKey: "ui.showShortcuts") }
    }
    /// 텍스트 입력 중에는 메뉴의 평문 단축키를 비활성화한다.
    @Published var isTyping = false

    // 공통
    @Published var root = 0
    @Published var scaleIndex = 0
    @Published var bpm = 100.0
    @Published var complexity = 2
    @Published var loop = false { didSet { player.setLoop(loop) } }
    @Published var chordPattern: ChordPattern = .block
    @Published var melodyStyle: MelodyStyle = .free
    @Published var melodyChannel = 1
    @Published var chordChannel = 2
    @Published var bassChannel = 3

    // 생성
    @Published var minutes = 3.0
    @Published var mood = ""
    @Published var model = ModelCatalog.initial() { didSet { ModelCatalog.save(model) } }
    @Published var apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? Keychain.load() ?? ""
    @Published var arrangement: Arrangement?
    @Published var isGenerating = false

    /// 일시적인 안내/오류 메시지. 비어 있으면 숨긴다. (상시 상태는 상단 디스플레이 아이콘이 맡는다.)
    @Published var status = "" { didSet { scheduleStatusClear() } }

    // 청취
    @Published var chordQualityIndex = 0
    @Published var progressionIndex = 0
    @Published var listenOptions = ListenOptions()
    @Published var autoReplay = true

    // 페달: Tab 을 누르고 있는 동안(held) 또는 고정(latched)이면 서스테인(CC64)
    @Published var pedalHeld = false { didSet { syncPedal() } }
    @Published var pedalLatched = false { didSet { syncPedal() } }
    var pedalActive: Bool { pedalHeld || pedalLatched }

    // 재생
    @Published var isPlaying = false
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var nowPlaying = ""
    /// 현재 재생 중인 것이 생성된 곡(true)인지 청취용 프리뷰(false)인지
    @Published var playingArrangement = false
    /// MIDI Note On 이 나가는 순간 잠깐 켜지는 표시등
    @Published var midiActive = false

    private let player = MidiPlayer()
    private var song: Song?
    private var lastPreview: PreviewKind?
    private var statusTask: Task<Void, Never>?
    private var midiTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var scale: ScaleType { Theory.scales[scaleIndex] }
    var channels: ChannelMap { ChannelMap(melody: melodyChannel, chords: chordChannel, bass: bassChannel) }
    var hasAPIKey: Bool { !apiKey.isEmpty }

    init() {
        player.onProgress = { [weak self] t in
            Task { @MainActor in self?.position = t }
        }
        player.onStop = { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
                self?.position = 0
            }
        }
        player.onActivity = { [weak self] in
            Task { @MainActor in self?.flashMIDI() }
        }

        // 자동 재생: 청취 중에 값을 바꾸면 잠시 뒤 새 설정으로 다시 시작
        let triggers: [AnyPublisher<Void, Never>] = [
            $root.map { _ in }.eraseToAnyPublisher(),
            $scaleIndex.map { _ in }.eraseToAnyPublisher(),
            $bpm.map { _ in }.eraseToAnyPublisher(),
            $complexity.map { _ in }.eraseToAnyPublisher(),
            $melodyStyle.map { _ in }.eraseToAnyPublisher(),
            $chordQualityIndex.map { _ in }.eraseToAnyPublisher(),
            $progressionIndex.map { _ in }.eraseToAnyPublisher(),
            $listenOptions.map { _ in }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(triggers)
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.autoReplayIfNeeded() }
            .store(in: &cancellables)
        // 코드 패턴은 패턴 듣기(코드 진행 재생)에서만 소리에 영향을 준다
        $chordPattern.map { _ in }
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.autoReplayIfNeeded(patternOnly: true) }
            .store(in: &cancellables)
    }

    /// 곡 재료를 무작위로 바꾼다. 청취 옵션(rate/음 길이)은 includeListenOptions 일 때만.
    /// 채널·옥타브·Together 등 연주 환경 설정은 건드리지 않는다.
    func randomize(includeListenOptions: Bool = false) {
        root = Int.random(in: 0..<12)
        scaleIndex = Int.random(in: 0..<Theory.scales.count)
        bpm = Double(Int.random(in: 60...150))
        complexity = Int.random(in: 1...Theory.maxComplexity)
        // Free (AI) 는 로컬에서 들을 수 없으므로 제외
        melodyStyle = MelodyStyle.allCases.filter { $0 != .free }.randomElement()!
        chordPattern = ChordPattern.allCases.randomElement()!
        progressionIndex = Int.random(in: 0..<Theory.progressions.count)
        listenOptions.varyMelody = Bool.random()
        var summary = "\(noteNames[root]) \(scale.name), \(Int(bpm)) BPM, 복잡도 \(complexity), \(melodyStyle.rawValue), \(chordPattern.rawValue)"
        if includeListenOptions {
            // 스케일/코드 순차 청취용. 너무 빠르거나 느린 값(rate 2)은 뺀다.
            let rate = ListenOptions.rates.filter { $0 <= 1 }.randomElement()!
            listenOptions.rate = rate
            // Auto 를 절반 확률로 두고, 나머지는 rate 이하의 길이로 제한
            let lengths = ListenOptions.lengths.filter { $0 > 0 && $0 <= rate }
            listenOptions.noteLength = Bool.random() ? 0 : lengths.randomElement()!
            summary += ", rate \(ListenOptions.label(beats: rate)), 음 길이 \(ListenOptions.label(beats: listenOptions.noteLength))"
        }
        status = "Randomize: " + summary
    }

    func saveKey() { Keychain.save(apiKey) }

    // MARK: 상태 표시

    private func scheduleStatusClear() {
        statusTask?.cancel()
        // 오류와 진행 중 메시지는 남겨 둔다
        guard !status.isEmpty, !status.hasPrefix("실패"), !isGenerating else { return }
        let delay = status.count > 60 ? 12.0 : 4.0
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.status = ""
        }
    }

    private func flashMIDI() {
        midiActive = true
        midiTask?.cancel()
        midiTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            self?.midiActive = false
        }
    }

    // MARK: 재생

    func play(_ s: Song, arrangement: Bool = false) {
        song = s
        playingArrangement = arrangement
        duration = s.seconds
        nowPlaying = s.title
        isPlaying = true
        player.play(s, loop: loop)
    }

    func stop() { player.stop() }

    func replay() { if let song { play(song, arrangement: playingArrangement) } }

    func togglePlayback() {
        if isPlaying { stop() } else { replay() }
    }

    private func syncPedal() { player.setPedal(pedalActive) }

    // MARK: 조작 (메뉴와 단축키가 공유)

    func toggleLoop() {
        loop.toggle()
        status = loop ? "반복 켬" : "반복 끔"
    }

    func toggleSettings() { showSettings.toggle() }

    func toggleShortcuts() { showShortcuts.toggle() }

    func adjustBPM(_ delta: Double) {
        bpm = min(200, max(40, bpm + delta))
        status = "Tempo \(Int(bpm)) BPM"
    }

    func shiftRoot(_ d: Int) {
        root = (root + d + 12) % 12
        status = "Key \(noteNames[root])"
    }

    func shiftScale(_ d: Int) {
        let n = Theory.scales.count
        scaleIndex = (scaleIndex + d + n) % n
        status = "Scale \(scale.name)"
    }

    func setComplexity(_ v: Int) {
        complexity = v
        status = "복잡도 \(v) · \(Theory.complexityNames[v])"
    }

    /// 청취 대상 선택 이동 (스케일은 shiftScale). 선택만 바꾸고, 재생 중이면 자동 재생이 새 선택으로 다시 들려준다.
    func shiftChordQuality(_ d: Int) {
        let n = Theory.chordQualities.count
        chordQualityIndex = (chordQualityIndex + d + n) % n
        status = "코드 \(Theory.chordQualities[chordQualityIndex].symbol)"
    }

    func shiftProgression(_ d: Int) {
        let n = Theory.progressions.count
        progressionIndex = (progressionIndex + d + n) % n
        status = "진행 \(Theory.progressions[progressionIndex].name)"
    }

    func shiftLength(_ d: Int) {
        let i = Self.lengths.firstIndex(of: minutes) ?? 1
        minutes = Self.lengths[min(Self.lengths.count - 1, max(0, i + d))]
        status = "길이 \(Int(minutes))분"
    }

    func cycleChordPattern(_ d: Int = 1) {
        let all = ChordPattern.allCases
        chordPattern = all[(all.firstIndex(of: chordPattern)! + d + all.count) % all.count]
        status = "코드 패턴: \(chordPattern.rawValue)"
    }

    func cycleMelodyStyle(_ d: Int = 1) {
        let all = MelodyStyle.allCases
        melodyStyle = all[(all.firstIndex(of: melodyStyle)! + d + all.count) % all.count]
        status = "멜로디 패턴: \(melodyStyle.rawValue)"
    }

    // 청취 옵션
    func shiftExtendUp(_ d: Int) {
        listenOptions.extendUp = min(ListenOptions.maxExtend, max(0, listenOptions.extendUp + d))
        status = "코드 위 확장 \(listenOptions.extendUp)"
    }

    func shiftExtendDown(_ d: Int) {
        listenOptions.extendDown = min(ListenOptions.maxExtend, max(0, listenOptions.extendDown + d))
        status = "코드 아래 확장 \(listenOptions.extendDown)"
    }

    func shiftOctave(_ d: Int) {
        listenOptions.octave = min(2, max(-2, listenOptions.octave + d))
        status = "옥타브 \(listenOptions.octave > 0 ? "+" : "")\(listenOptions.octave)"
    }

    func shiftNoteLength(_ d: Int) {
        let all = ListenOptions.lengths
        let i = all.firstIndex(of: listenOptions.noteLength) ?? 0
        listenOptions.noteLength = all[min(all.count - 1, max(0, i + d))]
        status = "음 길이 \(ListenOptions.label(beats: listenOptions.noteLength))"
    }

    // MARK: 단축키

    /// ANSI 배열 기준 키코드. 한글 등 ASCII 가 아닌 입력기에서도 단축키가 동작하도록 한다.
    private static let keyCodeFallback: [UInt16: String] = [
        0: "a", 1: "s", 3: "f", 4: "h", 5: "g", 8: "c", 37: "l", 38: "j", 40: "k", 46: "m",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 30: "]", 33: "[", 43: ",", 47: ".",
    ]

    private static func key(of event: NSEvent) -> String? {
        let typed = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if let first = typed.first, first.isASCII { return typed }
        return keyCodeFallback[event.keyCode]
    }

    /// 처리했으면 true. 텍스트 입력 중에는 호출하지 않는다. ⌘/⌥/⌃ 조합은 메뉴가 처리한다.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        guard flags.intersection([.command, .option, .control]).isEmpty else { return false }
        let shift = flags.contains(.shift)
        let step = shift ? 5.0 : 1.0
        switch event.keyCode {
        case 49:  // space
            if !event.isARepeat { togglePlayback() }
            return true
        case 123: adjustBPM(-step); return true  // ←
        case 124: adjustBPM(step); return true  // →
        case 126: shiftRoot(1); return true  // ↑
        case 125: shiftRoot(-1); return true  // ↓
        case 48:  // Tab: 누르는 동안 페달
            if !event.isARepeat { pedalHeld = true }
            return true
        default: break
        }
        guard let key = Self.key(of: event) else { return false }
        if event.isARepeat && !"hjkl[],.".contains(key) { return "gscfam12345".contains(key) }  // 반복 입력은 소비만
        switch key {
        case "h": adjustBPM(-step)  // vim: ← → ↓ ↑
        case "l": adjustBPM(step)
        case "k": shiftRoot(1)
        case "j": shiftRoot(-1)
        case "[": shiftScale(-1)
        case "]": shiftScale(1)
        case "1", "2", "3", "4", "5": setComplexity(Int(key)!)
        case ",": shiftLength(-1)
        case ".": shiftLength(1)
        case "a": cycleChordPattern(shift ? -1 : 1)
        case "m": cycleMelodyStyle(shift ? -1 : 1)
        case "g": listen(.melody)
        // S/C/F: 듣기, Shift: 다음 선택 (⌥ 는 메뉴에서 이전 선택)
        case "s":
            if shift { shiftScale(1) } else { listen(.scale) }  // 스케일은 Key·Scale 카드에서 고르므로 탭은 그대로
        case "c":
            tab = .listen
            if shift { shiftChordQuality(1) } else { listen(.chord) }
        case "f":
            tab = .listen
            if shift { shiftProgression(1) } else { listen(.progression) }
        default: return false
        }
        return true
    }

    /// Tab 을 떼면 페달을 올린다. 텍스트 입력 중이어도 항상 처리한다.
    func handleKeyUp(_ event: NSEvent) -> Bool {
        guard event.keyCode == 48, pedalHeld else { return false }
        pedalHeld = false
        return true
    }

    // MARK: 생성

    func generate() {
        guard !isGenerating else { return }
        saveKey()
        isGenerating = true
        status = "OpenRouter(\(model))에서 생성 중…"
        let req = GenerateRequest(root: root, scale: scale, bpm: bpm, complexity: complexity, minutes: minutes, mood: mood, melodyStyle: melodyStyle)
        let client = OpenRouterClient(apiKey: apiKey, model: model)
        Task {
            do {
                let arr = try await Generator.generate(req, client: client)
                arrangement = arr
                let s = buildSong()!
                isGenerating = false
                status = "\"\(arr.title)\" 생성 완료 — \(Int(s.seconds / 60))분 \(Int(s.seconds) % 60)초, 노트 \(s.events.count)개"
                play(s, arrangement: true)
            } catch {
                isGenerating = false
                status = "실패: \(error.localizedDescription)"
            }
        }
    }

    /// 현재 템포/길이/채널/패턴으로 arrangement 를 다시 전개.
    func buildSong() -> Song? {
        guard let arrangement else { return nil }
        let opts = ArrangeOptions(bpm: bpm, minutes: minutes, channels: channels, chordPattern: chordPattern)
        return Arranger.build(arrangement, options: opts)
    }

    var targetBars: Int { Arranger.targetBars(minutes: minutes, bpm: bpm) }

    /// 현재 템포/길이로 전개했을 때의 섹션 배치 (타임라인 표시용)
    var layout: [(name: String, bars: Int)] {
        guard let arrangement else { return [] }
        return Arranger.expandForm(arrangement.form, sections: arrangement.sections, targetBars: targetBars)
            .compactMap { name in arrangement.sections[name].map { (name, $0.bars) } }
    }

    func rebuildAndPlay() {
        if let s = buildSong() { play(s, arrangement: true) }
    }

    // MARK: 청취

    private func buildPreview(_ kind: PreviewKind) -> Song? {
        let o = listenOptions
        switch kind {
        case .scale:
            return Preview.scale(root: root, type: scale, channel: melodyChannel, options: o, bpm: bpm)
        case .melody:
            guard melodyStyle != .free else { return nil }
            return Preview.melody(root: root, scale: scale, style: melodyStyle, channel: melodyChannel, options: o, bpm: bpm)
        case .chord:
            return Preview.chord(
                root: root, quality: Theory.chordQualities[chordQualityIndex],
                channel: chordChannel, options: o, bpm: bpm)
        case .progression:
            return Preview.progression(
                root: root, scale: scale, prog: Theory.progressions[progressionIndex], complexity: complexity,
                pattern: chordPattern, channels: channels, options: o, bpm: bpm)
        }
    }

    func listen(_ kind: PreviewKind) {
        if kind == .melody && listenOptions.varyMelody { listenOptions.melodySeed = .random(in: .min ... .max) }
        guard let s = buildPreview(kind) else {
            status = "Free (AI) 는 곡 생성 시에만 적용됩니다. 로컬로 들으려면 다른 멜로디 패턴을 고르세요."
            return
        }
        lastPreview = kind
        play(s)
    }

    private func autoReplayIfNeeded(patternOnly: Bool = false) {
        guard autoReplay, isPlaying, !playingArrangement, let kind = lastPreview else { return }
        if patternOnly && kind != .progression { return }
        guard let s = buildPreview(kind) else { return }
        // 값을 바꾼 직후 재생을 시작하면 150ms 뒤 이 호출이 와서 방금 시작한 재생을 처음부터 다시 틀게 된다.
        // 지금 재생 중인 것과 같은 소리라면 건드리지 않는다.
        if let current = song, current.bpm == s.bpm, current.events == s.events { return }
        play(s)
    }
}
