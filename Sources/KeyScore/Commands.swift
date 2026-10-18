import AppKit
import SwiftUI

/// macOS 메뉴바. 항목마다 단축키를 표시해 메뉴만 봐도 조작법을 알 수 있게 한다.
///
/// - 평문 키(Space, H/J/K/L, S/C/F/G 등)는 AppModel.handleKey 의 키 모니터가 먼저 처리한다.
///   메뉴에는 vim 방식(H/J/K/L)만 표시하고, 화살표 키도 같은 동작을 한다.
///   텍스트 입력 중에는 평문 키 메뉴 항목을 비활성화해 입력을 가로채지 않는다.
/// - ⌘/⌥ 조합은 메뉴가 직접 처리한다.
struct KeyScoreCommands: Commands {
    @Bindable var m: AppModel

    var body: some Commands {
        // 창을 복제하면 플레이어가 둘이 되므로 New Window 는 제거
        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .appSettings) {
            Toggle("설정", isOn: Binding(get: { m.showSettings }, set: { _ in m.toggleSettings() }))
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("재생") {
            Button(m.isPlaying ? "정지" : "재생") { m.togglePlayback() }
                .shortcut(.space, typing: m.isTyping)
            Button("처음부터 다시 재생") { m.replay() }
                .disabled(m.nowPlaying.isEmpty)
            Toggle("반복 재생", isOn: Binding(get: { m.loop }, set: { _ in m.toggleLoop() }))
                .keyboardShortcut("l", modifiers: .option)
            Divider()
            Button("곡 생성 (OpenRouter)") { m.generate() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(m.isGenerating)
            Button("생성 취소") { m.cancelGenerate() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!m.isGenerating)
            Button("현재 설정으로 다시 전개") { m.rebuildAndPlay() }
                .disabled(m.arrangement == nil)
            Button("Randomize (Key · Scale · 템포 · 복잡도 · 멜로디 · 코드 패턴 · 진행)") { m.randomize() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Randomize + 청취 옵션 (Rate · 음 길이)") { m.randomize(includeListenOptions: true) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandMenu("청취") {
            Button("스케일 듣기") { m.listen(.scale) }.shortcut("s", typing: m.isTyping)
            Button("코드 듣기") { m.tab = .listen; m.listen(.chord) }.shortcut("c", typing: m.isTyping)
            Button("패턴 듣기 (코드 진행)") { m.tab = .listen; m.listen(.progression) }.shortcut("f", typing: m.isTyping)
            Button("멜로디 패턴 듣기") { m.listen(.melody) }.shortcut("g", typing: m.isTyping)
            Divider()
            Button("다음 스케일") { m.shiftScale(1) }.shortcut("s", .shift, typing: m.isTyping)
            Button("이전 스케일") { m.shiftScale(-1) }.keyboardShortcut("s", modifiers: [.option, .shift])
            Button("다음 코드 종류") { m.tab = .listen; m.shiftChordQuality(1) }.shortcut("c", .shift, typing: m.isTyping)
            Button("이전 코드 종류") { m.tab = .listen; m.shiftChordQuality(-1) }.keyboardShortcut("c", modifiers: [.option, .shift])
            Button("다음 코드 진행") { m.tab = .listen; m.shiftProgression(1) }.shortcut("f", .shift, typing: m.isTyping)
            Button("이전 코드 진행") { m.tab = .listen; m.shiftProgression(-1) }.keyboardShortcut("f", modifiers: [.option, .shift])
            Divider()
            Toggle("동시 재생 (Together)", isOn: $m.listenOptions.together)
                .keyboardShortcut("3", modifiers: .command)
            Toggle("내림차순", isOn: $m.listenOptions.descending)
                .keyboardShortcut("d", modifiers: .command)
            Toggle("오르내리기 (Up & down)", isOn: $m.listenOptions.upDown)
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Toggle("2옥타브", isOn: $m.listenOptions.twoOctaves)
                .keyboardShortcut("d", modifiers: [.command, .option])
            Toggle("레가토", isOn: $m.listenOptions.legato)
                .keyboardShortcut("g", modifiers: .option)
            Toggle("멜로디 변주 (들을 때마다 다르게)", isOn: $m.listenOptions.varyMelody)
                .keyboardShortcut("v", modifiers: .option)
            Divider()
            Button("코드 위 확장 늘리기") { m.shiftExtendUp(1) }.keyboardShortcut("u", modifiers: .command)
            Button("코드 위 확장 줄이기") { m.shiftExtendUp(-1) }.keyboardShortcut("u", modifiers: [.command, .shift])
            Button("코드 아래 확장 늘리기") { m.shiftExtendDown(1) }.keyboardShortcut("b", modifiers: .command)
            Button("코드 아래 확장 줄이기") { m.shiftExtendDown(-1) }.keyboardShortcut("b", modifiers: [.command, .shift])
            Button("옥타브 올리기") { m.shiftOctave(1) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("옥타브 내리기") { m.shiftOctave(-1) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("음 길이 길게") { m.shiftNoteLength(1) }.keyboardShortcut("=", modifiers: .command)
            Button("음 길이 짧게") { m.shiftNoteLength(-1) }.keyboardShortcut("-", modifiers: .command)
            Divider()
            Toggle("서스테인 페달 고정 (Tab: 누르는 동안 홀드)", isOn: $m.pedalLatched)
                .keyboardShortcut("p", modifiers: .option)
            Toggle("자동 재생 (옵션을 바꾸면 다시 재생)", isOn: $m.autoReplay)
                .keyboardShortcut("a", modifiers: .option)
        }

        CommandMenu("곡 설정") {
            Button("템포 −1") { m.adjustBPM(-1) }.shortcut("h", typing: m.isTyping)
            Button("템포 +1") { m.adjustBPM(1) }.shortcut("l", typing: m.isTyping)
            Button("템포 −5") { m.adjustBPM(-5) }.shortcut("h", .shift, typing: m.isTyping)
            Button("템포 +5") { m.adjustBPM(5) }.shortcut("l", .shift, typing: m.isTyping)
            Divider()
            Button("Key 반음 올리기") { m.shiftRoot(1) }.shortcut("k", typing: m.isTyping)
            Button("Key 반음 내리기") { m.shiftRoot(-1) }.shortcut("j", typing: m.isTyping)
            Button("다음 Scale") { m.shiftScale(1) }.shortcut("]", typing: m.isTyping)
            Button("이전 Scale") { m.shiftScale(-1) }.shortcut("[", typing: m.isTyping)
            Divider()
            ForEach(1...Theory.maxComplexity, id: \.self) { level in
                Toggle(Theory.complexityNames[level] + " (복잡도 \(level))",
                       isOn: Binding(get: { m.complexity == level }, set: { _ in m.setComplexity(level) }))
                    .shortcut(KeyEquivalent(Character("\(level)")), typing: m.isTyping)
            }
            Button("멜로디 패턴 다음") { m.cycleMelodyStyle(1) }.shortcut("m", typing: m.isTyping)
            Button("멜로디 패턴 이전") { m.cycleMelodyStyle(-1) }.shortcut("m", .shift, typing: m.isTyping)
            Button("코드 패턴 다음") { m.cycleChordPattern(1) }.shortcut("a", typing: m.isTyping)
            Button("코드 패턴 이전") { m.cycleChordPattern(-1) }.shortcut("a", .shift, typing: m.isTyping)
            Button("리듬 패턴 다음") { m.cycleDrumPattern(1) }.shortcut("d", typing: m.isTyping)
            Button("리듬 패턴 이전") { m.cycleDrumPattern(-1) }.shortcut("d", .shift, typing: m.isTyping)
            Button("두 번째 파트 다음") { m.cycleSecondPart(1) }.shortcut("r", typing: m.isTyping)
            Button("두 번째 파트 이전") { m.cycleSecondPart(-1) }.shortcut("r", .shift, typing: m.isTyping)
            Divider()
            Button("곡 길이 짧게") { m.shiftLength(-1) }.shortcut(",", typing: m.isTyping)
            Button("곡 길이 길게") { m.shiftLength(1) }.shortcut(".", typing: m.isTyping)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Toggle("곡 생성", isOn: Binding(get: { m.tab == .generate }, set: { _ in m.tab = .generate }))
                .keyboardShortcut("1", modifiers: .command)
            Toggle("스케일/코드 청취", isOn: Binding(get: { m.tab == .listen }, set: { _ in m.tab = .listen }))
                .keyboardShortcut("2", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Toggle("단축키 안내", isOn: Binding(get: { m.showShortcuts }, set: { _ in m.toggleShortcuts() }))
                .keyboardShortcut("/", modifiers: .command)
            Divider()
            Button("KeyScore 정보") { NSApp.orderFrontStandardAboutPanel(nil) }
            Text("버전 \(AppInfo.versionString)")
        }
    }
}

private extension View {
    /// 평문(또는 Shift 만 붙은) 단축키. 텍스트 입력 중에는 비활성화.
    func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers = [], typing: Bool) -> some View {
        keyboardShortcut(key, modifiers: modifiers).disabled(typing)
    }
}

enum AppInfo {
    /// 번들(Info.plist)의 버전. `swift run` 처럼 번들이 없으면 "dev".
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "dev" }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}
