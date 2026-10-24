import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// 앱 상태. `@Observable` 이라 SwiftUI 는 실제로 읽은 프로퍼티가 바뀐 뷰만 다시 그린다
/// (재생 중 position 이 초당 20회 바뀌어도 진행 표시만 갱신된다).
@MainActor
@Observable
final class AppModel {
    /// 곡 길이(분): 30초 단위로 자유롭게 조절. 눈금자에는 lengthLandmarks 만 숫자로 표시한다.
    static let lengthRange: ClosedRange<Double> = 0.5...12
    static let lengthStep = 0.5
    static let lengthLandmarks: [Double] = [1, 3, 5, 8, 12]
    /// 청취 중 값을 바꾸면 이 시간 뒤에 새 설정으로 다시 시작한다.
    static let autoReplayDelay: Duration = .milliseconds(150)

    static func snapLength(_ m: Double) -> Double {
        min(lengthRange.upperBound, max(lengthRange.lowerBound, (m / lengthStep).rounded() * lengthStep))
    }

    /// 1:30 같은 m:ss 표기
    static func lengthLabel(_ m: Double) -> String {
        let secs = Int((m * 60).rounded())
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    enum Tab: Hashable { case generate, listen }
    enum PreviewKind { case scale, chord, progression, melody }

    var tab: Tab = .generate
    var showSettings = false
    /// 하단 단축키 패널. 처음에는 열려 있고, 닫은 상태는 다음 실행에도 기억한다.
    var showShortcuts = UserDefaults.standard.object(forKey: "ui.showShortcuts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showShortcuts, forKey: "ui.showShortcuts") }
    }
    /// 텍스트 입력 중에는 메뉴의 평문 단축키를 비활성화한다.
    var isTyping = false

    // 공통. 청취 소리에 영향을 주는 값은 바뀌면 자동 재생을 예약한다.
    var root = 0 { didSet { scheduleAutoReplay() } }
    var scaleIndex = 0 { didSet { scheduleAutoReplay() } }
    var bpm = 100.0 { didSet { scheduleAutoReplay() } }
    var complexity = 2 { didSet { scheduleAutoReplay() } }
    var loop = false { didSet { player.setLoop(loop) } }
    /// 코드 패턴은 패턴 듣기(코드 진행 재생)에서만 소리에 영향을 준다
    var chordPattern: ChordPattern = .block { didSet { scheduleAutoReplay(patternOnly: true) } }
    /// 멜로디 듣기의 프레이즈. phraseGuidesMelody 가 켜져 있으면 곡 생성에 멜로디 성격의 본보기로 들어간다.
    var phrase: Phrase = Phrase.all[0] { didSet { scheduleAutoReplay() } }
    /// 곡 생성 멜로디에 선택한 프레이즈의 성격과 밀도를 반영한다. 기본은 끔: 켜지 않으면 AI 가 자유롭게 쓴다.
    var phraseGuidesMelody = false
    var melodyChannel = 1
    var chordChannel = 2
    var bassChannel = 3
    var secondChannel = 4
    /// 리프는 Riff 로 생성할 때만 요청하므로, 다른 설정으로 만든 곡에서 Riff 로 바꾸면 소리가 없다는 것을 알린다.
    var secondPart: SecondPart = .off {
        didSet {
            let missing = secondPart == .riff && arrangement.map { $0.sections.values.allSatisfy { $0.riff.isEmpty } } == true
            status = "두 번째 파트: \(secondPart.rawValue) (ch \(secondChannel))"
                + (missing ? " — 이 곡에는 리프가 없습니다. Riff 로 다시 생성하세요" : "")
        }
    }
    var rhythmChannel = 10 { didSet { scheduleAutoReplay() } }
    var drumPattern: DrumPattern = .off { didSet { scheduleAutoReplay() } }
    var formPreset: FormPreset = .free

    // 생성
    var minutes = 3.0
    var mood = ""
    var model = ModelCatalog.initial() { didSet { ModelCatalog.save(model) } }
    /// 환경변수 OPENROUTER_API_KEY > Keychain. init 에서 채운다.
    var apiKey = ""
    var arrangement: Arrangement?
    /// 지금 곡을 전개할 때 쓴 설정과 생성할 때 쓴 설정. 화면의 곡 정보는 이 값으로 그려 들리는 곡과 맞춘다.
    private(set) var arrangedWith: ArrangeSettings?
    private(set) var generatedWith: PromptSettings?
    /// 지금 곡이 실제로 전개된 섹션 배치 (타임라인 표시용). 설정을 바꿔도 다시 전개하기 전에는 그대로다.
    private(set) var layout: [(name: String, bars: Int)] = []
    /// 마지막으로 전개한 곡. 내보내기는 이것을 그대로 쓴다 (다시 전개하면 멜로디 세기가 무작위라 들은 곡과 달라진다).
    private(set) var arrangedSong: Song?
    var isGenerating = false

    /// 일시적인 안내/오류 메시지. 비어 있으면 숨긴다. (상시 상태는 상단 디스플레이 아이콘이 맡는다.)
    var status = "" { didSet { scheduleStatusClear() } }

    // 청취
    var chordQualityIndex = 0 { didSet { scheduleAutoReplay() } }
    var progressionIndex = 0 { didSet { scheduleAutoReplay() } }
    var listenOptions = ListenOptions() { didSet { scheduleAutoReplay() } }
    var autoReplay = true

    // 페달: Tab 을 누르고 있는 동안(held) 또는 고정(latched)이면 서스테인(CC64)
    var pedalHeld = false { didSet { syncPedal() } }
    var pedalLatched = false { didSet { syncPedal() } }
    var pedalActive: Bool { pedalHeld || pedalLatched }
    /// MIDI Clock(4분음표당 24 펄스)과 Start/Stop 송신. 수신 측이 앱 템포를 따라오게 할 때 켠다.
    /// Clock 을 받으면 트랜스포트가 움직이는 수신기도 있어 기본은 끄고, 켠 상태는 다음 실행에도 기억한다.
    var sendClock = UserDefaults.standard.bool(forKey: "midi.sendClock") {
        didSet {
            UserDefaults.standard.set(sendClock, forKey: "midi.sendClock")
            player.setClock(sendClock)
        }
    }

    // 재생
    var isPlaying = false
    var position = 0.0
    var duration = 0.0
    var nowPlaying = ""
    /// 현재 재생 중인 것이 생성된 곡(true)인지 청취용 프리뷰(false)인지
    var playingArrangement = false
    /// MIDI Note On 이 나가는 순간 잠깐 켜지는 표시등
    var midiActive = false

    @ObservationIgnored private let player = MidiPlayer()
    @ObservationIgnored private var song: Song?
    @ObservationIgnored private var lastPreview: PreviewKind?
    @ObservationIgnored private var playSession = 0
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var midiTask: Task<Void, Never>?
    @ObservationIgnored private var autoReplayTask: Task<Void, Never>?
    @ObservationIgnored private var generateTask: Task<Void, Never>?
    /// Keychain 에 들어 있는(또는 환경변수로 받은) 키. 같은 값이면 다시 쓰지 않고, 환경변수 키는 Keychain 에 남기지 않는다.
    @ObservationIgnored private var persistedKey = ""
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?

    var scale: ScaleType { Theory.scales[scaleIndex] }
    var channels: ChannelMap { ChannelMap(melody: melodyChannel, chords: chordChannel, bass: bassChannel, second: secondChannel, rhythm: rhythmChannel) }
    var hasAPIKey: Bool { !apiKey.isEmpty }

    init() {
        let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? Keychain.load() ?? ""
        apiKey = key
        persistedKey = key
        player.setClock(sendClock)
        player.onProgress = { [weak self] t in
            Task { @MainActor in self?.position = t }
        }
        player.onStop = { [weak self] session in
            Task { @MainActor in self?.playbackStopped(session) }
        }
        player.onActivity = { [weak self] in
            Task { @MainActor in self?.flashMIDI() }
        }
        // ⌘Q 로 끝내도 수신 측 트랜스포트와 울리던 음이 남지 않게
        let player = player
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            player.stopNow()
        }
    }

