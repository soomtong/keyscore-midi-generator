import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let lengths: [Double] = [1, 3, 5, 8, 12]

    enum Tab: Hashable { case generate, listen, settings }
    @Published var tab: Tab = .generate

    // 공통
    @Published var root = 0
    @Published var scaleIndex = 0
    @Published var bpm = 100.0
    @Published var complexity = 2
    @Published var loop = false { didSet { player.setLoop(loop) } }
    @Published var chordPattern: ChordPattern = .block
    @Published var melodyChannel = 1
    @Published var chordChannel = 2
    @Published var bassChannel = 3

    // 생성
    @Published var minutes = 3.0
    @Published var mood = ""
    @Published var model = ProcessInfo.processInfo.environment["OPENROUTER_MODEL"] ?? "anthropic/claude-sonnet-4.5"
    @Published var apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? Keychain.load() ?? ""
    @Published var arrangement: Arrangement?
    @Published var isGenerating = false
    @Published var status = "준비됨. MIDI 출력: 가상 소스 \"KeyScore\""

    // 청취
    @Published var chordQualityIndex = 0
    @Published var progressionIndex = 0

    // 재생
    @Published var isPlaying = false
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var nowPlaying = ""

    private let player = MidiPlayer()
    private var song: Song?

    var scale: ScaleType { Theory.scales[scaleIndex] }
    var channels: ChannelMap { ChannelMap(melody: melodyChannel, chords: chordChannel, bass: bassChannel) }

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
    }

    func randomize() {
        root = Int.random(in: 0..<12)
        scaleIndex = Int.random(in: 0..<Theory.scales.count)
        bpm = Double(Int.random(in: 60...150))
        complexity = Int.random(in: 1...3)
    }

    func saveKey() { Keychain.save(apiKey) }

    // MARK: 재생

    func play(_ s: Song) {
        song = s
        duration = s.seconds
        nowPlaying = s.title
        isPlaying = true
        player.play(s, loop: loop)
    }

    func stop() { player.stop() }

    func replay() { if let song { play(song) } }

    func togglePlayback() {
        if isPlaying { stop() } else { replay() }
    }

    // MARK: 단축키

    static let shortcutHelp = "Space 재생/정지 · L 반복 · G 생성 · R Randomize · ←→ 템포(Shift 5) · ↑↓ Key · [ ] Scale · 1 2 3 복잡도 · , . 길이 · A 패턴 · S/C/P 스케일/코드/진행 듣기 · Tab 탭 전환"

    /// 처리했으면 true. 텍스트 입력 중에는 호출하지 않는다.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        guard flags.intersection([.command, .option, .control]).isEmpty else { return false }
        let shift = flags.contains(.shift)
        let step = shift ? 5.0 : 1.0
        if event.keyCode == 49 {  // space
            if !event.isARepeat { togglePlayback() }
            return true
        }
        switch event.keyCode {
        case 123: setBPM(bpm - step); return true  // ←
        case 124: setBPM(bpm + step); return true  // →
        case 126: shiftRoot(1); return true  // ↑
        case 125: shiftRoot(-1); return true  // ↓
        case 48:  // Tab
            let all: [Tab] = [.generate, .listen, .settings]
            let i = all.firstIndex(of: tab) ?? 0
            tab = all[(i + (shift ? all.count - 1 : 1)) % all.count]
            return true
        default: break
        }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if event.isARepeat && !"[],.".contains(key) { return "lgrscpa123".contains(key) }  // 반복 입력은 소비만
        switch key {
        case "l": loop.toggle(); status = loop ? "반복 켬" : "반복 끔"
        case "g": generate()
        case "r": randomize(); status = "Randomize: \(noteNames[root]) \(scale.name), \(Int(bpm)) BPM, 복잡도 \(complexity)"
        case "[": shiftScale(-1)
        case "]": shiftScale(1)
        case "1", "2", "3": complexity = Int(key)!; status = "복잡도 \(complexity)"
        case ",": shiftLength(-1)
        case ".": shiftLength(1)
        case "a":
            let all = ChordPattern.allCases
            let i = all.firstIndex(of: chordPattern)!
            chordPattern = all[(i + 1) % all.count]
            status = "코드 패턴: \(chordPattern.rawValue)"
        case "s": tab = .listen; listenScale()
        case "c": tab = .listen; listenChord()
        case "p": tab = .listen; listenProgression()
        default: return false
        }
        return true
    }

    private func setBPM(_ v: Double) {
        bpm = min(200, max(40, v))
        status = "Tempo \(Int(bpm)) BPM"
    }

    private func shiftRoot(_ d: Int) {
        root = (root + d + 12) % 12
        status = "Key \(noteNames[root])"
    }

    private func shiftScale(_ d: Int) {
        let n = Theory.scales.count
        scaleIndex = (scaleIndex + d + n) % n
        status = "Scale \(scale.name)"
    }

    private func shiftLength(_ d: Int) {
        let i = Self.lengths.firstIndex(of: minutes) ?? 1
        minutes = Self.lengths[min(Self.lengths.count - 1, max(0, i + d))]
        status = "길이 \(Int(minutes))분"
    }

    // MARK: 생성

    func generate() {
        guard !isGenerating else { return }
        saveKey()
        isGenerating = true
        status = "OpenRouter(\(model))에서 생성 중…"
        let req = GenerateRequest(root: root, scale: scale, bpm: bpm, complexity: complexity, minutes: minutes, mood: mood)
        let client = OpenRouterClient(apiKey: apiKey, model: model)
        Task {
            do {
                let arr = try await Generator.generate(req, client: client)
                arrangement = arr
                let s = buildSong()!
                status = "\"\(arr.title)\" 생성 완료 — \(Int(s.seconds / 60))분 \(Int(s.seconds) % 60)초, 노트 \(s.events.count)개"
                play(s)
            } catch {
                status = "실패: \(error.localizedDescription)"
            }
            isGenerating = false
        }
    }

    /// 현재 템포/길이/채널/패턴으로 arrangement 를 다시 전개.
    func buildSong() -> Song? {
        guard let arrangement else { return nil }
        let opts = ArrangeOptions(bpm: bpm, minutes: minutes, channels: channels, chordPattern: chordPattern)
        return Arranger.build(arrangement, options: opts)
    }

    func rebuildAndPlay() {
        if let s = buildSong() { play(s) }
    }

    // MARK: 청취

    func listenScale() {
        play(Preview.scale(root: root, type: scale, channel: melodyChannel))
    }

    func listenChord() {
        play(Preview.chord(root: root, quality: Theory.chordQualities[chordQualityIndex], pattern: chordPattern, channel: chordChannel))
    }

    func listenProgression() {
        play(Preview.progression(
            root: root, scale: scale, prog: Theory.progressions[progressionIndex],
            complexity: complexity, pattern: chordPattern, channels: channels))
    }
}
