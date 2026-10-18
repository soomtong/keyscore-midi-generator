# 프로젝트 메모리

- [동시성 모델과 MIDI 타이밍 설계](docs/decisions/2026-10-18-concurrency-and-midi-timing.md) — MidiPlayer 는 actor 가 아닌 전용 큐 + one-shot 타이머, AppModel 은 @Observable, LLM 출력 클램프, 환경변수 키는 Keychain 에 쓰지 않음
- [MIDI 송신 배칭, LLM 입력 상한, 관찰 범위](docs/decisions/2026-10-19-midi-batching-and-llm-input-bounds.md) — 같은 tick 의 메시지는 MIDIEventList 하나로, 리프 배치는 SoundingMap 이분 탐색, position 은 작은 뷰에서만 읽음, ephemeral URLSession, Keychain ThisDeviceOnly
- [MIDI 파일 내보내기](docs/decisions/2026-10-19-midi-file-export.md) — SMF Format 1 · 480 PPQ, 채널 단위 트랙, 같은 음 겹침은 다음 시작에서 끊음, 마지막 전개 곡 그대로 저장, Key signature·Program Change 생략
