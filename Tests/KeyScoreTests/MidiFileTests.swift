import AudioToolbox
import XCTest
@testable import KeyScore

final class MidiFileTests: XCTestCase {
    /// 테스트용 SMF 리더. 청크를 나누고 VLQ 를 풀어 트랙별 (절대 tick, 바이트) 이벤트로 돌려준다.
    struct Parsed {
        var format = 0, division = 0
        var tracks: [[(tick: Int, bytes: [UInt8])]] = []
    }

    static func parse(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws -> Parsed {
        let b = [UInt8](data)
        var i = 0
        func u(_ n: Int) throws -> Int {
            guard i + n <= b.count else { throw CocoaError(.fileReadCorruptFile) }
            defer { i += n }
            return b[i..<i + n].reduce(0) { $0 << 8 | Int($1) }
        }
        func vlq() throws -> Int {
            var v = 0
            for _ in 0..<4 {
                let x = try u(1)
                v = v << 7 | (x & 0x7F)
                if x & 0x80 == 0 { return v }
            }
            throw CocoaError(.fileReadCorruptFile)
        }
        var p = Parsed()
        XCTAssertEqual(Array(b[0..<4]), Array("MThd".utf8), file: file, line: line)
        i = 4
        XCTAssertEqual(try u(4), 6, file: file, line: line)
        p.format = try u(2)
        let ntrks = try u(2)
        p.division = try u(2)
        for _ in 0..<ntrks {
            XCTAssertEqual(Array(b[i..<i + 4]), Array("MTrk".utf8), file: file, line: line)
            i += 4
            let end = try u(4) + i
            var tick = 0
            var events: [(Int, [UInt8])] = []
            while i < end {
                tick += try vlq()
                let status = try u(1)
                XCTAssertTrue(status & 0x80 != 0, "running status 는 쓰지 않는다", file: file, line: line)
                if status == 0xFF {
                    let type = try u(1)
                    let len = try vlq()
                    events.append((tick, [0xFF, UInt8(type)] + b[i..<i + len]))
                    i += len
                } else {
                    events.append((tick, [UInt8(status), UInt8(try u(1)), UInt8(try u(1))]))
                }
            }
            XCTAssertEqual(i, end, "청크 길이와 내용이 맞아야 한다", file: file, line: line)
            XCTAssertEqual(events.last?.1, [0xFF, 0x2F], "End of Track 으로 끝나야 한다", file: file, line: line)
            XCTAssertEqual(events.filter { $0.1 == [0xFF, 0x2F] }.count, 1, file: file, line: line)
            p.tracks.append(events)
        }
        XCTAssertEqual(i, b.count, file: file, line: line)
        return p
    }

    /// 모든 Note On 에 짝 Off 가 있고, 같은 (채널, 음높이) 가 겹치지 않는지. 노트 수를 돌려준다.
    @discardableResult
    static func checkPairs(_ p: Parsed, file: StaticString = #filePath, line: UInt = #line) -> Int {
        var count = 0
        for t in p.tracks.dropFirst() {
            var sounding = Set<[UInt8]>()
            for (_, e) in t where e[0] & 0xF0 == 0x90 || e[0] & 0xF0 == 0x80 {
                let key = [e[0] & 0x0F, e[1]]
                if e[0] & 0xF0 == 0x90 {
                    XCTAssertGreaterThan(e[2], 0, file: file, line: line)
                    XCTAssertTrue(sounding.insert(key).inserted, "겹친 Note On \(key)", file: file, line: line)
                    count += 1
                } else {
                    XCTAssertNotNil(sounding.remove(key), "짝 없는 Note Off \(key)", file: file, line: line)
                }
            }
            XCTAssertTrue(sounding.isEmpty, file: file, line: line)
        }
        return count
    }

    func testVLQ() {
        XCTAssertEqual(MidiFile.vlq(0), [0x00])
        XCTAssertEqual(MidiFile.vlq(0x7F), [0x7F])
        XCTAssertEqual(MidiFile.vlq(0x80), [0x81, 0x00])
        XCTAssertEqual(MidiFile.vlq(0x3FFF), [0xFF, 0x7F])
        XCTAssertEqual(MidiFile.vlq(0x4000), [0x81, 0x80, 0x00])
        XCTAssertEqual(MidiFile.vlq(0x0FFF_FFFF), [0xFF, 0xFF, 0xFF, 0x7F])
        XCTAssertEqual(MidiFile.vlq(0x1000_0000), [0xFF, 0xFF, 0xFF, 0x7F])  // 상한으로 자른다
        XCTAssertEqual(MidiFile.vlq(-5), [0x00])
    }

    func testTempo() {
        XCTAssertEqual(MidiFile.microsPerBeat(120), 0x07A120)
        XCTAssertEqual(MidiFile.microsPerBeat(40), 1_500_000)
        XCTAssertEqual(MidiFile.microsPerBeat(200), 300_000)
        XCTAssertEqual(MidiFile.microsPerBeat(0), 500_000)
        XCTAssertEqual(MidiFile.microsPerBeat(.nan), 500_000)
        XCTAssertEqual(MidiFile.microsPerBeat(1), 0xFF_FFFF)
    }

    func testEmptySongHasOnlyConductor() throws {
        let data = MidiFile.data(Song(title: "", bpm: 120, events: [], totalBeats: 0))
        XCTAssertEqual(Array(data.prefix(14)), [0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 1, 0, 1, 0x01, 0xE0])
        let p = try Self.parse(data)
        XCTAssertEqual(p.tracks.count, 1)
        XCTAssertTrue(p.tracks[0].contains { $0.bytes == [0xFF, 0x51, 0x07, 0xA1, 0x20] })
        XCTAssertTrue(p.tracks[0].contains { $0.bytes == [0xFF, 0x58, 4, 2, 24, 8] })
    }

    func testTracksPerChannelAndOrdering() throws {
        let song = Song(title: "곡", bpm: 100, events: [
            NoteEvent(channel: 9, pitch: 36, velocity: 100, start: 0, length: 0.5),
            NoteEvent(channel: 0, pitch: 60, velocity: 0, start: 0, length: 1),  // 세기 0 → 1
            NoteEvent(channel: 0, pitch: 60, velocity: 90, start: 1, length: 1),  // 앞 음 Off 와 같은 tick
            NoteEvent(channel: 0, pitch: 200, velocity: 90, start: 0, length: 1),  // 버린다
            NoteEvent(channel: 0, pitch: 62, velocity: 90, start: .nan, length: 1),  // 버린다
            NoteEvent(channel: 0, pitch: 64, velocity: 90, start: -1, length: 1),  // 버린다
        ], totalBeats: 4)
        let p = try Self.parse(MidiFile.data(song, trackNames: [0: "Melody"]))
        XCTAssertEqual(p.format, 1)
        XCTAssertEqual(p.division, 480)
        XCTAssertEqual(p.tracks.count, 3)
        XCTAssertEqual(p.tracks[0].first?.bytes, [0xFF, 0x03] + Array("곡".utf8))
        XCTAssertEqual(p.tracks[1].first?.bytes, [0xFF, 0x03] + Array("Melody".utf8))
        XCTAssertEqual(p.tracks[2].first?.bytes, [0xFF, 0x03] + Array("Channel 10".utf8))
        let notes = p.tracks[1].filter { $0.bytes[0] != 0xFF }
        XCTAssertEqual(notes.map(\.tick), [0, 480, 480, 960])
        XCTAssertEqual(notes.map(\.bytes), [[0x90, 60, 1], [0x80, 60, 64], [0x90, 60, 90], [0x80, 60, 64]])
        // 곡 끝의 쉼표까지 남는다
        XCTAssertEqual(p.tracks.map { $0.last!.tick }, [1920, 1920, 1920])
        Self.checkPairs(p)
    }

    func testOverlappingSamePitchIsClipped() throws {
        let song = Song(title: "T", bpm: 120, events: [
            NoteEvent(channel: 0, pitch: 60, velocity: 80, start: 0, length: 4),
            NoteEvent(channel: 0, pitch: 60, velocity: 90, start: 1, length: 1),
            NoteEvent(channel: 0, pitch: 60, velocity: 50, start: 1, length: 3),  // 같은 tick 의 약한 쪽은 버린다
            NoteEvent(channel: 0, pitch: 60, velocity: 70, start: 3, length: 0),  // 길이 0 → 1 tick
        ], totalBeats: 4)
        let p = try Self.parse(MidiFile.data(song))
        XCTAssertEqual(Self.checkPairs(p), 3)
        let notes = p.tracks[1].filter { $0.bytes[0] != 0xFF }
        XCTAssertEqual(notes.map(\.tick), [0, 480, 480, 960, 1440, 1441])
        XCTAssertEqual(notes[2].bytes, [0x90, 60, 90])
    }

    /// 실제 전개 결과: 모든 코드·리듬 패턴과 리프로 만든 곡이 짝이 맞는 파일이 되고, AudioToolbox 로도 읽힌다.
    func testArrangedSongsRoundTrip() throws {
        var arr = KeyScoreTests.sample
        arr.sections["A"]!.melody = [MelodyNote(beat: 0, pitch: 72, length: 3), MelodyNote(beat: 2, pitch: 72, length: 2)]
        arr.sections["A"]!.riff = [MelodyNote(beat: 0, pitch: 67, length: 0.5)]
        arr.sections["A"]!.bass = [MelodyNote(beat: 0, pitch: 36, length: 8), MelodyNote(beat: 4, pitch: 36, length: 1)]
        for (i, chord) in ChordPattern.allCases.enumerated() {
            let drums = DrumPattern.allCases[i % DrumPattern.allCases.count]
            let second = SecondPart.allCases[i % SecondPart.allCases.count]
            let settings = ArrangeSettings(bpm: 96, minutes: 0.2, chordPattern: chord, drumPattern: drums,
                                           secondPart: second, channels: ChannelMap())
            let song = Arranger.build(arr, options: settings.options)
            let data = MidiFile.data(song, trackNames: AppModel.trackNames(settings))
            let p = try Self.parse(data)
            let count = Self.checkPairs(p)
            XCTAssertGreaterThan(count, 0, "\(chord)")
            XCTAssertEqual(p.tracks.count, 1 + Set(song.events.map(\.channel)).count)
            XCTAssertEqual(Set(p.tracks.map { $0.last!.tick }), [Int((song.totalBeats * 480).rounded())])
            XCTAssertEqual(try Self.audioToolboxNoteCount(data), count, "\(chord)")
        }
    }

    func testTrackNamesSkipDisabledParts() {
        var s = ArrangeSettings(bpm: 100, minutes: 1, chordPattern: .block, drumPattern: .off, secondPart: .off,
                                channels: ChannelMap(melody: 1, chords: 2, bass: 2, second: 1, rhythm: 10))
        XCTAssertEqual(AppModel.trackNames(s), [0: "Melody", 1: "Chords + Bass"])
        s.secondPart = SecondPart.allCases.first { $0 != .off }!
        s.drumPattern = DrumPattern.allCases.first { $0 != .off }!
        XCTAssertEqual(AppModel.trackNames(s), [0: "Melody + Second", 1: "Chords + Bass", 9: "Rhythm"])
    }

    func testFileName() {
        XCTAssertEqual(AppModel.fileName("  a/b:c  "), "a-b-c")
        XCTAssertEqual(AppModel.fileName("..hidden"), "hidden")
        XCTAssertEqual(AppModel.fileName(" "), "KeyScore")
    }

    /// 독립 검증: AudioToolbox 가 파일을 읽어 센 노트 수. 템포가 120 BPM 이 아닌 값으로 들어갔는지도 본다.
    static func audioToolboxNoteCount(_ data: Data) throws -> Int {
        var seq: MusicSequence?
        XCTAssertEqual(NewMusicSequence(&seq), noErr)
        let sequence = try XCTUnwrap(seq)
        defer { DisposeMusicSequence(sequence) }
        XCTAssertEqual(MusicSequenceFileLoadData(sequence, data as CFData, .midiType, []), noErr)

        var tempoTrack: MusicTrack?
        XCTAssertEqual(MusicSequenceGetTempoTrack(sequence, &tempoTrack), noErr)
        var bpms: [Double] = []
        try forEachEvent(XCTUnwrap(tempoTrack)) { type, ptr in
            if type == kMusicEventType_ExtendedTempo {
                bpms.append(ptr!.assumingMemoryBound(to: ExtendedTempoEvent.self).pointee.bpm)
            }
        }
        XCTAssertEqual(bpms.count, 1)
        XCTAssertEqual(bpms.first ?? 0, 96, accuracy: 0.01)

        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)
        var notes = 0
        for t in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(sequence, t, &track)
            try forEachEvent(XCTUnwrap(track)) { type, _ in if type == kMusicEventType_MIDINoteMessage { notes += 1 } }
        }
        return notes
    }

    static func forEachEvent(_ track: MusicTrack, _ body: (MusicEventType, UnsafeRawPointer?) -> Void) throws {
        var it: MusicEventIterator?
        XCTAssertEqual(NewMusicEventIterator(track, &it), noErr)
        let iterator = try XCTUnwrap(it)
        defer { DisposeMusicEventIterator(iterator) }
        var has: DarwinBoolean = false
        MusicEventIteratorHasCurrentEvent(iterator, &has)
        while has.boolValue {
            var time: MusicTimeStamp = 0
            var type: MusicEventType = 0
            var ptr: UnsafeRawPointer?
            var size: UInt32 = 0
            MusicEventIteratorGetEventInfo(iterator, &time, &type, &ptr, &size)
            body(type, ptr)
            MusicEventIteratorNextEvent(iterator)
            MusicEventIteratorHasCurrentEvent(iterator, &has)
        }
    }
}
