# MIDI 송신 배칭, LLM 입력 상한, 관찰 범위 (2026-10-19)

## 배경
성능·보안·Swift 6 이디엄 관점으로 전체 코드를 검토했다. 외부 악기로 신호를 보내는 앱이므로
송신 경로의 시스템 호출 수와 메인 스레드가 멈출 수 있는 경로를 우선으로 봤다.

## 결정

### 같은 tick 의 메시지는 MIDIEventList 하나로 보낸다
- 이전: 메시지마다 MIDIEventList 를 초기화하고 MIDIReceivedEventList 를 불렀다. 화음 6음 + 베이스 + 드럼이
  같은 순간에 나가면 MIDIServer 왕복이 8번이었다.
- 이후: MidiPlayer 가 힙에 둔 송신 버퍼(outbox)에 모았다가 tick 끝에 한 번 보낸다. 패킷 하나는 64 워드까지라
  그보다 많으면 먼저 보내고 새 패킷을 시작하므로 순서는 유지된다.
- MIDIEventListAdd 는 자리가 없으면 NULL 을 돌려주지만 Swift 에는 non-optional 포인터로 들어온다.
  NULL 비교 대신 워드 수를 직접 센다.
- 정지 시퀀스(페달 해제 → Note Off → All Notes Off)도 한 패킷으로 나간다.

### 송신 전에 값을 한 번 더 자른다
- 음높이가 0...127 밖인 이벤트는 보내지 않는다 (이전에는 UInt8(clamping:) 으로 128 이상이 255 가 되어
  데이터 바이트에 상위 비트가 섞일 수 있었다). 데이터 바이트는 & 0x7F 로 마스크한다.
- Note On 세기는 1 이상으로 올린다. 세기 0 인 Note On 은 MIDI 에서 Note Off 와 같아 active 집합과 어긋난다.
- 길이 0 인 곡을 반복 재생하면 타이머가 쉬지 않고 돌았다. 메시지를 다 보낸 뒤 endSeconds 가 0 이하이면 그냥 끝낸다.

### 리프 배치는 멜로디를 음높이별 구간표로 정리한 뒤 이분 탐색한다
- 이전: 리프 음마다 멜로디 전체를 훑어 충돌을 검사했다. LLM 이 파트 상한(2048 음)까지 채운 섹션은 한 번에
  2.8 초가 걸렸고, 곡 전체로는 섹션 수 × 반복 횟수만큼 곱해져 메인 스레드가 수십 초 멈출 수 있었다.
- 이후: SoundingMap 이 음높이별 울림 구간을 합쳐 정렬해 두고, 충돌 검사는 음 하나에 이분 탐색 세 번이다.
  같은 입력이 26 ms 에 끝난다. 마디별 멜로디 시작 여부도 미리 계산한다.
- 반개구간 [start, end) 의미는 그대로다 (끝점이 맞닿기만 하면 충돌이 아니다).

### 초당 20회 바뀌는 값은 작은 뷰에서만 읽는다
- @Observable 은 body 를 평가한 View 단위로 의존성을 기록한다. ContentView.body 안의 computed property
  (lcd, progressLine, statusIcons)에서 position 과 midiActive 를 읽으면 본문 전체가 초당 20회 다시 평가됐다.
- TimeField, ProgressLine, StatusIcons 를 별도 View 로 분리하고, ArrangementLane 은 모델을 받아 자기 body 에서
  position 을 읽는다. 이제 재생 중에는 이 네 뷰만 다시 그린다.

### 네트워크 세션은 ephemeral
- URLCache 는 응답과 함께 요청(Authorization 헤더 포함)을 ~/Library/Caches 에 적을 수 있다.
  OpenRouterClient 의 기본 세션을 디스크 캐시·쿠키 없는 ephemeral 구성으로 바꾸고 요청에도 캐시 무시를 지정했다.

### Keychain 항목은 이 기기에서만
- kSecAttrAccessibleWhenUnlockedThisDeviceOnly 를 지정해 iCloud Keychain 동기화와 백업 복원으로 옮겨지지 않게 했다.

## 검토했지만 바꾸지 않은 것
- MidiPlayer 를 actor 로: 이전 결정 유지. 실시간 송신은 전용 큐가 맞다.
- 실시간 스레드 정책(thread_policy_set): 지금 지터가 1 ms 안이라 필요하면 그때 한다.
- Arranger.build 를 메인 밖으로: 최대 길이 곡(5만 이벤트)도 디버그 빌드에서 18 ms 라 한 번의 멈춤으로 충분히 짧다.
- Arranger.expandForm 의 접미사 합 미리 계산: 최악 0.03 ms 라 의미 없다.
- Keychain.load 를 init 에서 동기 호출: 앱 수명에 한 번이고 값이 작다.
