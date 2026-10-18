import AppKit
import SwiftUI

private let accent = Color(red: 0.48, green: 0.32, blue: 0.96)

struct ContentView: View {
    @StateObject private var m = AppModel()
    @State private var keyMonitor = MonitorBox()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    soundCard
                    modeCard
                }
                .padding(16)
            }
            transport
        }
        .tint(accent)
        .frame(minWidth: 620, minHeight: 700)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: 구성 요소

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcon.image(size: 128))
                .resizable().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("KeyScore").font(.title2.weight(.semibold))
                Text(m.nowPlaying.isEmpty ? "MIDI → \"KeyScore\" 가상 소스" : "♪ \(m.nowPlaying)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { m.randomize() } label: { Label("Randomize", systemImage: "dice") }
                .controlSize(.large)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
    }

    private var soundCard: some View {
        Card(title: "사운드") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Key", selection: $m.root) {
                    ForEach(0..<12, id: \.self) { Text(noteNames[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Scale", selection: $m.scaleIndex) {
                    ForEach(Array(Theory.scales.enumerated()), id: \.offset) { Text($1.name).tag($0) }
                }
                HStack {
                    Label("\(Int(m.bpm)) BPM", systemImage: "metronome")
                        .monospacedDigit().frame(width: 110, alignment: .leading)
                    Slider(value: $m.bpm, in: 40...200, step: 1)
                }
                HStack {
                    Text("복잡도").frame(width: 110, alignment: .leading)
                    Picker("", selection: $m.complexity) {
                        Text("Triad").tag(1)
                        Text("7th").tag(2)
                        Text("9th / sus").tag(3)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                Picker("코드 패턴", selection: $m.chordPattern) {
                    ForEach(ChordPattern.allCases) { Text($0.rawValue).tag($0) }
                }
            }
        }
    }

    private var modeCard: some View {
        Card(title: nil) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $m.tab) {
                    Text("곡 생성").tag(AppModel.Tab.generate)
                    Text("스케일/코드 청취").tag(AppModel.Tab.listen)
                    Text("설정").tag(AppModel.Tab.settings)
                }
                .pickerStyle(.segmented).labelsHidden()
                switch m.tab {
                case .generate: generateTab
                case .listen: listenTab
                case .settings: settingsTab
                }
            }
        }
    }

    private var generateTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("길이", selection: $m.minutes) {
                ForEach(AppModel.lengths, id: \.self) { Text("\(Int($0))분").tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("분위기 (선택, 예: calm night jazz)", text: $m.mood)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button { m.generate() } label: {
                    if m.isGenerating {
                        HStack { ProgressView().controlSize(.small); Text("생성 중…") }
                    } else {
                        Label("곡 생성", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(m.isGenerating)
                if m.arrangement != nil {
                    Button("현재 설정으로 다시 전개") { m.rebuildAndPlay() }
                        .controlSize(.large)
                }
            }
            if let a = m.arrangement {
                HStack(spacing: 6) {
                    ForEach(Array(a.form.enumerated()), id: \.offset) { _, name in
                        Text(name).font(.caption2.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accent.opacity(0.18), in: Capsule())
                    }
                }
            }
        }
    }

    private var listenTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            listenRow(title: "스케일", detail: "\(noteNames[m.root]) \(m.scale.name)", icon: "pianokeys", key: "S") {
                m.listenScale()
            } picker: { EmptyView() }
            listenRow(title: "코드", detail: nil, icon: "music.note", key: "C") {
                m.listenChord()
            } picker: {
                Picker("", selection: $m.chordQualityIndex) {
                    ForEach(Array(Theory.chordQualities.enumerated()), id: \.offset) { Text($1.symbol).tag($0) }
                }
                .labelsHidden().frame(width: 120)
            }
            listenRow(title: "진행", detail: nil, icon: "music.note.list", key: "P") {
                m.listenProgression()
            } picker: {
                Picker("", selection: $m.progressionIndex) {
                    ForEach(Array(Theory.progressions.enumerated()), id: \.offset) { Text($1.name).tag($0) }
                }
                .labelsHidden().frame(width: 160)
            }
        }
    }

    private func listenRow<P: View>(title: String, detail: String?, icon: String, key: String,
                                    action: @escaping () -> Void, @ViewBuilder picker: () -> P) -> some View {
        HStack(spacing: 10) {
            Button(action: action) { Label("\(title) 듣기", systemImage: icon).frame(width: 110, alignment: .leading) }
                .controlSize(.large)
            KeyCap(key)
            picker()
            if let detail { Text(detail).foregroundStyle(.secondary) }
            Spacer()
        }
    }

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField("OpenRouter API Key", text: $m.apiKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { m.saveKey() }
            TextField("Model", text: $m.model).textFieldStyle(.roundedBorder)
            HStack(spacing: 18) {
                Stepper("Melody ch \(m.melodyChannel)", value: $m.melodyChannel, in: 1...16)
                Stepper("Chord ch \(m.chordChannel)", value: $m.chordChannel, in: 1...16)
                Stepper("Bass ch \(m.bassChannel)", value: $m.bassChannel, in: 1...16)
            }
            Text("Omnisphere: Settings → MIDI → 입력 소스에서 \"KeyScore\" 를 선택하고, Multi 모드에서 채널별로 패치를 지정하세요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var transport: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button { m.togglePlayback() } label: {
                    Image(systemName: m.isPlaying ? "stop.fill" : "play.fill")
                        .font(.title2).foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(accent))
                }
                .buttonStyle(.plain)
                .disabled(m.nowPlaying.isEmpty && !m.isPlaying)
                .opacity(m.nowPlaying.isEmpty && !m.isPlaying ? 0.4 : 1)

                Toggle(isOn: $m.loop) { Image(systemName: "repeat") }
                    .toggleStyle(.button).controlSize(.large)

                ProgressView(value: m.duration > 0 ? min(m.position / m.duration, 1) : 0)
                Text(m.duration > 0 ? "\(fmt(m.position)) / \(fmt(m.duration))" : "–:– / –:–")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .trailing)
            }
            Text(m.status).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(AppModel.shortcutHelp).font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
    }

    private func fmt(_ s: Double) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }

    // MARK: 단축키

    /// 단축키 처리. 텍스트 입력 중에는 일반 입력으로 둔다.
    private func installKeyMonitor() {
        guard keyMonitor.value == nil else { return }
        keyMonitor.value = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [m] event in
            guard !(event.window?.firstResponder is NSText) else { return event }
            return m.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let token = keyMonitor.value { NSEvent.removeMonitor(token) }
        keyMonitor.value = nil
    }
}

private struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label).font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(minWidth: 18).padding(.horizontal, 4).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.5)))
    }
}

final class MonitorBox {
    var value: Any?
}
