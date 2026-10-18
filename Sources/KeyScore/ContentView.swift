import AppKit
import SwiftUI

private let accent = Color(red: 0.48, green: 0.32, blue: 0.96)

private enum Theme {
    static let window = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let panel = Color(red: 0.15, green: 0.15, blue: 0.18)
    static let stroke = Color.white.opacity(0.07)
    static let lcd = Color(red: 0.04, green: 0.06, blue: 0.07)
    static let lcdText = Color(red: 0.55, green: 0.95, blue: 0.85)
    static let play = Color(red: 0.25, green: 0.78, blue: 0.45)
}

private enum Field { case mood, apiKey, model }

struct ContentView: View {
    @ObservedObject var m: AppModel
    @FocusState private var focus: Field?
    @State private var keyMonitor = MonitorBox()

    var body: some View {
        VStack(spacing: 0) {
            transportBar
            progressLine
            ScrollView {
                VStack(spacing: 10) {
                    if m.showSettings { settingsCard.transition(.opacity.combined(with: .move(edge: .top))) }
                    keyScaleBpmCard
                    complexityCard
                    modeCard
                    chordPatternCard
                }
                .animation(.easeOut(duration: 0.15), value: m.showSettings)
                .padding(12)
                .contentShape(Rectangle())
                .onTapGesture { releaseFocus() }
            }
            footer
        }
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .focusEffectDisabled()
        .onChange(of: focus) { _, new in m.isTyping = new != nil }
        .tint(accent)
        .frame(minWidth: 800, minHeight: 620)
        .onAppear {
            installKeyMonitor()
            DispatchQueue.main.async { releaseFocus() }  // 시작할 때 입력칸이 포커스를 잡으면 단축키가 꺼진다
        }
        .onDisappear { removeKeyMonitor() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            m.pedalHeld = false  // Tab 을 누른 채 다른 앱으로 가면 keyUp 이 오지 않는다
        }
    }

    // MARK: 트랜스포트 (Logic 스타일 상단 바)

