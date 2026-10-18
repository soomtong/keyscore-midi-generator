# KeyScore MIDI Generator

macOS 전용. OpenRouter LLM 으로 멜로디/코드 섹션을 만들고, CoreMIDI 가상 소스 "KeyScore" 로 Omnisphere 등 가상악기에 송신한다.

## 실행
    swift run KeyScore

- API key: 환경변수 OPENROUTER_API_KEY 또는 설정 탭 입력(Keychain 저장). 모델은 OPENROUTER_MODEL 또는 설정 탭.
- Omnisphere: Settings → MIDI 입력에서 "KeyScore" 선택. 기본 채널은 Melody 1, Chord 2, Bass 3 (설정 탭에서 1~16 변경).

## 구조
- LLM 은 섹션(코드 진행 + 멜로디)과 form 만 JSON 으로 생성, Arranger 가 목표 길이(1/3/5/8/12분)에 맞춰 전개.
- 스케일/코드/진행 청취는 LLM 없이 로컬에서 즉시 재생.

## 테스트
    swift test
    KEYSCORE_LIVE=1 swift test --filter OpenRouterLiveTests   # 실제 API 호출
