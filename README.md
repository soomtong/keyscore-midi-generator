# KeyScore MIDI Generator

macOS 전용. OpenRouter LLM 으로 멜로디/코드 섹션을 만들고, CoreMIDI 가상 소스 "KeyScore" 로 Omnisphere 등 가상악기에 송신한다.

## 실행
    swift run KeyScore            # 개발용
    Scripts/bundle.sh             # build/KeyScore.app (아이콘 포함)

- API key: 환경변수 OPENROUTER_API_KEY 또는 설정(⌘,)에서 입력(Keychain 저장).
- 모델: 설정에서 저가 모델 프리셋(Claude Haiku 5.5, GPT-6 Luna, DeepSeek, GLM, Qwen)을 고르거나 ID 를 직접 입력. 환경변수 OPENROUTER_MODEL 이 있으면 우선.
- Omnisphere: Settings → MIDI 입력에서 "KeyScore" 선택. 기본 채널은 Melody 1, Chord 2, Bass 3 (설정에서 1~16 변경).
- 상단 디스플레이 아이콘: MIDI 출력(노트가 나갈 때 깜빡임), 서스테인 페달, 자동 재생, API key 상태. 마우스를 올리면 설명이 나온다.

## 구조
- LLM 은 섹션(코드 진행 + 멜로디)과 form 만 JSON 으로 생성, Arranger 가 목표 길이(1/3/5/8/12분)에 맞춰 전개.
- 스케일/코드/진행/멜로디 패턴 청취는 LLM 없이 로컬에서 즉시 재생.

## 단축키
메뉴바(재생 / 청취 / 곡 설정)에 모두 표시된다. 평문 키는 텍스트 입력 중에는 동작하지 않는다. 한글 입력기에서도 동작한다.

| 동작 | 키 |
|---|---|
| 재생/정지 | Space |
| 반복 | ⌥L |
| 곡 생성 / Randomize / Randomize + 청취 옵션 | ⌘G / ⌘R / ⇧⌘R |
| 설정 패널 | ⌘, (또는 상단 ⚙) |
| 하단 단축키 패널 열기/닫기 | ⌘/ (Help ▸ 단축키 안내, 패널 우측 상단 ✕) |
| 탭: 곡 생성 / 청취 | ⌘1 / ⌘2 |
| 스케일 / 코드 / 패턴(코드 진행) / 멜로디 듣기 | S / C / F / G |
| 서스테인 페달 | Tab 을 누르는 동안 (⌥P 로 고정) |
| 스케일 / 코드 종류 / 코드 진행: 다음 선택 | ⇧S / ⇧C / ⇧F |
| 스케일 / 코드 종류 / 코드 진행: 이전 선택 | ⌥⇧S / ⌥⇧C / ⌥⇧F |
| 템포 −/+ (Shift 는 5) | H / L (← / →) |
| Key +/− 반음 | K / J (↑ / ↓) |
| Scale 이전/다음 | [ / ] |
| 복잡도 (Triad · 7th · 9th/sus · 11th/13th · Altered) | 1 – 5 |
| 곡 길이 | , / . |
| 코드 패턴 다음 / 이전 | A / ⇧A |
| 멜로디 패턴 다음 / 이전 | M / ⇧M |

청취 옵션(kornflake 의 Audition 옵션 차용): Sequential/Together(⌘3), Descending(⌘D), Up & down(⇧⌘D), 2 Octaves(⌥⌘D),
Legato(⌥G), 코드 위/아래 확장(⌘U/⇧⌘U, ⌘B/⇧⌘B), 옥타브(⌥⌘↑/↓), 음 길이(⌘=/⌘-), 진행 간격(Rate), 자동 재생(⌥A).

## 테스트
    swift test
    KEYSCORE_LIVE=1 swift test --filter OpenRouterLiveTests   # 실제 API 호출