    private var transportBar: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIcon.image(size: 96, flat: true))
                .resizable().frame(width: 30, height: 30)
            HStack(spacing: 4) {
                ToolButton(symbol: "stop.fill", active: false, tint: accent) { m.stop() }
                ToolButton(symbol: "play.fill", active: m.isPlaying, tint: Theme.play) { m.togglePlayback() }
                    .opacity(m.nowPlaying.isEmpty && !m.isPlaying ? 0.4 : 1)
                ToolButton(symbol: "repeat", active: m.loop, tint: .orange) { m.toggleLoop() }
            }
            lcd
            Button { m.randomize() } label: { Label("Randomize", systemImage: "dice") }
                .controlSize(.small).focusable(false)
                .help("Randomize (⌘R)")
            ToolButton(symbol: "gearshape.fill", active: m.showSettings, tint: accent) { m.toggleSettings() }
                .help("설정 (⌘,)")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.panel)
    }

    private var lcd: some View {
        HStack(spacing: 0) {
            LCDField(label: "TIME", value: m.duration > 0 ? "\(fmt(m.position)) / \(fmt(m.duration))" : "–:–", width: 104)
            LCDDivider()
            LCDField(label: "TEMPO", value: "\(Int(m.bpm))", width: 52)
            LCDDivider()
            LCDField(label: "KEY", value: "\(noteNames[m.root]) \(m.scale.name)", width: 150)
            LCDDivider()
            LCDField(label: "NOW PLAYING", value: m.nowPlaying.isEmpty ? "–" : m.nowPlaying, width: nil)
            LCDDivider()
            statusIcons
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Theme.lcd, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.6)))
    }

    /// 상시 상태(MIDI 출력, 페달, 자동 재생, 생성/API 키)를 아이콘으로 보여준다. 마우스를 올리면 설명이 나온다.
    private var statusIcons: some View {
        let failed = m.status.hasPrefix("실패")
        return HStack(spacing: 10) {
            StatusIcon(symbol: "cable.connector", lit: true, flash: m.midiActive, tint: Theme.play,
                       help: "MIDI 출력 준비됨 — 가상 소스 \"KeyScore\" (노트가 나갈 때 깜빡임)")
            StatusIcon(symbol: "arrow.down.to.line", lit: m.pedalActive, tint: .orange,
                       help: m.pedalActive ? "서스테인 페달 ON" : "서스테인 페달 OFF — Tab 을 누르는 동안, 또는 ⌥P 로 고정")
            StatusIcon(symbol: "arrow.triangle.2.circlepath", lit: m.autoReplay, tint: Theme.lcdText,
                       help: m.autoReplay ? "자동 재생 ON (⌥A) — 청취 중 값을 바꾸면 다시 재생" : "자동 재생 OFF (⌥A)")
            if m.isGenerating {
                ProgressView().controlSize(.mini).frame(width: 16, height: 16).help("OpenRouter 에서 생성 중…")
            } else if failed {
                StatusIcon(symbol: "xmark.octagon.fill", lit: true, flash: false, tint: .red, help: m.status)
            } else if !m.hasAPIKey {
                StatusIcon(symbol: "key.slash", lit: true, flash: false, tint: .orange,
                           help: "OpenRouter API key 가 없습니다 — 설정(⌘,)에서 입력하세요")
            } else {
                StatusIcon(symbol: "key.fill", lit: true, flash: false, tint: Theme.lcdText.opacity(0.7),
                           help: "OpenRouter API key 설정됨 — 모델: \(m.model)")
            }
        }
        .padding(.horizontal, 10)
    }

    private var progressLine: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.black.opacity(0.4))
                Rectangle().fill(accent)
                    .frame(width: g.size.width * (m.duration > 0 ? min(m.position / m.duration, 1) : 0))
            }
        }
        .frame(height: 2)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 왼쪽: 패널 라벨(닫혀 있으면 눌러서 열기), 오른쪽: 일시적인 메시지/오류, 맨 끝: 닫기
            // 패널이 닫혀 있어도 이 줄은 남겨 메시지를 보여 준다. 높이는 고정해 레이아웃이 흔들리지 않게 한다.
            HStack(spacing: 6) {
                Button { m.toggleShortcuts() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "keyboard").font(.system(size: 10, weight: .semibold))
                        Text("SHORTCUTS").font(.system(size: 10, weight: .bold)).tracking(0.8)
                        if !m.showShortcuts { Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold)) }
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(m.showShortcuts
                      ? "메뉴바의 재생 / 청취 / 곡 설정 메뉴에도 같은 단축키가 표시됩니다. Help ▸ 단축키 안내 (⌘/)"
                      : "단축키 패널 열기 (Help ▸ 단축키 안내, ⌘/)")
                Spacer(minLength: 12)
                Text(m.status.isEmpty ? " " : m.status)
                    .font(.caption).lineLimit(1)
                    .foregroundStyle(m.status.hasPrefix("실패") ? Color.red : Color.secondary)
                if m.showShortcuts {
                    Button { m.toggleShortcuts() } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 18)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("닫기 — Help ▸ 단축키 안내 (⌘/)에서 다시 열 수 있습니다")
                }
            }
            if m.showShortcuts {
                ShortcutLegend().transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: m.showShortcuts)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.panel)
    }

    // MARK: 카드

    private var keyScaleBpmCard: some View {
        Card(title: "KEY · SCALE · BPM") {
            HStack(alignment: .top, spacing: 14) {
                MiniKeyboard(root: $m.root)
                    .frame(width: 270, height: 76)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        DarkMenu(items: Theory.scales.indices.map { ($0, Theory.scales[$0].name) }, selection: $m.scaleIndex)
                        Button { m.listen(.scale) } label: { Label("스케일 듣기", systemImage: "play.fill") }
                            .controlSize(.small).focusable(false)
                        KeyCap("S", .listen)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "metronome").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { m.bpm }, set: { m.bpm = $0.rounded() }), in: 40...200)
                            .controlSize(.small).focusable(false)
                        Text("\(Int(m.bpm))").font(.callout.monospacedDigit().weight(.medium))
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var complexityCard: some View {
        Card(title: "복잡도 · 멜로디 패턴") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ToggleGroup(items: (1...Theory.maxComplexity).map { ($0, Theory.complexityNames[$0]) },
                                badges: (1...Theory.maxComplexity).map { "\($0)" }, badgeGroup: .setting, selection: $m.complexity)
                        .frame(width: 420)
                    DarkMenu(items: MelodyStyle.allCases.map { ($0, $0.rawValue) }, selection: $m.melodyStyle)
                    Button { m.listen(.melody) } label: { Image(systemName: "play.fill") }
                        .controlSize(.small).focusable(false)
                    KeyCap("G", .listen)
                }
                Text(m.melodyStyle.summary).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var chordPatternCard: some View {
        Card(title: "코드 패턴", trailing: {
            // 패턴 듣기는 청취 탭의 "패턴 듣기" 줄(F)이 담당한다. 여기에는 단축키 정보만 둔다.
            HStack(spacing: 6) {
                KeyCap("F", .listen)
                Text("패턴 듣기").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.38))
                Text("·").foregroundStyle(Color.white.opacity(0.2))
                KeyCap("A", .setting)
                KeyCap("⇧A", .setting)
                Text("패턴 선택").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.38))
            }
        }) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 4), spacing: 6) {
                ForEach(ChordPattern.allCases) { pattern in
                    PatternTile(title: pattern.rawValue, summary: pattern.summary, selected: m.chordPattern == pattern)
                        .onTapGesture { m.chordPattern = pattern }
                }
            }
        }
    }

    private var modeCard: some View {
        Card(title: nil) {
            VStack(alignment: .leading, spacing: 10) {
                ToggleGroup(items: [
                    (AppModel.Tab.generate, "곡 생성"), (.listen, "스케일/코드 청취"),
                ], badges: ["⌘1", "⌘2"], badgeGroup: .view, selection: $m.tab)
                switch m.tab {
                case .generate: generateTab
                case .listen: listenTab
                }
            }
        }
    }

    private var generateTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            lengthSection
            TextField("분위기 (선택, 예: calm night jazz)", text: $m.mood)
                .textFieldStyle(.roundedBorder).controlSize(.small)
                .focused($focus, equals: .mood)
            HStack {
                Button { m.generate() } label: {
                    if m.isGenerating {
                        HStack { ProgressView().controlSize(.small); Text("생성 중…") }
                    } else {
                        Label("곡 생성", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(m.isGenerating)
                KeyCap("⌘G", .play)
                if m.arrangement != nil {
                    Button("현재 설정으로 다시 전개") { m.rebuildAndPlay() }
                }
            }
        }
    }

    private var lengthSection: some View {
        let layout = m.layout
        let order = m.arrangement?.form.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } ?? []
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text("LENGTH · ARRANGEMENT").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                Spacer()
                KeyCap(",", .setting)
                KeyCap(".", .setting)
                Text("길이").font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 0) {
                LCDField(label: "LENGTH", value: String(format: "%d:00", Int(m.minutes)), width: 80)
                LCDDivider()
                LCDField(label: "BARS", value: "\(m.targetBars)", width: 64)
                LCDDivider()
                LCDField(label: "SECTIONS", value: layout.isEmpty ? "–" : "\(layout.count)", width: 84)
                LCDDivider()
                LCDField(label: "FORM", value: order.isEmpty ? "–" : order.joined(separator: " "), width: 220)
            }
            .padding(.vertical, 4)
            .background(Theme.lcd, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.6)))
            .frame(maxWidth: .infinity, alignment: .leading)

            LengthRuler(minutes: $m.minutes, stops: AppModel.lengths)
                .frame(height: 42)
            ArrangementLane(
                layout: layout, order: order,
                progress: m.isPlaying && m.playingArrangement && m.duration > 0 ? min(m.position / m.duration, 1) : nil)
                .frame(height: 34)
        }
    }

    private var listenTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            listenRow(title: "코드", detail: nil, key: "C") {
                m.listen(.chord)
            } picker: {
                DarkMenu(items: Theory.chordQualities.indices.map { ($0, Theory.chordQualities[$0].symbol) },
                         selection: $m.chordQualityIndex, width: 110)
            }
            listenRow(title: "패턴", detail: nil, key: "F") {
                m.listen(.progression)
            } picker: {
                DarkMenu(items: Theory.progressions.indices.map { ($0, Theory.progressions[$0].name) },
                         selection: $m.progressionIndex, width: 150)
                PatternBadge(pattern: m.chordPattern) { m.cycleChordPattern(1) }
            }
            listenOptionsPanel
        }
    }

    private func listenRow<P: View>(title: String, detail: String?, key: String,
                                    action: @escaping () -> Void, @ViewBuilder picker: () -> P) -> some View {
        HStack(spacing: 8) {
            Button(action: action) { Label("\(title) 듣기", systemImage: "play.fill").frame(width: 84, alignment: .leading) }
                .controlSize(.small)
            KeyCap(key, .listen)
            picker()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }
    }

    /// kornflake 의 Audition 옵션을 차용: 순차/동시, 내림차순, 오르내리기, 2옥타브, 코드 확장, 진행 간격, 음 길이, 레가토, 옥타브
    private var listenOptionsPanel: some View {
        let together = m.listenOptions.together
        return VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.stroke)
            OptionLabel("MODE")
            HStack(spacing: 6) {
                ToggleGroup(items: [(false, "Sequential"), (true, "Together")], badges: ["", "⌘3"], badgeGroup: .listen,
                            selection: $m.listenOptions.together)
                    .frame(width: 230)
                Group {
                    OptionChip("Descending", key: "⌘D", isOn: $m.listenOptions.descending)
                    OptionChip("Up & down", key: "⇧⌘D", isOn: $m.listenOptions.upDown)
                    OptionChip("2 Octaves", key: "⌥⌘D", isOn: $m.listenOptions.twoOctaves)
                }
                .opacity(together ? 0.35 : 1)
            }
            Text("Descending · Up & down · 2 Octaves 는 스케일/코드 순차(Sequential) 재생에 적용됩니다. Together, 진행, 멜로디에는 적용되지 않습니다.")
                .font(.caption2).foregroundStyle(.tertiary)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    OptionLabel("RATE")
                    ToggleGroup(items: ListenOptions.rates.map { ($0, ListenOptions.label(beats: $0)) }, selection: $m.listenOptions.rate)
                        .frame(width: 200)
                }
                .opacity(together ? 0.35 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    OptionLabel("NOTE LENGTH")
                    ToggleGroup(items: ListenOptions.lengths.map { ($0, ListenOptions.label(beats: $0)) }, selection: $m.listenOptions.noteLength)
                }
            }
            HStack(spacing: 18) {
                MiniStepper(title: "EXTEND ▲", value: m.listenOptions.extendUp, range: 0...ListenOptions.maxExtend) { m.shiftExtendUp($0) }
                MiniStepper(title: "EXTEND ▼", value: m.listenOptions.extendDown, range: 0...ListenOptions.maxExtend) { m.shiftExtendDown($0) }
                MiniStepper(title: "OCTAVE", value: m.listenOptions.octave, range: -2...2) { m.shiftOctave($0) }
                Spacer()
            }
            HStack(spacing: 6) {
                OptionChip("Legato", key: "⌥G", isOn: $m.listenOptions.legato).opacity(together ? 0.35 : 1)
                OptionChip("Vary melody", key: "⌥V", isOn: $m.listenOptions.varyMelody)
                OptionChip("Pedal", key: "Tab · ⌥P", isOn: $m.pedalLatched)
                OptionChip("Auto replay", key: "⌥A", isOn: $m.autoReplay)
            }
        }
    }

    private var settingsCard: some View {
        Card(title: "SETTINGS · ⌘,") {
            VStack(alignment: .leading, spacing: 10) {
                SecureField("OpenRouter API Key", text: $m.apiKey)
                    .textFieldStyle(.roundedBorder).controlSize(.small)
                    .focused($focus, equals: .apiKey)
                    .onSubmit { m.saveKey() }

                VStack(alignment: .leading, spacing: 6) {
                    OptionLabel("MODEL · 1M 토큰당 입력 / 출력 USD")
                    DarkMenu(items: ModelCatalog.presets.map { ($0.id, $0.label) }, selection: $m.model,
                             placeholder: "직접 입력한 모델")
                    TextField("Model ID (목록에 없으면 직접 입력)", text: $m.model)
                        .textFieldStyle(.roundedBorder).controlSize(.small)
                        .focused($focus, equals: .model)
                    Text(ModelCatalog.preset(for: m.model)?.note ?? "목록에 없는 모델입니다. JSON 출력을 지원하는 모델인지 확인하세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack(spacing: 18) {
                    Stepper("Melody ch \(m.melodyChannel)", value: $m.melodyChannel, in: 1...16)
                    Stepper("Chord ch \(m.chordChannel)", value: $m.chordChannel, in: 1...16)
                    Stepper("Bass ch \(m.bassChannel)", value: $m.bassChannel, in: 1...16)
                }
                .controlSize(.small)
                Text("Omnisphere: Settings → MIDI → 입력 소스에서 \"KeyScore\" 를 선택하고, Multi 모드에서 채널별로 패치를 지정하세요.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("KeyScore 버전 \(AppInfo.versionString)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func fmt(_ s: Double) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }

    // MARK: 단축키

    private func releaseFocus() {
        focus = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// 단축키 처리. 텍스트 입력 중에는 일반 입력으로 둔다.
    private func installKeyMonitor() {
        guard keyMonitor.value == nil else { return }
        keyMonitor.value = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [m] event in
            if event.type == .keyUp { return m.handleKeyUp(event) ? nil : event }
            guard !(event.window?.firstResponder is NSText) else { return event }
            return m.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let token = keyMonitor.value { NSEvent.removeMonitor(token) }
        keyMonitor.value = nil
    }
}

// MARK: - 컴포넌트

private struct Card<Content: View, Trailing: View>: View {
    let title: String?
    let trailing: Trailing
    let content: Content

    init(title: String?, @ViewBuilder content: () -> Content) where Trailing == EmptyView {
        self.title = title
        self.trailing = EmptyView()
        self.content = content()
    }

    /// trailing: 제목 줄 오른쪽 끝에 놓일 보조 정보 (단축키 안내 등)
    init(title: String?, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || Trailing.self != EmptyView.self {
                HStack(alignment: .center) {
                    if let title {
                        Text(title).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    trailing
                }
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke))
    }
}

/// 토글 버튼 묶음 (라디오 대체)
private struct ToggleGroup<T: Hashable>: View {
    let items: [(T, String)]
    var badges: [String] = []
    var badgeGroup: KeyGroup = .setting
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let on = selection == item.0
                HStack(spacing: 6) {
                    Text(item.1).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if i < badges.count, !badges[i].isEmpty {
                        Text(badges[i]).font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(on ? Color.white : badgeGroup.color)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(badgeGroup.color.opacity(on ? 0.45 : 0.16), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                    .foregroundStyle(on ? Color.white : Color.secondary)
                    .background(on ? accent : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = item.0 }
            }
        }
    }
}

/// 다크 테마용 팝업 메뉴
private struct DarkMenu<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var width: CGFloat? = nil
    var placeholder = ""

    var body: some View {
        Menu {
            ForEach(items.indices, id: \.self) { i in
                Button(items[i].1) { selection = items[i].0 }
            }
        } label: {
            HStack(spacing: 4) {
                Text(items.first { $0.0 == selection }?.1 ?? placeholder)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: width ?? .infinity)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .focusable(false)
    }
}

/// 피아노 건반 모양의 Key 선택기
private struct MiniKeyboard: View {
    @Binding var root: Int
    private let whites = [0, 2, 4, 5, 7, 9, 11]
    private let blacks: [(pc: Int, slot: Int)] = [(1, 1), (3, 2), (6, 4), (8, 5), (10, 6)]

    var body: some View {
        GeometryReader { g in
            let ww = g.size.width / 7
            let bw = ww * 0.62
            let bh = g.size.height * 0.60
            ZStack(alignment: .topLeading) {
                ForEach(Array(whites.enumerated()), id: \.offset) { i, pc in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(root == pc ? accent : Color(white: 0.90))
                        .overlay(alignment: .bottom) {
                            Text(noteNames[pc]).font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(root == pc ? Color.white : Color(white: 0.35)).padding(.bottom, 4)
                        }
                        .frame(width: ww - 2, height: g.size.height)
                        .offset(x: CGFloat(i) * ww + 1)
                        .onTapGesture { root = pc }
                }
                ForEach(blacks, id: \.pc) { b in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(root == b.pc ? accent : Color(white: 0.07))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.18)))
                        .overlay(alignment: .bottom) {
                            Text(noteNames[b.pc]).font(.system(size: 8, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.75)).padding(.bottom, 3)
                        }
                        .frame(width: bw, height: bh)
                        .offset(x: CGFloat(b.slot) * ww - bw / 2)
                        .onTapGesture { root = b.pc }
                }
            }
        }
    }
}

/// 곡 길이 눈금자: 1분 단위 눈금, 선택 가능한 길이(stops)는 큰 눈금. 클릭/드래그하면 가장 가까운 길이로 스냅.
private struct LengthRuler: View {
    @Binding var minutes: Double
    let stops: [Double]
    private let maxMinutes = 12.0
    private let inset: CGFloat = 14

    var body: some View {
        GeometryReader { g in
            ruler
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let w = max(1, g.size.width - inset * 2)
                    let target = Double((v.location.x - inset) / w) * maxMinutes
                    if let nearest = stops.min(by: { abs($0 - target) < abs($1 - target) }) { minutes = nearest }
                })
        }
    }

    private var ruler: some View {
        Canvas { ctx, size in
            let w = size.width - inset * 2
            func x(_ m: Double) -> CGFloat { inset + w * CGFloat(m / maxMinutes) }
            let trackY: CGFloat = 12
            ctx.fill(Path(roundedRect: CGRect(x: inset, y: trackY - 2, width: w, height: 4), cornerRadius: 2),
                     with: .color(.white.opacity(0.08)))
            ctx.fill(Path(roundedRect: CGRect(x: inset, y: trackY - 2, width: x(minutes) - inset, height: 4), cornerRadius: 2),
                     with: .color(accent))

            for m in 0...Int(maxMinutes) {
                let isStop = stops.contains(Double(m))
                var tick = Path()
                tick.move(to: CGPoint(x: x(Double(m)), y: trackY + 6))
                tick.addLine(to: CGPoint(x: x(Double(m)), y: trackY + (isStop ? 13 : 9)))
                ctx.stroke(tick, with: .color(.white.opacity(isStop ? 0.45 : 0.18)), lineWidth: 1)
            }
            for m in stops {
                let on = m == minutes
                ctx.draw(
                    Text("\(Int(m))분").font(.system(size: 10, weight: on ? .bold : .regular))
                        .foregroundStyle(on ? Color.white : Color.secondary),
                    at: CGPoint(x: x(m), y: trackY + 15), anchor: .top)
            }
            let handle = CGRect(x: x(minutes) - 6, y: trackY - 8, width: 12, height: 16)
            ctx.fill(Path(roundedRect: handle, cornerRadius: 4), with: .color(.white))
            ctx.stroke(Path(roundedRect: handle, cornerRadius: 4), with: .color(accent), lineWidth: 2)
        }
    }
}

