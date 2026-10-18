import CoreMIDI
import XCTest
@testable import KeyScore

final class MidiPlayerTests: XCTestCase {
    func testVirtualSourceDeliversNotes() throws {
        let player = MidiPlayer()
        var client = MIDIClientRef()
        MIDIClientCreate("test" as CFString, nil, nil, &client)

        final class Counter: @unchecked Sendable {
            let lock = NSLock()
            var ons = 0, offs = 0
        }
        let counter = Counter()
        var port = MIDIPortRef()
        MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &port) { list, _ in
            var packet = list.pointee.packet
            for _ in 0..<list.pointee.numPackets {
                withUnsafeBytes(of: packet.words) { raw in
                    let words = raw.bindMemory(to: UInt32.self)
                    for i in 0..<Int(packet.wordCount) {
                        let status = (words[i] >> 16) & 0xF0
                        counter.lock.lock()
                        if status == 0x90 { counter.ons += 1 } else if status == 0x80 { counter.offs += 1 }
                        counter.lock.unlock()
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
        XCTAssertTrue(found, "KeyScore 가상 소스를 찾지 못함")

        let song = Preview.scale(root: 0, type: Theory.scales[0], channel: 1)
        let expected = song.events.count
        player.play(song, loop: false)
        Thread.sleep(forTimeInterval: song.seconds + 0.5)
        counter.lock.lock(); defer { counter.lock.unlock() }
        XCTAssertEqual(counter.ons, expected)
        XCTAssertGreaterThanOrEqual(counter.offs, expected)
    }
}
