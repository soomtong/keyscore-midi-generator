import CoreMIDI
import XCTest
import os
@testable import KeyScore

/// "KeyScore" 가상 소스를 구독해 받은 MIDI 메시지를 모은다. 도착 시각(uptime, 초)도 함께 기록한다.
private final class Receiver: @unchecked Sendable {
    struct Message: Equatable {
        let status: UInt8
        let d1: UInt8
        let d2: UInt8
        let at: Double
    }
    private let lock = NSLock()
    private var all: [Message] = []
    private var batches: [Int] = []
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()

    var messages: [Message] {
        lock.lock(); defer { lock.unlock() }
        return all
    }

    /// 콜백 한 번에 받은 메시지 수. 송신 쪽이 MIDIReceivedEventList 를 한 번 부를 때마다 하나씩 쌓인다.
    var deliveries: [Int] {
        lock.lock(); defer { lock.unlock() }
        return batches
    }

    init?() {
        MIDIClientCreate("test" as CFString, nil, nil, &client)
        MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &port) { [unowned self] list, _ in
            let at = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
            var packet = list.pointee.packet
            var received = 0
            for _ in 0..<list.pointee.numPackets {
                withUnsafeBytes(of: packet.words) { raw in
                    let words = raw.bindMemory(to: UInt32.self)
                    for i in 0..<Int(packet.wordCount) {
                        let w = words[i]
                        lock.lock()
                        all.append(Message(status: UInt8((w >> 16) & 0xFF), d1: UInt8((w >> 8) & 0xFF), d2: UInt8(w & 0xFF), at: at))
                        lock.unlock()
                        received += 1
                    }
                }
                packet = MIDIEventPacketNext(&packet).pointee
            }
            lock.lock()
            batches.append(received)
            lock.unlock()
        }
        var found = false
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(src, kMIDIPropertyName, &name)
            if (name?.takeRetainedValue() as String?) == "KeyScore" {
                MIDIPortConnectSource(port, src, nil)
                found = true
            }
        }
        if !found { return nil }
    }
}

final class MidiPlayerTests: XCTestCase {
    func testVirtualSourceDeliversNotes() throws {
        let player = MidiPlayer()
        XCTAssertTrue(player.isReady)
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        let song = Preview.scale(root: 0, type: Theory.scales[0], channel: 1)
        player.play(song, loop: false)
        Thread.sleep(forTimeInterval: song.seconds + 0.5)
        let ons = rx.messages.filter { $0.status & 0xF0 == 0x90 }.count
        let offs = rx.messages.filter { $0.status & 0xF0 == 0x80 }.count
        XCTAssertEqual(ons, song.events.count)
        XCTAssertGreaterThanOrEqual(offs, song.events.count)
    }

    func testSustainPedalIsSentAtStartAndReleasedOnStop() throws {
        let player = MidiPlayer()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        player.setPedal(true)  // 재생 전에 밟아 둠
        Thread.sleep(forTimeInterval: 0.1)

        let song = Preview.scale(root: 0, type: Theory.scales[0], channel: 1)
        player.play(song, loop: false)
        Thread.sleep(forTimeInterval: 0.3)
        let pedals = rx.messages.filter { $0.status == 0xB0 && $0.d1 == 64 }
        XCTAssertEqual(pedals.first?.d2, 127, "재생 시작 때 페달이 내려가 있어야 한다")

        player.setPedal(false)  // 재생 중에 떼면 즉시 CC64=0
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(rx.messages.filter { $0.status == 0xB0 && $0.d1 == 64 }.last?.d2, 0)

        player.stop()
        Thread.sleep(forTimeInterval: 0.2)
        // 정지 때에는 페달을 먼저 떼고 All Notes Off(CC123)
        let tail = rx.messages.suffix(8).map { "\($0.status):\($0.d1)" }
        XCTAssertTrue(tail.contains("176:123"), "All Notes Off 가 없음: \(tail)")
    }