    deinit {
        statusTask?.cancel()
        midiTask?.cancel()
        autoReplayTask?.cancel()
        generateTask?.cancel()
    }

    /// 곡 재료를 무작위로 바꾼다. 청취 옵션(rate/음 길이)은 includeListenOptions 일 때만.
    /// 채널·옥타브·Together 등 연주 환경 설정은 건드리지 않는다.
    func randomize(includeListenOptions: Bool = false) {
        root = Int.random(in: 0..<12)
        scaleIndex = Int.random(in: 0..<Theory.scales.count)
        bpm = Double(Int.random(in: 60...150))
        complexity = Int.random(in: 1...Theory.maxComplexity)
        phrase = Phrase.all.randomElement()!
        chordPattern = ChordPattern.allCases.randomElement()!
        progressionIndex = Int.random(in: 0..<Theory.progressions.count)
        listenOptions.varyMelody = Bool.random()
        var summary = "\(noteNames[root]) \(scale.name), \(Int(bpm)) BPM, 복잡도 \(complexity), \(phrase.name), \(chordPattern.rawValue)"
        if includeListenOptions {
            // 코드 순차 청취용. 너무 빠르거나 느린 값(rate 2)은 뺀다.
            let rate = ListenOptions.rates.filter { $0 <= 1 }.randomElement()!
            listenOptions.rate = rate
            // Auto 를 절반 확률로 두고, 나머지는 rate 이하의 길이로 제한
            let lengths = ListenOptions.lengths.filter { $0 > 0 && $0 <= rate }
            listenOptions.noteLength = Bool.random() ? 0 : lengths.randomElement()!
            summary += ", rate \(ListenOptions.label(beats: rate)), 음 길이 \(ListenOptions.label(beats: listenOptions.noteLength))"
        }
        status = "Randomize: " + summary
    }

