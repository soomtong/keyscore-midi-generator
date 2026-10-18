# 동시성 모델과 MIDI 타이밍 설계 (2026-10-18)

## 배경
Swift 6 언어 모드로 올리면서 UI 상태(AppModel), 네트워크(OpenRouterClient), 실시간 송신(MidiPlayer)의
격리 경계를 정리했다. 외부 악기로 신호를 보내는 앱이므로 송신 지연과 지터를 가장 우선으로 본다.

## 결정

### MidiPlayer 는 actor 가 아니라 전용 serial DispatchQueue 를 유지한다
- actor 는 협력 스레드 풀에서 실행되어 우선순위와 깨어나는 시점을 보장하지 못한다.
  CoreMIDI 송신은 `qos: .userInteractive` 큐에서 `DispatchSourceTimer(flags: .strict)` 로 깨운다.
- 외부에서 보이는 API(play/stop/setPedal/setLoop)는 모두 큐에 enqueue 만 하므로 어느 스레드에서 불러도 안전하다.
  이 때문에 `@unchecked Sendable` 을 붙이고, 큐 밖에서 상태를 읽지 않는다는 규칙을 코드 주석으로 남겼다.
- 콜백(onProgress/onStop/onActivity)은 큐에서 불리며, AppModel 이 `Task { @MainActor in }` 로 메인에 올린다.

### 1 ms 폴링 대신 다음 이벤트 시각에 맞춘 one-shot 타이머
- 이전: 재생 중 1 ms 마다 깨어나 (초당 1000회) 큐를 스캔. 유휴 상태에서도 CPU 를 쓰고, 이벤트 시각이 1 ms 격자로 양자화됐다.
- 이후: 다음 메시지 시각과 다음 진행 보고 시각(50 ms) 중 빠른 쪽에 타이머를 걸고, 실행 후 다시 건다.
  깨어나는 횟수는 이벤트 수에 비례하고, 지터는 스케줄링 지연만 남는다.
- CoreMIDI 타임스탬프 선행 송신(lookahead)은 쓰지 않는다. 타임스탬프를 존중하는 수신기와 그렇지 않은 수신기가 섞여 있고,
  정지 시 보내는 Note Off 가 선행 송신된 Note On 보다 먼저 처리되어 음이 걸릴 수 있기 때문이다.

### AppModel 은 ObservableObject 대신 @Observable
- `@ObservedObject` 는 어느 프로퍼티가 바뀌어도 ContentView 전체를 다시 그린다. 재생 중 position 이 초당 20회 바뀌므로
  1000줄짜리 뷰가 초당 20회 재평가됐다. `@Observable` 은 실제로 읽은 프로퍼티가 바뀐 뷰만 다시 그린다.
- 자동 재생 디바운스는 Combine 대신 `Task.sleep` 과 취소로 구현했다 (메인 액터 격리가 컴파일러에 보인다).

### LLM 출력은 신뢰하지 않는다
- 파싱 단계에서 수치는 유한성 검사와 범위 클램프를 거친다. 특히 음높이는 0...127 로 접어 둔다.
  이전에는 `while p > 60 { p -= 12 }` 식의 접기가 있어, 거대한 정수 하나로 앱이 멈출 수 있었다.
- 섹션 수와 form 길이에도 상한을 둔다 (전개 알고리즘이 섹션 수의 제곱에 비례).

### API key
- 환경변수로 받은 키는 Keychain 에 쓰지 않는다. 사용자가 설정에서 입력한 값만, 이전에 저장한 값과 다를 때만 저장한다.