    /// one-shot 타이머가 다음 이벤트 시각에 정확히 깨어나는지: 125 ms 간격 16음의 간격 오차를 본다.
    func testNoteOnTimingFollowsSchedule() throws {
        let player = MidiPlayer()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        let step = 0.25  // 박
        let bpm = 120.0
        let events = (0..<16).map { NoteEvent(channel: 0, pitch: 60 + $0 % 12, velocity: 90, start: Double($0) * step, length: 0.1) }
        let song = Song(title: "timing", bpm: bpm, events: events, totalBeats: 4.5)
        player.play(song, loop: false)
        Thread.sleep(forTimeInterval: song.seconds + 0.3)
        let ons = rx.messages.filter { $0.status & 0xF0 == 0x90 }.map(\.at)
        XCTAssertEqual(ons.count, 16)
        let expected = step * 60 / bpm  // 0.125 s
        let gaps = zip(ons.dropFirst(), ons).map { $0 - $1 }
        let worst = gaps.map { abs($0 - expected) }.max() ?? 0
        print("TIMING worst gap error \(Int(worst * 1e6)) µs, gaps(ms) \(gaps.map { Int($0 * 1000) })")
        XCTAssertLessThan(worst, 0.008, "간격 오차 \(worst * 1000) ms")
        // 누적 드리프트: 첫 음부터 마지막 음까지 15 간격
        XCTAssertEqual(ons.last! - ons.first!, expected * 15, accuracy: 0.01)
    }

    /// 같은 순간에 나가는 메시지(화음 + 베이스 + 드럼)는 MIDIEventList 하나로 묶여 한 번에 도착한다.
    /// 65 음을 동시에 치면 64 워드 패킷 하나와 나머지 하나로 나뉘되 모두 도착한다.
    func testSimultaneousNotesArriveInOneBatch() throws {
        let player = MidiPlayer()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        let chord = (0..<10).map { NoteEvent(channel: UInt8($0 % 3), pitch: 48 + $0 * 3, velocity: 90, start: 0, length: 1) }
        player.play(Song(title: "chord", bpm: 120, events: chord, totalBeats: 1.5), loop: false)
        Thread.sleep(forTimeInterval: 0.3)
        let first = rx.deliveries.first ?? 0
        XCTAssertEqual(first, 10, "첫 배치에 화음 전체가 있어야 한다: \(rx.deliveries)")
        player.stop()
        Thread.sleep(forTimeInterval: 0.2)

        let rx2 = try XCTUnwrap(Receiver())
        let wall = (0..<65).map { NoteEvent(channel: 0, pitch: $0 + 30, velocity: 90, start: 0, length: 0.2) }
        player.play(Song(title: "wall", bpm: 120, events: wall, totalBeats: 1), loop: false)
        Thread.sleep(forTimeInterval: 0.8)
        let ons = rx2.messages.filter { $0.status & 0xF0 == 0x90 }
        XCTAssertEqual(ons.count, 65)
        XCTAssertEqual(rx2.deliveries.prefix(2), [64, 1])
    }

    /// 음높이가 MIDI 범위를 벗어난 이벤트는 보내지 않고, 세기 0 은 1 로 올려 Note On 이 Note Off 로 읽히지 않게 한다.
    func testSanitizesPitchAndVelocity() throws {
        let player = MidiPlayer()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        let events = [
            NoteEvent(channel: 0, pitch: 200, velocity: 90, start: 0, length: 0.2),
            NoteEvent(channel: 0, pitch: -3, velocity: 90, start: 0, length: 0.2),
            NoteEvent(channel: 0, pitch: 60, velocity: 0, start: 0, length: 0.2),
            NoteEvent(channel: 0, pitch: 62, velocity: 900, start: 0, length: 0.2),
        ]
        player.play(Song(title: "bad", bpm: 120, events: events, totalBeats: 0.5), loop: false)
        Thread.sleep(forTimeInterval: 0.5)
        let ons = rx.messages.filter { $0.status & 0xF0 == 0x90 }
        XCTAssertEqual(ons.map(\.d1), [60, 62])
        XCTAssertEqual(ons.map(\.d2), [1, 127])
    }

    /// 길이 0 인 곡을 반복 재생하면 타이머가 쉬지 않고 돌지 않고 바로 끝난다.
    func testEmptyLoopedSongStopsInsteadOfSpinning() {
        let player = MidiPlayer()
        let stopped = expectation(description: "onStop")
        player.onStop = { _ in stopped.fulfill() }
        player.play(Song(title: "empty", bpm: 120, events: [], totalBeats: 0), loop: true)
        wait(for: [stopped], timeout: 1)
    }

