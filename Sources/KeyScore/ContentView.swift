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
    @Bindable var m: AppModel
    @FocusState private var focus: Field?
    @State private var keyMonitor = MonitorBox()
    /// 헤더 아이콘. 본문이 다시 그려질 때마다 아이콘을 새로 렌더링하지 않도록 한 번만 만든다.
    private static let headerIcon = AppIcon.image(size: 96, flat: true)

    var body: some View {
        VStack(spacing: 0) {
            transportBar
            ProgressLine(m: m)
            ScrollView {
                VStack(spacing: 10) {
                    if m.showSettings { settingsCard.transition(.opacity.combined(with: .move(edge: .top))) }
                    keyScaleBpmCard
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
        .frame(minWidth: 860, minHeight: 620)
        .onAppear {
            installKeyMonitor()
            Task { releaseFocus() }  // 시작할 때 입력칸이 포커스를 잡으면 단축키가 꺼진다
        }
        .onDisappear { removeKeyMonitor() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            m.pedalHeld = false  // Tab 을 누른 채 다른 앱으로 가면 keyUp 이 오지 않는다
        }
    }

    // MARK: 트랜스포트 (Logic 스타일 상단 바)

    private var transportBar: some View {
        HStack(spacing: 10) {
            Image(nsImage: Self.headerIcon)
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
            TimeField(m: m)
            LCDDivider()
            LCDField(label: "TEMPO", value: "\(Int(m.bpm))", width: 52)
            LCDDivider()
            LCDField(label: "KEY", value: "\(noteNames[m.root]) \(m.scale.name)", width: 150)
            LCDDivider()
            LCDField(label: "NOW PLAYING", value: m.nowPlaying.isEmpty ? "–" : m.nowPlaying, width: nil)
            LCDDivider()
            StatusIcons(m: m)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Theme.lcd, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.6)))
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

    private var chordPatternCard: some View {
        Card(title: "PATTERNS", trailing: {
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
            HStack(spacing: 10) {
                TextField("분위기 (선택, 예: calm night jazz)", text: $m.mood)
                    .textFieldStyle(.roundedBorder).controlSize(.small)
                    .focused($focus, equals: .mood)
                OptionLabel("FORM")
                DarkMenu(items: FormPreset.allCases.map { ($0, $0.rawValue) }, selection: $m.formPreset)
                    .frame(width: 170)
                    .help(m.formPreset.summary + " (곡 생성 시 반영)")
            }
            // 두 파트를 2단으로. 두 열은 같은 폭이고 높이도 맞춘다.
            HStack(alignment: .top, spacing: 12) {
                secondPartSection
                Divider().overlay(Theme.stroke)
                rhythmSection
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 곡 정보 LCD 오른쪽 끝의 생성 버튼. 생성 중에도 폭이 같고, 다시 전개 버튼은 곡이 없으면 비활성으로 자리를 지킨다.
    private var generateButtons: some View {
        HStack(spacing: 6) {
            Button { m.exportMIDI() } label: { Image(systemName: "square.and.arrow.down") }
                .controlSize(.small).focusable(false)
                .disabled(m.arrangedSong == nil || m.isGenerating)
                .help("MIDI 파일로 내보내기 (⌘E)")
            Button { m.rebuildAndPlay() } label: { Image(systemName: "arrow.clockwise") }
                .controlSize(.small).focusable(false)
                .disabled(m.arrangement == nil || m.isGenerating)
                .help("현재 설정(템포·길이·채널·패턴)으로 다시 전개")
            Button { m.isGenerating ? m.cancelGenerate() : m.generate() } label: {
                HStack(spacing: 4) {
                    if m.isGenerating {
                        ProgressView().controlSize(.mini)
                        Text("취소")
                    } else {
                        Image(systemName: "wand.and.stars")
                        Text("곡 생성")
                    }
                }
                .frame(width: 72)
            }
            .buttonStyle(.borderedProminent).focusable(false)
            .help(m.isGenerating ? "생성 중 — 눌러서 취소" : "곡 생성 (⌘G)")
            KeyCap("⌘G", .play)
        }
    }

    /// 두 번째 파트(리프)와 채널.
    private var secondPartSection: some View {
        partSection(title: "SECOND PART", key: "R", note: "리프는 곡 생성 시 LLM 이 쓰며, 멜로디 밑에 깔리지 않습니다") {
            DarkMenu(items: SecondPart.allCases.map { ($0, $0.rawValue) }, selection: $m.secondPart)
        } channel: {
            ChannelStepper(title: "CH", channel: $m.secondChannel)
        } summary: {
            m.secondPart.summary
        }
    }

    /// 리듬(드럼) 패턴과 채널. General MIDI 드럼 노트를 보낸다.
    private var rhythmSection: some View {
        partSection(title: "RHYTHM", key: "D", note: "GM 드럼 맵 (보통 ch 10, 8채널 악기는 8) · 섹션별 강약과 필인은 생성 시 LLM 이 정함") {
            DarkMenu(items: DrumPattern.allCases.map { ($0, $0.rawValue) }, selection: $m.drumPattern)
        } channel: {
            ChannelStepper(title: "CH", channel: $m.rhythmChannel)
        } summary: {
            m.drumPattern.summary
        }
    }

    /// 채널 하나를 쓰는 파트 열. 메뉴는 열 폭을 채우고 채널 폭은 고정, 설명은 한 줄로 잘라
    /// 패턴이나 채널을 바꿔도 레이아웃이 흔들리지 않게 한다.
    private func partSection<M: View, C: View>(title: String, key: String, note: String,
                                               @ViewBuilder menu: () -> M, @ViewBuilder channel: () -> C,
                                               summary: () -> String) -> some View {
        let text = summary()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Text(title).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                KeyCap(key, .setting)
                KeyCap("⇧" + key, .setting)
                Text("선택").font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                menu()
                channel().help("\(title) 채널 — 설정(⌘,)에서도 바꿀 수 있습니다")
            }
            Text(text)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
                .help(text)
            Text(note)
                .font(.caption2).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.tail)
                .help(note)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lengthSection: some View {
        let layout = m.layout
        let order = m.arrangement?.form.all.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } ?? []
        let pendingArrange = m.pendingArrange
        let pendingPrompt = m.pendingPrompt
        return VStack(alignment: .leading, spacing: 6) {
            // 곡 정보(SECTIONS · FORM · 타임라인)는 지금 들리는 곡 기준. 곡을 만든 뒤 바뀐 설정은 배지로 알린다.
            HStack(alignment: .center, spacing: 6) {
                Text("LENGTH · ARRANGEMENT").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                if !pendingArrange.isEmpty {
                    Button { m.rebuildAndPlay() } label: {
                        PendingBadge(text: "↻ 다시 전개 시 반영", tint: Theme.lcdText)
                    }
                    .buttonStyle(.plain).focusable(false)
                    .help("바뀐 설정: \(pendingArrange.joined(separator: ", ")) — 눌러서 다시 전개")
                }
                if !pendingPrompt.isEmpty {
                    PendingBadge(text: "다시 생성 시 반영", tint: .orange)
                        .help("바뀐 설정: \(pendingPrompt.joined(separator: ", ")) — 프롬프트에 들어가는 값이라 곡 생성(⌘G)을 해야 반영됩니다")
                }
                Spacer()
                KeyCap(",", .setting)
                KeyCap(".", .setting)
                Text("길이").font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    LCDField(label: "LENGTH", value: AppModel.lengthLabel(m.minutes), width: 80)
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
                Spacer(minLength: 8)
                generateButtons
            }

            LengthRuler(minutes: $m.minutes, landmarks: AppModel.lengthLandmarks)
                .frame(height: 42)
            ArrangementLane(m: m, layout: layout, order: order)
                .frame(height: 34)
        }
    }

    private var listenTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            listenRow(title: "멜로디", detail: m.melodyStyle.summary, key: "G") {
                m.listen(.melody)
            } picker: {
                DarkMenu(items: MelodyStyle.allCases.map { ($0, $0.rawValue) }, selection: $m.melodyStyle, width: 150)
                KeyCap("M", .setting)
                KeyCap("⇧M", .setting)
                OptionChip("Vary", key: "⌥V", isOn: $m.listenOptions.varyMelody)
                    .help("멜로디 변주 (들을 때마다 다르게)")
            }
            listenRow(title: "코드", detail: nil, key: "C") {
                m.listen(.chord)
            } picker: {
                DarkMenu(items: Theory.chordQualities.indices.map { ($0, Theory.chordQualities[$0].symbol) },
                         selection: $m.chordQualityIndex, width: 110)
            }
            // 복잡도는 주로 패턴 듣기(코드 진행)의 소리를 바꾸므로 같은 줄 오른쪽에 둔다
            listenRow(title: "패턴", detail: nil, key: "F") {
                m.listen(.progression)
            } picker: {
                DarkMenu(items: Theory.progressions.indices.map { ($0, Theory.progressions[$0].name) },
                         selection: $m.progressionIndex, width: 150)
                PatternBadge(pattern: m.chordPattern) { m.cycleChordPattern(1) }.fixedSize()
            } trailing: {
                ToggleGroup(items: (1...Theory.maxComplexity).map { ($0, Theory.complexityNames[$0]) },
                            badges: (1...Theory.maxComplexity).map { "\($0)" }, badgeGroup: .setting, selection: $m.complexity)
                    .frame(width: 400)
                    .help("복잡도 (1–5)")
            }
            listenOptionsPanel
        }
    }

    private func listenRow<P: View, T: View>(title: String, detail: String?, key: String,
                                             action: @escaping () -> Void, @ViewBuilder picker: () -> P,
                                             @ViewBuilder trailing: () -> T = { EmptyView() }) -> some View {
        HStack(spacing: 8) {
            Button(action: action) { Label("\(title) 듣기", systemImage: "play.fill").frame(width: 84, alignment: .leading) }
                .controlSize(.small)
            KeyCap(key, .listen)
            picker()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail) }
            Spacer(minLength: 8)
            trailing()
        }
    }

    /// kornflake 의 Audition 옵션을 차용: 순차/동시, 내림차순, 오르내리기, 2옥타브, 코드 확장, 진행 간격, 음 길이, 레가토, 옥타브.
    /// 옵션마다 적용되는 듣기가 달라 적용 대상별로 묶는다 (Preview 참고). 스케일 듣기는 옥타브만 따른다.
    private var listenOptionsPanel: some View {
        let together = m.listenOptions.together
        return VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.stroke)
            // 코드 듣기 전용: 구성음을 늘어놓는 방식. 스케일은 오름차순 순차로 고정이라 받지 않는다
            optionSection(title: "CHORD", keys: ["C"])
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
            HStack(spacing: 6) {
                OptionChip("Legato", key: "⌥G", isOn: $m.listenOptions.legato).opacity(together ? 0.35 : 1)
                Text("Descending · Up & down · 2 Octaves · Rate · Legato 는 Sequential 에만 적용됩니다.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Divider().overlay(Theme.stroke)
            HStack(alignment: .top, spacing: 24) {
                // 코드 · 패턴 듣기: 코드 구성음을 위아래로 늘린다
                VStack(alignment: .leading, spacing: 8) {
                    optionSection(title: "CHORD · PATTERN", keys: ["C", "F"])
                    HStack(spacing: 18) {
                        MiniStepper(title: "EXTEND ▲", value: m.listenOptions.extendUp, range: 0...ListenOptions.maxExtend) { m.shiftExtendUp($0) }
                        MiniStepper(title: "EXTEND ▼", value: m.listenOptions.extendDown, range: 0...ListenOptions.maxExtend) { m.shiftExtendDown($0) }
                    }
                }
                Divider().overlay(Theme.stroke)
                // 모든 듣기에 적용
                VStack(alignment: .leading, spacing: 8) {
                    optionSection(title: "ALL", keys: [])
                    HStack(spacing: 12) {
                        MiniStepper(title: "OCTAVE", value: m.listenOptions.octave, range: -2...2) { m.shiftOctave($0) }
                        OptionChip("Pedal", key: "Tab · ⌥P", isOn: $m.pedalLatched)
                        OptionChip("Auto replay", key: "⌥A", isOn: $m.autoReplay)
                    }
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 청취 옵션 묶음 제목과 적용되는 듣기 단축키
    private func optionSection(title: String, keys: [String]) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
            ForEach(keys, id: \.self) { KeyCap($0, .listen) }
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

                VStack(alignment: .leading, spacing: 6) {
                    OptionLabel("MIDI CHANNELS")
                    HStack(spacing: 18) {
                        ChannelStepper(title: "MELODY", channel: $m.melodyChannel)
                        ChannelStepper(title: "CHORD", channel: $m.chordChannel)
                        ChannelStepper(title: "BASS", channel: $m.bassChannel)
                        ChannelStepper(title: "2ND", channel: $m.secondChannel)
                        ChannelStepper(title: "RHYTHM", channel: $m.rhythmChannel)
                        Spacer(minLength: 0)
                    }
                    Text("가상악기/외장악기의 MIDI 입력 소스에서 \"KeyScore\" 를 선택하고, 멀티팀버(Multi) 모드에서 채널별로 음색을 지정하세요. 리듬 채널에는 General MIDI 드럼 맵을 쓰는 드럼 음색을 지정합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    OptionLabel("MIDI CLOCK · 템포 동기화")
                    OptionChip("Send Clock · Start / Stop", key: "", isOn: $m.sendClock)
                    Text("켜면 재생을 시작할 때 Start, 재생하는 동안 4분음표당 24 펄스의 Clock, 멈출 때 Stop 을 \"KeyScore\" 로 보냅니다. 가상악기나 DAW 에서 외부 MIDI Clock 동기화를 켜면 아르페지에이터 · LFO · 딜레이가 앱 템포를 따라옵니다. 반복 재생은 처음으로 돌아갈 때마다 Start 를 다시 보냅니다.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("KeyScore 버전 \(AppInfo.versionString)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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
            // 로컬 이벤트 모니터는 항상 메인 스레드에서 불린다
            let handled = MainActor.assumeIsolated {
                if event.type == .keyUp { return m.handleKeyUp(event) }
                guard !(event.window?.firstResponder is NSText) else { return false }
                return m.handleKey(event)
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let token = keyMonitor.value { NSEvent.removeMonitor(token) }
        keyMonitor.value = nil
    }
}

// MARK: - 컴포넌트

// 재생 중 초당 20회 바뀌는 position 과 Note On 마다 깜빡이는 midiActive 는 아래의 작은 뷰에서만 읽는다.
// @Observable 은 body 를 평가한 뷰 단위로 의존성을 기록하므로, ContentView.body 안의 computed property 에서
// 읽으면 1000줄짜리 본문 전체가 초당 20회 다시 평가된다.

/// 상단 디스플레이의 TIME 칸 (재생 위치 / 길이)
private struct TimeField: View {
    let m: AppModel

    var body: some View {
        LCDField(label: "TIME", value: m.duration > 0 ? "\(Self.fmt(m.position)) / \(Self.fmt(m.duration))" : "–:–", width: 104)
    }

    private static func fmt(_ s: Double) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}

/// 트랜스포트 아래의 2px 진행선
private struct ProgressLine: View {
    let m: AppModel

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.black.opacity(0.4))
                Rectangle().fill(accent)
                    .frame(width: g.size.width * (m.duration > 0 ? min(m.position / m.duration, 1) : 0))
            }
        }
        .frame(height: 2)
    }
}

/// 상시 상태(MIDI 출력, 페달, 자동 재생, 생성/API 키)를 아이콘으로 보여준다. 마우스를 올리면 설명이 나온다.
private struct StatusIcons: View {
    let m: AppModel

    var body: some View {
        let failed = m.status.hasPrefix("실패")
        HStack(spacing: 10) {
            StatusIcon(symbol: "cable.connector", lit: true, flash: m.midiActive, tint: Theme.play,
                       help: "MIDI 출력 준비됨 — 가상 소스 \"KeyScore\" (노트가 나갈 때 깜빡임)")
            StatusIcon(symbol: "arrow.down.to.line", lit: m.pedalActive, tint: .orange,
                       help: m.pedalActive ? "서스테인 페달 ON" : "서스테인 페달 OFF — Tab 을 누르는 동안, 또는 ⌥P 로 고정")
            StatusIcon(symbol: "metronome", lit: m.sendClock, tint: Theme.play,
                       help: m.sendClock ? "MIDI Clock 송신 ON — 수신 측이 앱 템포를 따라옴 (설정 ⌘,)" : "MIDI Clock 송신 OFF — 설정(⌘,) 또는 재생 메뉴에서 켭니다")
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
}

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

/// 곡 길이 눈금자: 1분 단위 눈금, 30초 단위 작은 눈금, 대표 길이(landmarks)는 큰 눈금과 숫자. 클릭/드래그하면 30초 단위로 스냅.
private struct LengthRuler: View {
    @Binding var minutes: Double
    let landmarks: [Double]
    private let maxMinutes = AppModel.lengthRange.upperBound
    private let inset: CGFloat = 14

    var body: some View {
        GeometryReader { g in
            ruler
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let w = max(1, g.size.width - inset * 2)
                    let target = Double((v.location.x - inset) / w) * maxMinutes
                    minutes = AppModel.snapLength(target)
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

            let halves = Int(maxMinutes / AppModel.lengthStep)
            for h in 0...halves {
                let m = Double(h) * AppModel.lengthStep
                let isWhole = h % 2 == 0
                let isLandmark = landmarks.contains(m)
                var tick = Path()
                tick.move(to: CGPoint(x: x(m), y: trackY + 6))
                tick.addLine(to: CGPoint(x: x(m), y: trackY + (isLandmark ? 13 : isWhole ? 9 : 7)))
                ctx.stroke(tick, with: .color(.white.opacity(isLandmark ? 0.45 : isWhole ? 0.18 : 0.1)), lineWidth: 1)
            }
            for m in landmarks {
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
/// position 은 이 뷰의 body 에서 읽어 플레이헤드가 움직여도 이 뷰만 다시 그린다.
private struct ArrangementLane: View {
    let m: AppModel
    let layout: [(name: String, bars: Int)]
    let order: [String]

    private var progress: Double? {
        m.isPlaying && m.playingArrangement && m.duration > 0 ? min(m.position / m.duration, 1) : nil
    }

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
            Item(["1–5"], "복잡도"), Item([", ."], "곡 길이"), Item(["A", "⇧A"], "패턴"), Item(["M", "⇧M"], "멜로디 패턴"), Item(["R", "⇧R"], "두 번째 파트"), Item(["D", "⇧D"], "리듬 패턴"),
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
            if !key.isEmpty {
                Text(key).font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(isOn ? Color.white.opacity(0.65) : Color.secondary.opacity(0.55))
            }
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
                .frame(width: 22)
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

/// MIDI 채널(1~16) 선택. 숫자 폭이 고정되어 9 → 10 으로 바뀌어도 옆 요소가 밀리지 않는다.
private struct ChannelStepper: View {
    let title: String
    @Binding var channel: Int

    var body: some View {
        MiniStepper(title: title, value: channel, range: 1...16) { channel = min(16, max(1, channel + $0)) }
    }
}

/// 곡을 만든 뒤 설정이 바뀌었음을 알리는 작은 배지
private struct PendingBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text).font(.system(size: 9, weight: .bold)).lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// NSEvent 모니터 토큰 보관함. 뷰가 다시 만들어져도 같은 토큰을 들고 있어야 제거할 수 있다.
@MainActor
final class MonitorBox {
    var value: Any?
}