/// 섹션 배치 타임라인. 폭은 마디 수에 비례하고, 재생 중이면 플레이헤드가 움직인다.
private struct ArrangementLane: View {
    let layout: [(name: String, bars: Int)]
    let order: [String]
    let progress: Double?

    private static let palette: [Color] = [
        Color(red: 0.48, green: 0.32, blue: 0.96), Color(red: 0.18, green: 0.70, blue: 0.72),
        Color(red: 0.92, green: 0.35, blue: 0.62), Color(red: 0.95, green: 0.60, blue: 0.20),
        Color(red: 0.30, green: 0.55, blue: 0.95), Color(red: 0.40, green: 0.75, blue: 0.40),
    ]

    private func color(_ name: String) -> Color {
        Self.palette[(order.firstIndex(of: name) ?? 0) % Self.palette.count]
    }

    var body: some View {
        GeometryReader { g in
            let total = max(1, layout.reduce(0) { $0 + $1.bars })
            let gap: CGFloat = layout.count > 24 ? 1 : 2
            let usable = max(1, g.size.width - gap * CGFloat(max(0, layout.count - 1)))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.3))
                if layout.isEmpty {
                    Text("곡을 생성하면 섹션 구성이 여기에 표시됩니다")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: gap) {
                        ForEach(layout.indices, id: \.self) { i in
                            let sec = layout[i]
                            let w = usable * CGFloat(sec.bars) / CGFloat(total)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(color(sec.name).opacity(0.35))
                                RoundedRectangle(cornerRadius: 3).stroke(color(sec.name).opacity(0.9), lineWidth: 1)
                                if w > 14 {
                                    Text(w > 44 ? sec.name : String(sec.name.prefix(1)))
                                        .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                        .padding(.leading, 5)
                                }
                            }
                            .frame(width: w)
                        }
                    }
                    .padding(2)
                }
                if let p = progress {
                    Rectangle().fill(Color.white).frame(width: 2)
                        .offset(x: max(0, min(g.size.width - 2, g.size.width * p)))
                }
            }
        }
    }
}