    /// stop 알림은 끝난 재생의 session 과 함께 온다. 곡이 끝나 스스로 멈춰도 마찬가지.
    func testStopReportsSession() {
        let player = MidiPlayer()
        let stopped = expectation(description: "onStop")
        stopped.expectedFulfillmentCount = 2
        let seen = OSAllocatedUnfairLock(initialState: [Int]())
        player.onStop = { id in
            seen.withLock { $0.append(id) }
            stopped.fulfill()
        }
        let short = Song(title: "s", bpm: 120, events: [NoteEvent(channel: 0, pitch: 60, velocity: 90, start: 0, length: 0.1)], totalBeats: 0.2)
        let first = player.play(short, loop: false)  // 0.1 초 뒤 스스로 멈춤
        Thread.sleep(forTimeInterval: 0.3)
        let second = player.play(short, loop: true)  // 반복 중 stop()
        Thread.sleep(forTimeInterval: 0.15)
        player.stop()
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(seen.withLock { $0 }, [first, second])
        XCTAssertNotEqual(first, second)
    }
}

/// MIDI Clock(0xF8) 과 Start(0xFA) / Continue(0xFB) / Stop(0xFC) / Song Position Pointer(0xF2) 송신.
private func isSystem(_ m: Receiver.Message) -> Bool { m.status >= 0xF0 }
private func median(_ xs: some Collection<Double>) -> Double { xs.sorted()[xs.count / 2] }

final class MidiClockTests: XCTestCase {
    func testClockCountCoversOneCycle() {
        XCTAssertEqual(MidiPlayer.clockCount(totalBeats: 1), 24)
        XCTAssertEqual(MidiPlayer.clockCount(totalBeats: 7.5), 180)  // 스케일 듣기 (1/8 × 15)
        XCTAssertEqual(MidiPlayer.clockCount(totalBeats: 0), 0)
        XCTAssertEqual(MidiPlayer.clockCount(totalBeats: .nan), 0)
        XCTAssertEqual(MidiPlayer.clockCount(totalBeats: .infinity), 0)
    }

    /// 기본은 꺼져 있어 노트와 CC 만 나간다.
    func testClockIsOffByDefault() throws {
        let player = MidiPlayer()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        let song = Song(title: "c", bpm: 240, events: [NoteEvent(channel: 0, pitch: 60, velocity: 90, start: 0, length: 0.5)], totalBeats: 1)
        player.play(song, loop: false)
        Thread.sleep(forTimeInterval: song.seconds + 0.3)
        XCTAssertFalse(rx.messages.isEmpty)
        XCTAssertTrue(rx.messages.filter(isSystem).isEmpty, "\(rx.messages.filter(isSystem).map(\.status))")
    }

    /// Start → 4분음표당 24 펄스 → Stop. 첫 Clock 은 첫 Note On 보다 먼저 나가고, 펄스 간격은 템포를 따른다.
    func testClockFollowsTempoBetweenStartAndStop() throws {
        let player = MidiPlayer()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        player.setClock(true)
        let bpm = 120.0
        let events = (0..<4).map { NoteEvent(channel: 0, pitch: 60, velocity: 90, start: Double($0), length: 0.5) }
        let song = Song(title: "clock", bpm: bpm, events: events, totalBeats: 4)
        player.play(song, loop: false)
        Thread.sleep(forTimeInterval: song.seconds + 0.4)

        let all = rx.messages
        XCTAssertEqual(all.first(where: isSystem)?.status, 0xFA, "Start 가 먼저")
        XCTAssertEqual(all.last(where: isSystem)?.status, 0xFC, "곡이 끝나면 Stop")
        let firstClock = try XCTUnwrap(all.firstIndex { $0.status == 0xF8 })
        let firstOn = try XCTUnwrap(all.firstIndex { $0.status & 0xF0 == 0x90 })
        XCTAssertLessThan(firstClock, firstOn, "같은 시각이면 Clock 이 먼저")

        let clocks = all.filter { $0.status == 0xF8 }.map(\.at)
        XCTAssertEqual(clocks.count, 4 * MidiPlayer.clocksPerBeat)
        let step = 60 / bpm / Double(MidiPlayer.clocksPerBeat)  // 20.8 ms
        let worst = zip(clocks.dropFirst(), clocks).map { abs($0 - $1 - step) }.max() ?? 0
        print("CLOCK worst gap error \(Int(worst * 1e6)) µs")
        XCTAssertLessThan(worst, 0.008)
        XCTAssertEqual(clocks.last! - clocks.first!, step * Double(clocks.count - 1), accuracy: 0.01)
        // 박마다 Note On 이 펄스 24개 간격으로 온다 (0, 24, 48, 72 번째 펄스와 같은 시각)
        let ons = all.filter { $0.status & 0xF0 == 0x90 }.map(\.at)
        for (beat, on) in ons.enumerated() {
            XCTAssertEqual(on, clocks[beat * MidiPlayer.clocksPerBeat], accuracy: 0.004)
        }
    }

