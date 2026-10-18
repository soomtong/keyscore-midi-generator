import Foundation

/// 곡을 전개할 때 쓰는 설정. 곡을 만든 뒤 바뀌면 ↻ 다시 전개로 반영된다.
struct ArrangeSettings: Equatable {
    var bpm: Double
    var minutes: Double
    var chordPattern: ChordPattern
    var drumPattern: DrumPattern
    var secondPart: SecondPart
    var channels: ChannelMap

    var options: ArrangeOptions {
        ArrangeOptions(bpm: bpm, minutes: minutes, channels: channels, chordPattern: chordPattern,
                       drumPattern: drumPattern, secondPart: secondPart)
    }

    var targetBars: Int { Arranger.targetBars(minutes: minutes, bpm: bpm) }

    /// old 와 달라진 항목 이름
    func changes(from old: Self) -> [String] {
        [("BPM", bpm != old.bpm), ("길이", minutes != old.minutes), ("코드 패턴", chordPattern != old.chordPattern),
         ("리듬", drumPattern != old.drumPattern), ("Second Part", secondPart != old.secondPart), ("채널", channels != old.channels)]
            .filter(\.1).map(\.0)
    }
}

/// 프롬프트에 들어가는 설정. 곡을 만든 뒤 바뀌면 다시 생성해야 반영된다.
struct PromptSettings: Equatable {
    var root: Int
    var scaleIndex: Int
    var complexity: Int
    var melodyStyle: MelodyStyle
    var mood: String
    var progressionIndex: Int
    var formPreset: FormPreset

    func changes(from old: Self) -> [String] {
        [("Key", root != old.root), ("Scale", scaleIndex != old.scaleIndex), ("복잡도", complexity != old.complexity),
         ("멜로디 패턴", melodyStyle != old.melodyStyle), ("분위기", mood != old.mood),
         ("진행", progressionIndex != old.progressionIndex), ("FORM", formPreset != old.formPreset)]
            .filter(\.1).map(\.0)
    }
}