private struct ToolButton: View {
    let symbol: String
    let active: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.secondary)
                .frame(width: 32, height: 26)
                .background(active ? tint : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

private struct LCDField: View {
    let label: String
    let value: String
    /// nil 이면 남는 폭을 모두 차지한다.
    let width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8, weight: .bold)).tracking(0.6).foregroundStyle(Theme.lcdText.opacity(0.5))
            Text(value).font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.lcdText).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(minWidth: width, maxWidth: width ?? .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

private struct LCDDivider: View {
    var body: some View {
        Rectangle().fill(Theme.lcdText.opacity(0.12)).frame(width: 1, height: 24)
    }
}

private struct PatternTile: View {
    let title: String
    let summary: String
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(summary).font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
        .background(selected ? accent.opacity(0.28) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? accent : Theme.stroke, lineWidth: selected ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// 단축키 그룹. 메뉴 이름(재생/곡 설정/청취/화면)과 같은 분류로 색을 나눈다.
private enum KeyGroup {
    case play, setting, listen, view

    var color: Color {
        switch self {
        case .play: return Color(red: 0.40, green: 0.85, blue: 0.55)
        case .setting: return Color(red: 0.68, green: 0.58, blue: 1.00)
        case .listen: return Color(red: 0.35, green: 0.82, blue: 0.88)
        case .view: return Color(red: 0.98, green: 0.68, blue: 0.32)
        }
    }
}

private struct KeyCap: View {
    let label: String
    let group: KeyGroup
    init(_ label: String, _ group: KeyGroup) {
        self.label = label
        self.group = group
    }

    var body: some View {
        Text(label).font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(group.color)
            .frame(minWidth: 14).padding(.horizontal, 4).padding(.vertical, 1.5)
            .background(group.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(group.color.opacity(0.55)))
    }
}

/// 하단 단축키 표: 그룹(재생 / 청취 / 곡 설정)별 같은 폭·같은 높이의 카드.
/// 라벨은 왼쪽, 키캡은 오른쪽 끝에 맞추고 행 높이를 통일해 어느 카드를 봐도 같은 리듬으로 읽히게 한다.
private struct ShortcutLegend: View {
    private struct Item {
        let keys: [String]
        let label: String
        init(_ keys: [String], _ label: String) {
            self.keys = keys
            self.label = label
        }
    }

    private struct Group {
        let group: KeyGroup
        let title: String
        let items: [Item]
        var note: String? = nil
    }

    private let rowHeight: CGFloat = 24

    private let groups: [Group] = [
        Group(group: .play, title: "재생", items: [
            Item(["Space"], "재생 / 정지"), Item(["⌥L"], "반복"), Item(["⌘G"], "곡 생성"), Item(["⌘R"], "Randomize"),
        ], note: "메뉴바의 재생 · 청취 · 곡 설정 메뉴에도 같은 단축키가 표시됩니다. 텍스트를 입력하는 동안에는 글자 키 단축키가 꺼집니다."),
        Group(group: .listen, title: "청취", items: [
            Item(["S"], "스케일 듣기"), Item(["C"], "코드 듣기"), Item(["F"], "패턴 듣기"), Item(["G"], "멜로디 듣기"),
            Item(["⇧S", "⇧C", "⇧F"], "다음 선택"), Item(["⌥⇧S", "⌥⇧C", "⌥⇧F"], "이전 선택"),
            Item(["Tab"], "페달 (누르는 동안)"),
        ]),
        Group(group: .setting, title: "곡 설정", items: [
            Item(["H L", "← →"], "템포"), Item(["⇧"], "템포 ±5 (누른 채)"), Item(["K J", "↑ ↓"], "Key"), Item(["[ ]"], "Scale"),
            Item(["1–5"], "복잡도"), Item([", ."], "곡 길이"), Item(["A", "⇧A"], "코드 패턴"), Item(["M", "⇧M"], "멜로디 패턴"),
        ]),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(groups.indices, id: \.self) { card(groups[$0]) }
        }
        .fixedSize(horizontal: false, vertical: true)  // 세 카드가 가장 긴 카드의 높이로 맞춰진다
    }

    private func card(_ g: Group) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(g.group.color).frame(width: 6, height: 6)
                Text(g.title).font(.system(size: 11, weight: .bold)).foregroundStyle(g.group.color)
                Spacer()
            }
            .frame(height: rowHeight)
            ForEach(g.items.indices, id: \.self) { i in
                VStack(spacing: 0) {
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                    HStack(spacing: 4) {
                        Text(g.items[i].label).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
                        Spacer(minLength: 8)
                        ForEach(g.items[i].keys, id: \.self) { KeyCap($0, g.group) }
                    }
                    .frame(height: rowHeight)
                }
            }
            if let note = g.note {
                Spacer(minLength: 8)
                Text(note).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.3))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.03))
        .overlay(alignment: .top) { Rectangle().fill(g.group.color.opacity(0.75)).frame(height: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke))
    }
}