    /// 반복 재생은 처음으로 돌아갈 때마다 Start 를 다시 보내고, 바퀴마다 펄스 수가 같다.
    func testLoopRestartsWithStart() throws {
        let player = MidiPlayer()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        player.setClock(true)
        let song = Song(title: "loop", bpm: 240, events: [NoteEvent(channel: 0, pitch: 60, velocity: 90, start: 0, length: 0.5)], totalBeats: 1.5)
        player.play(song, loop: true)  // 한 바퀴 0.375 초
        Thread.sleep(forTimeInterval: 1.0)
        player.stop()
        Thread.sleep(forTimeInterval: 0.2)

        let system = rx.messages.filter(isSystem).map(\.status)
        XCTAssertEqual(system.last, 0xFC)
        // Start 로 나눈 각 바퀴(마지막 바퀴는 중간에 멈춤)의 펄스 수
        let cycles = system.dropLast().split(separator: 0xFA, omittingEmptySubsequences: false).dropFirst().map(\.count)
        XCTAssertGreaterThanOrEqual(cycles.count, 3, "\(cycles)")
        for full in cycles.dropLast() { XCTAssertEqual(full, 36) }
    }

    /// 재생 중에 켜면 다음 16분음표 자리를 SPP 로 알리고 Continue 뒤에 그 자리부터 펄스를 보낸다. 끄면 바로 Stop.
    func testTogglingDuringPlaybackUsesSongPositionAndStop() throws {
        let player = MidiPlayer()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        let bpm = 120.0  // 16분음표 0.125 초
        let song = Song(title: "late", bpm: bpm, events: [NoteEvent(channel: 0, pitch: 60, velocity: 90, start: 0, length: 0.5)], totalBeats: 8)
        player.play(song, loop: false)
        let started = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        Thread.sleep(forTimeInterval: 0.3)
        player.setClock(true)
        Thread.sleep(forTimeInterval: 0.5)
        player.setClock(false)
        Thread.sleep(forTimeInterval: 0.2)
        let afterOff = rx.messages.count
        Thread.sleep(forTimeInterval: 0.2)
        player.stop()
        Thread.sleep(forTimeInterval: 0.2)

        let all = rx.messages
        let system = all.filter(isSystem)
        XCTAssertEqual(system.map(\.status).first, 0xF2)
        XCTAssertEqual(system.map(\.status).dropFirst().first, 0xFB)
        XCTAssertFalse(system.contains { $0.status == 0xFA }, "중간에 켜면 Start 가 아니라 Continue")
        let spp = try XCTUnwrap(system.first).d1
        XCTAssertTrue((3...4).contains(spp), "0.3 초 뒤의 다음 16분음표: \(spp)")
        // 첫 펄스는 SPP 자리에서 나간다
        let firstClock = try XCTUnwrap(system.first { $0.status == 0xF8 }).at
        XCTAssertEqual(firstClock - started, Double(spp) * 0.125, accuracy: 0.02)
        // 끈 뒤에는 Stop 하나뿐이고, 정지할 때 Stop 을 다시 보내지 않는다
        XCTAssertEqual(system.last?.status, 0xFC)
        XCTAssertEqual(system.filter { $0.status == 0xFC }.count, 1)
        XCTAssertTrue(all[afterOff...].filter(isSystem).isEmpty)
    }

