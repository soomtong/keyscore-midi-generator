import CoreMIDI
import XCTest
@testable import KeyScore

/// "KeyScore" 가상 소스를 구독해 받은 MIDI 메시지를 모은다.
private final class Receiver: @unchecked Sendable {
    struct Message: Equatable { let status: UInt8; let d1: UInt8; let d2: UInt8 }
    private let lock = NSLock()
    private var all: [Message] = []
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()

    var messages: [Message] {
        lock.lock(); defer { lock.unlock() }
        return all
    }

    init?() {
        MIDIClientCreate("test" as CFString, nil, nil, &client)
        MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &port) { [unowned self] list, _ in
            var packet = list.pointee.packet
            for _ in 0..<list.pointee.numPackets {
                withUnsafeBytes(of: packet.words) { raw in
                    let words = raw.bindMemory(to: UInt32.self)
                    for i in 0..<Int(packet.wordCount) {
                        let w = words[i]
                        lock.lock()
                        all.append(Message(status: UInt8((w >> 16) & 0xFF), d1: UInt8((w >> 8) & 0xFF), d2: UInt8(w & 0xFF)))
                        lock.unlock()
                    }
                }
                packet = MIDIEventPacketNext(&packet).pointee
            }
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

        var o = ListenOptions()
        o.upDown = false
        let song = Preview.scale(root: 0, type: Theory.scales[0], channel: 1, options: o)
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
    func testScaleOptionsReachMIDI() async throws {
        let asc: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        let plain = try await notesPlayed { _ in }
        XCTAssertEqual(plain, asc)  // 기본값은 오름차순만, 중복 재생 없음
        let desc = try await notesPlayed { $0.listenOptions.descending = true }
        XCTAssertEqual(desc, Array(asc.reversed()))
        let upDown = try await notesPlayed { $0.listenOptions.upDown = true }
        XCTAssertEqual(upDown, asc + Array(asc.reversed().dropFirst()))
        let two = try await notesPlayed { $0.listenOptions.twoOctaves = true }
        XCTAssertEqual(two.count, 15)
        XCTAssertEqual(two.last, 84)
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
}