/// 상단 디스플레이의 상태 아이콘. lit 이 꺼져 있으면 흐리게, flash 면 잠깐 밝게.
private struct StatusIcon: View {
    let symbol: String
    let lit: Bool
    var flash = false
    let tint: Color
    let help: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(flash ? Color.white : (lit ? tint : Color.white.opacity(0.18)))
            .shadow(color: lit ? tint.opacity(flash ? 0.9 : 0.35) : .clear, radius: flash ? 5 : 2)
            .frame(width: 16, height: 16)
            .help(help)
    }
}

/// 패턴 듣기(코드 진행 재생)에 쓰이는 코드 패턴 라벨. 클릭하면 다음 패턴 (A / ⇧A 와 같은 동작).
private struct PatternBadge: View {
    let pattern: ChordPattern
    let next: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform").font(.system(size: 9, weight: .bold))
            Text("PATTERN").font(.system(size: 8, weight: .bold)).tracking(0.6).opacity(0.6)
            Text(pattern.rawValue).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(KeyGroup.setting.color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(KeyGroup.setting.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(KeyGroup.setting.color.opacity(0.45)))
        .contentShape(Rectangle())
        .onTapGesture(perform: next)
        .help("\(pattern.summary)\n클릭하거나 A / ⇧A 로 바꿉니다")
    }
}

private struct OptionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
    }
}

/// 켜고 끄는 옵션 칩
private struct OptionChip: View {
    let title: String
    let key: String
    @Binding var isOn: Bool
    init(_ title: String, key: String, isOn: Binding<Bool>) {
        self.title = title
        self.key = key
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: 11, weight: .medium))
            Text(key).font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(isOn ? Color.white.opacity(0.65) : Color.secondary.opacity(0.55))
        }
        .foregroundStyle(isOn ? Color.white : Color.secondary)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(isOn ? KeyGroup.listen.color.opacity(0.38) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(isOn ? KeyGroup.listen.color.opacity(0.7) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

private struct MiniStepper: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let step: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            OptionLabel(title)
            stepButton("minus", enabled: value > range.lowerBound) { step(-1) }
            Text(value > 0 && range.lowerBound < 0 ? "+\(value)" : "\(value)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(minWidth: 22)
            stepButton("plus", enabled: value < range.upperBound) { step(1) }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            .frame(width: 20, height: 18)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            .opacity(enabled ? 1 : 0.3)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
    }
}

final class MonitorBox {
    var value: Any?
}