    /// Start(재생 시작과 반복 되감기 모두)와 바로 다음 Clock 사이에 1 ms 가까운 간격이 있다.
    func testStartLeadsFirstClock() throws {
        let player = MidiPlayer()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        player.setClock(true)
        player.play(Song(title: "lead", bpm: 240, events: [], totalBeats: 1), loop: true)  // 한 바퀴 0.25 초
        Thread.sleep(forTimeInterval: 0.7)
        player.stop()
        Thread.sleep(forTimeInterval: 0.2)

        let system = rx.messages.filter(isSystem)
        let starts = system.indices.filter { system[$0].status == 0xFA }
        XCTAssertGreaterThanOrEqual(starts.count, 3)
        // 도착 시각 지터에 흔들리지 않게 중앙값으로 본다
        let leads = starts.filter { $0 + 1 < system.count && system[$0 + 1].status == 0xF8 }.map { system[$0 + 1].at - system[$0].at }
        XCTAssertGreaterThan(median(leads), 0.0007, "\(leads.map { Int($0 * 1e6) }) µs")
    }

    /// 곡 길이가 펄스 격자에 맞지 않아도(1.3 박 → 31.2 펄스) 바퀴 경계의 펄스 간격이 일정하다.
    func testLoopKeepsClockSpacingOffGrid() throws {
        let player = MidiPlayer()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        player.setClock(true)
        let bpm = 240.0
        player.play(Song(title: "off-grid", bpm: bpm, events: [], totalBeats: 1.3), loop: true)
        Thread.sleep(forTimeInterval: 1.2)
        player.stop()
        Thread.sleep(forTimeInterval: 0.2)

        let system = rx.messages.filter(isSystem).map(\.status)
        let cycles = system.dropLast().split(separator: 0xFA, omittingEmptySubsequences: false).dropFirst().map(\.count)
        XCTAssertGreaterThanOrEqual(cycles.count, 3, "\(cycles)")
        for full in cycles.dropLast() { XCTAssertEqual(full, 32) }
        let clocks = rx.messages.filter { $0.status == 0xF8 }.map(\.at)
        let step = 60 / bpm / Double(MidiPlayer.clocksPerBeat)  // 10.4 ms
        // 펄스는 하나의 격자(i × step) 위에 있어야 한다. 바퀴 경계에서 간격이 줄면(0.8 step) 바퀴마다 8 ms 씩 앞당겨진다.
        // 도착 시각 지터에 흔들리지 않게 첫 바퀴와 마지막 바퀴의 격자 오프셋 중앙값을 비교한다.
        let offsets = clocks.enumerated().map { $0.element - Double($0.offset) * step }
        let drift = median(offsets.suffix(32)) - median(offsets.prefix(32))
        XCTAssertEqual(drift, 0, accuracy: 0.004, "바퀴를 거치며 펄스 격자가 \(drift * 1000) ms 밀림")
    }

    /// 반복 재생에서 곡 끝을 넘는 음이 있어도 되감기가 늦어지지 않아 Clock 이 끊기지 않고, 그 음은 되감을 때 끊긴다.
    func testLoopDoesNotWaitForNotesPastTheEnd() throws {
        let player = MidiPlayer()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        player.setClock(true)
        let bpm = 240.0
        let long = NoteEvent(channel: 0, pitch: 60, velocity: 90, start: 0, length: 3)  // 곡(1 박)보다 2 박 길다
        player.play(Song(title: "tail", bpm: bpm, events: [long], totalBeats: 1), loop: true)
        Thread.sleep(forTimeInterval: 0.9)
        player.stop()
        Thread.sleep(forTimeInterval: 0.2)

        let clocks = rx.messages.filter { $0.status == 0xF8 }.map(\.at)
        let step = 60 / bpm / Double(MidiPlayer.clocksPerBeat)
        // 되감기가 남은 Note Off(0.5 초 뒤)를 기다리면 바퀴마다 그만큼 펄스가 끊긴다
        let longest = zip(clocks.dropFirst(), clocks).map { $0 - $1 }.max() ?? 0
        XCTAssertLessThan(longest, step * 4, "Clock 공백 \(longest * 1000) ms")
        XCTAssertGreaterThanOrEqual(clocks.count, 3 * MidiPlayer.clocksPerBeat)
        // 바퀴마다 Note On 앞에 앞 바퀴 음의 Note Off 가 온다
        let notes = rx.messages.filter { $0.status & 0xE0 == 0x80 }.map(\.status)
        XCTAssertEqual(Array(notes.prefix(5)), [0x90, 0x80, 0x90, 0x80, 0x90])
    }