    /// 사용자가 바꾼 키만 Keychain 에 쓴다.
    func saveKey() {
        guard apiKey != persistedKey else { return }
        if Keychain.save(apiKey) {
            persistedKey = apiKey
        } else {
            status = "실패: API key 를 Keychain 에 저장하지 못했습니다"
        }
    }

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
        playSession = player.play(s, loop: loop)
    }

    func stop() { player.stop() }

    /// 마지막으로 튼 것을 현재 설정으로 다시 만들어 처음부터 튼다. 다시 만들 수 없으면 마지막 곡을 그대로 튼다.
    func replay() {
        let rebuilt = playingArrangement ? buildSong() : lastPreview.flatMap(buildPreview)
        if let s = rebuilt ?? song { play(s, arrangement: playingArrangement) }
    }

    func togglePlayback() {
        if isPlaying { stop() } else { replay() }
    }

    /// 정지 알림. 정지 직후 새 재생을 시작했으면 이전 재생의 알림은 무시한다.
    private func playbackStopped(_ session: Int) {
        guard session == playSession else { return }
        isPlaying = false
        position = 0
    }

    private func syncPedal() { player.setPedal(pedalActive) }

    // MARK: 조작 (메뉴와 단축키가 공유)

    func toggleLoop() {
        loop.toggle()
        status = loop ? "반복 켬" : "반복 끔"
    }

    func toggleClock() {
        sendClock.toggle()
        status = sendClock ? "MIDI Clock 송신 켬" : "MIDI Clock 송신 끔"
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
        minutes = Self.snapLength(minutes + Double(d) * Self.lengthStep)
        status = "길이 \(Self.lengthLabel(minutes))"
    }

    func cycleDrumPattern(_ d: Int = 1) {
        drumPattern = drumPattern.cycled(by: d)
        status = "리듬 패턴: \(drumPattern.rawValue) (ch \(rhythmChannel))"
    }

    func cycleSecondPart(_ d: Int = 1) {
        secondPart = secondPart.cycled(by: d)
    }

    func cycleChordPattern(_ d: Int = 1) {
        chordPattern = chordPattern.cycled(by: d)
        status = "패턴: \(chordPattern.rawValue)"
    }

    func cyclePhrase(_ d: Int = 1) {
        let all = Phrase.all
        let i = all.firstIndex(of: phrase) ?? 0
        phrase = all[((i + d) % all.count + all.count) % all.count]
        status = "프레이즈: \(phrase.name) — \(phrase.summary)"
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
        if event.isARepeat && !"hjkl[],.".contains(key) { return "gscfamdr12345".contains(key) }  // 반복 입력은 소비만
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
        case "m": cyclePhrase(shift ? -1 : 1)
        case "d": cycleDrumPattern(shift ? -1 : 1)
        case "r": cycleSecondPart(shift ? -1 : 1)
        case "g": listen(.melody)
        // S/C/F: 듣기, Shift: 다음 선택 (⌥ 는 메뉴에서 이전 선택)
        case "s":
            if shift { shiftScale(1) } else { listen(.scale) }  // 스케일은 Key·Scale 카드에서 고르므로 탭은 그대로
        case "c":
            if shift { shiftChordQuality(1) } else { listen(.chord) }  // 코드 듣기는 탭 밖 CHORD 카드
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
        let req = GenerateRequest(root: root, scale: scale, bpm: bpm, complexity: complexity, minutes: minutes, mood: mood, phrase: phraseGuidesMelody ? phrase : nil,
                                  chordPattern: chordPattern, progression: Theory.progressions[progressionIndex], secondPart: secondPart,
                                  drumPattern: drumPattern, formPreset: formPreset)
        // 생성 중에 설정을 바꿔도 요청한 그때의 설정으로 전개한다
        let prompt = promptSettings
        let arrange = arrangeSettings
        let client = OpenRouterClient(apiKey: apiKey, model: model)
        generateTask = Task { [weak self] in
            defer { self?.isGenerating = false }
            do {
                let arr = try await Generator.generate(req, client: client) { [weak self] stage, step, total in
                    self?.status = "OpenRouter(\(client.model)) \(step)/\(total) \(stage.label) 구성 중…"
                }
                guard let self, !Task.isCancelled else { return }
                let s = adopt(arr, prompt: prompt, arrange: arrange)
                isGenerating = false
                status = "\"\(arr.title)\" 생성 완료 — \(Int(s.seconds / 60))분 \(Int(s.seconds) % 60)초, 노트 \(s.events.count)개"
                play(s, arrangement: true)
            } catch is CancellationError {
                self?.isGenerating = false
                self?.status = "생성을 취소했습니다"
            } catch {
                self?.isGenerating = false
                self?.status = "실패: \(error.localizedDescription)"
            }
        }
    }

    /// 진행 중인 생성을 중단한다. 이미 받은 단계는 버린다.
    func cancelGenerate() {
        generateTask?.cancel()
    }

    var arrangeSettings: ArrangeSettings {
        ArrangeSettings(bpm: bpm, minutes: minutes, chordPattern: chordPattern, drumPattern: drumPattern,
                        secondPart: secondPart, channels: channels)
    }

    var promptSettings: PromptSettings {
        PromptSettings(root: root, scaleIndex: scaleIndex, complexity: complexity, phrase: phraseGuidesMelody ? phrase : nil,
                       mood: mood, progressionIndex: progressionIndex, formPreset: formPreset)
    }

    /// 곡을 만든 뒤 바뀐 전개 설정 (↻ 다시 전개로 반영)
    var pendingArrange: [String] {
        guard arrangement != nil, let old = arrangedWith else { return [] }
        return arrangeSettings.changes(from: old)
    }

    /// 곡을 만든 뒤 바뀐 프롬프트 설정 (다시 생성해야 반영)
    var pendingPrompt: [String] {
        guard arrangement != nil, let old = generatedWith else { return [] }
        return promptSettings.changes(from: old)
    }

    /// 생성된 곡을 받아 요청 당시의 설정으로 전개한다.
    func adopt(_ arr: Arrangement, prompt: PromptSettings, arrange: ArrangeSettings) -> Song {
        arrangement = arr
        generatedWith = prompt
        return buildSong(with: arrange)!
    }

    /// arrangement 를 settings(기본: 현재 설정)로 전개하고, 그 설정과 섹션 배치를 기억한다.
    func buildSong(with settings: ArrangeSettings? = nil) -> Song? {
        guard let arrangement else { return nil }
        let used = settings ?? arrangeSettings
        arrangedWith = used
        layout = Arranger.expandForm(arrangement.form, sections: arrangement.sections, targetBars: used.targetBars)
            .compactMap { name in arrangement.sections[name].map { (name, $0.bars) } }
        let built = Arranger.build(arrangement, options: used.options)
        arrangedSong = built
        return built
    }

    /// 다음 생성/전개의 목표 마디 수 (현재 설정)
    var targetBars: Int { Arranger.targetBars(minutes: minutes, bpm: bpm) }

    func rebuildAndPlay() {
        if let s = buildSong() { play(s, arrangement: true) }
    }

    // MARK: 내보내기

    /// 마지막으로 전개한 곡을 MIDI 파일(SMF Format 1)로 저장한다.
    func exportMIDI() {
        guard let song = arrangedSong, let used = arrangedWith else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.midi]
        panel.nameFieldStringValue = Self.fileName(song.title) + ".mid"
        panel.canCreateDirectories = true
        let names = Self.trackNames(used)
        Task {
            guard await panel.begin() == .OK, let url = panel.url else { return }
            do {
                try MidiFile.data(song, trackNames: names).write(to: url, options: .atomic)
                status = "MIDI 파일 저장: \(url.lastPathComponent)"
            } catch {
                status = "실패: MIDI 파일을 저장하지 못했습니다 (\(error.localizedDescription))"
            }
        }
    }

    /// 채널(0-based)별 트랙 이름. 꺼진 파트는 빼고, 같은 채널을 쓰는 파트는 " + " 로 잇는다.
    nonisolated static func trackNames(_ s: ArrangeSettings) -> [UInt8: String] {
        let c = s.channels
        let parts = [("Melody", c.melody, true), ("Chords", c.chords, true), ("Bass", c.bass, true),
                     ("Second", c.second, s.secondPart != .off), ("Rhythm", c.rhythm, s.drumPattern != .off)]
        var names: [UInt8: [String]] = [:]
        for (name, ch, on) in parts where on && (1...16).contains(ch) {
            names[UInt8(ch - 1), default: []].append(name)
        }
        return names.mapValues { $0.joined(separator: " + ") }
    }

    /// 파일 이름으로 쓸 수 없는 문자를 바꾼다. 비면 "KeyScore".
    nonisolated static func fileName(_ title: String) -> String {
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .map { "/:\\".contains($0) || $0.isNewline ? "-" : String($0) }.joined()
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? "KeyScore" : String(name.prefix(100))
    }

    // MARK: 청취

    /// Groove 옵션: 진행 · 프레이즈에 묶인 드럼을 쓴다. 묶인 것이 없으면 패턴 듣기는 리듬 패턴 설정, 멜로디 듣기는 없음.
    var progressionDrums: DrumPattern {
        listenOptions.groove ? (Theory.progressions[progressionIndex].drums ?? drumPattern) : drumPattern
    }

    var phraseDrums: DrumPattern { listenOptions.groove ? (phrase.drums ?? .off) : .off }

    private func buildPreview(_ kind: PreviewKind) -> Song {
        let o = listenOptions
        switch kind {
        case .scale:
            return Preview.scale(root: root, type: scale, channel: melodyChannel, octave: o.octave, bpm: bpm)
        case .melody:
            return Preview.melody(root: root, scale: scale, phrase: phrase, channel: melodyChannel, drums: phraseDrums,
                                  rhythmChannel: rhythmChannel, options: o, bpm: bpm)
        case .chord:
            return Preview.chord(
                root: root, quality: Theory.chordQualities[chordQualityIndex],
                channel: chordChannel, options: o, bpm: bpm)
        case .progression:
            return Preview.progression(
                root: root, scale: scale, prog: Theory.progressions[progressionIndex], complexity: complexity,
                pattern: chordPattern, channels: channels, drums: progressionDrums, options: o, bpm: bpm)
        }
    }

    func listen(_ kind: PreviewKind) {
        if kind == .melody && listenOptions.varyMelody { listenOptions.melodySeed = .random(in: .min ... .max) }
        lastPreview = kind
        play(buildPreview(kind))
    }

    /// 자동 재생 디바운스: 값이 연달아 바뀌면 마지막 변경 뒤 autoReplayDelay 가 지나서 한 번만 다시 튼다.
    private func scheduleAutoReplay(patternOnly: Bool = false) {
        autoReplayTask?.cancel()
        autoReplayTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autoReplayDelay)
            guard !Task.isCancelled else { return }
            self?.autoReplayIfNeeded(patternOnly: patternOnly)
        }
    }

    private func autoReplayIfNeeded(patternOnly: Bool) {
        guard autoReplay, isPlaying, !playingArrangement, let kind = lastPreview else { return }
        if patternOnly && kind != .progression { return }
        let s = buildPreview(kind)
        // 값을 바꾼 직후 재생을 시작하면 잠시 뒤 이 호출이 와서 방금 시작한 재생을 처음부터 다시 틀게 된다.
        // 지금 재생 중인 것과 같은 소리라면 건드리지 않는다.
        if let current = song, current.bpm == s.bpm, current.events == s.events { return }
        play(s)
    }
}

extension CaseIterable where Self: Equatable {
    /// allCases 에서 d 칸 옮긴 값 (양 끝에서 순환).
    func cycled(by d: Int) -> Self {
        let all = Array(Self.allCases)
        let i = all.firstIndex(of: self) ?? 0
        return all[((i + d) % all.count + all.count) % all.count]
    }
}
