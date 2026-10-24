# 프로젝트 메모리

- [동시성 모델과 MIDI 타이밍 설계](docs/decisions/2026-10-18-concurrency-and-midi-timing.md) — MidiPlayer 는 actor 가 아닌 전용 큐 + one-shot 타이머, AppModel 은 @Observable, LLM 출력 클램프, 환경변수 키는 Keychain 에 쓰지 않음
- [MIDI 송신 배칭, LLM 입력 상한, 관찰 범위](docs/decisions/2026-10-19-midi-batching-and-llm-input-bounds.md) — 같은 tick 의 메시지는 MIDIEventList 하나로, 리프 배치는 SoundingMap 이분 탐색, position 은 작은 뷰에서만 읽음, ephemeral URLSession, Keychain ThisDeviceOnly
- [MIDI 파일 내보내기](docs/decisions/2026-10-19-midi-file-export.md) — SMF Format 1 · 480 PPQ, 채널 단위 트랙, 같은 음 겹침은 다음 시작에서 끊음, 마지막 전개 곡 그대로 저장, Key signature·Program Change 생략
- [MIDI Clock 송신](docs/decisions/2026-10-23-midi-clock.md) — 기본 끔, 박당 24 펄스를 목록이 아니라 타이머로 계산, 같은 시각이면 Clock 먼저, 반복 때 Start 재송신, 재생 중 켜면 SPP + Continue, 끄면 Stop, UMP type 1
- [프레이즈 카탈로그와 코드 라인](docs/decisions/2026-10-24-phrases-and-chord-lines.md) — 멜로디 듣기는 MelodyStyle 대신 유명 프레이즈 카탈로그(원곡 조성 고정, 간이 표기로 기록), 진행은 ChordStep(박 수 · 근음 조정 · 코드 패밀리 · 고정 심볼 · 슬래시 베이스)과 voiceLead 보이싱, 2박 분할 묶음은 뺌(빨라질 뿐), 모던 팝 묶음과 드럼 16종, Groove 옵션으로 묶인 GM 드럼, 곡 생성에는 곡명 없이 선율 성격만