    /// 재생 중에 켰는데 이번 바퀴에 남은 펄스가 없으면 Start/Continue 를 보내지 않았으므로 곡 끝에 Stop 도 보내지 않는다.
    func testSkippedCycleSendsNoUnpairedStop() throws {
        let player = MidiPlayer()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        // 마지막 Note Off 가 곡 끝(0.25 초)을 넘는다
        let song = Song(title: "late", bpm: 240, events: [NoteEvent(channel: 0, pitch: 60, velocity: 90, start: 0, length: 2)], totalBeats: 1)
        player.play(song, loop: false)
        Thread.sleep(forTimeInterval: 0.35)
        player.setClock(true)
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertTrue(rx.messages.contains { $0.status == 0x80 }, "곡이 끝나야 한다")
        XCTAssertTrue(rx.messages.filter(isSystem).isEmpty, "\(rx.messages.filter(isSystem).map(\.status))")
    }
}

/// AppModel 에서 청취 옵션을 켜고 실제로 나오는 MIDI 노트 순서를 확인한다.
final class ListenOptionsEndToEndTests: XCTestCase {
    @MainActor
    private func notesPlayed(_ kind: AppModel.PreviewKind = .scale, _ configure: (AppModel) -> Void) async throws -> [UInt8] {
        let m = AppModel()
        let rx = try XCTUnwrap(Receiver(), "KeyScore 가상 소스를 찾지 못함")
        m.bpm = 200  // 빨리 끝나도록
        configure(m)
        m.listen(kind)
        // 자동 재생 디바운스(150ms)보다 길게 기다려, 값 변경 직후 재생해도 다시 시작되지 않는지 함께 확인한다
        try await Task.sleep(for: .seconds(m.duration + 0.6))
        return rx.messages.filter { $0.status & 0xF0 == 0x90 }.map(\.d1)
    }

    @MainActor
    func testScaleIgnoresSequenceOptions() async throws {
        let asc: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        let upDown = asc + asc.reversed().dropFirst()
        let plain = try await notesPlayed { _ in }
        XCTAssertEqual(plain, upDown)  // 올라갔다 내려옴, 꼭대기 음은 한 번만
        let opts = try await notesPlayed {
            $0.listenOptions.together = true
            $0.listenOptions.descending = true
            $0.listenOptions.upDown = true
            $0.listenOptions.twoOctaves = true
        }
        XCTAssertEqual(opts, upDown)
    }

    @MainActor
    func testOptionsApplyToSequentialChord() async throws {
        let plain = try await notesPlayed(.chord) { _ in }
        XCTAssertEqual(plain, [60, 64, 67])
        let desc = try await notesPlayed(.chord) { $0.listenOptions.descending = true }
        let two = try await notesPlayed(.chord) { $0.listenOptions.twoOctaves = true }
        let upDown = try await notesPlayed(.chord) { $0.listenOptions.upDown = true }
        XCTAssertEqual(desc, [67, 64, 60])
        XCTAssertEqual(two, [60, 64, 67, 72, 76, 79])
        XCTAssertEqual(upDown, [60, 64, 67, 64, 60])
    }

    @MainActor
    func testTogetherIgnoresSequenceOptions() async throws {
        let notes = try await notesPlayed(.chord) {
            $0.listenOptions.together = true
            $0.listenOptions.descending = true
            $0.listenOptions.twoOctaves = true
        }
        XCTAssertEqual(Set(notes), [60, 64, 67])
    }

    /// 정지 직후 바로 다시 재생하면, 늦게 도착한 이전 재생의 정지 알림이 새 재생 상태를 덮어쓰지 않는다.
    @MainActor
    func testStopThenPlayKeepsPlayingState() async throws {
        let m = AppModel()
        m.bpm = 60
        m.listen(.scale)
        m.stop()
        m.listen(.scale)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(m.isPlaying)
        m.stop()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(m.isPlaying)
    }

    /// 진행 알림이 position 에 반영되고, 자동 정지 뒤에는 0 으로 돌아온다.
    @MainActor
    func testProgressAdvancesAndResets() async throws {
        let m = AppModel()
        m.bpm = 200
        m.listen(.chord)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertGreaterThan(m.position, 0.2)
        try await Task.sleep(for: .seconds(m.duration + 0.3))
        XCTAssertFalse(m.isPlaying)
        XCTAssertEqual(m.position, 0)
    }
}
