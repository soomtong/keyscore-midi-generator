# MIDI 파일 내보내기 (2026-10-19)

## 배경
생성해서 전개한 곡을 DAW 나 다른 시퀀서로 가져갈 수 있게 Standard MIDI File 로 저장한다.
청취 탭의 스케일/코드/패턴 프리뷰는 대상이 아니다. 계획은 서브 에이전트 검토를 거쳐 수정 후 승인됐다.

## 결정

### SMF 1.0, Format 1, 480 PPQ
- MidiFile.data(_:trackNames:beatsPerBar:) 는 Song 을 Data 로 바꾸는 순수 함수다. 파일 입출력은 AppModel 이 한다.
- 트랙 0 은 컨덕터: 곡 제목(FF 03), 박자(FF 58, 기본 4/4), 템포(FF 51). 모든 트랙은 FF 2F 00 으로 끝나고,
  End of Track 은 마지막 이벤트와 곡 끝(totalBeats) 중 늦은 쪽에 둔다 (곡 끝 쉼표가 남도록).
- Note Off 는 0x8n, 세기 64. running status 는 쓰지 않는다 (유효하고 단순하다).

### 트랙은 파트가 아니라 채널 단위
- NoteEvent 는 채널만 갖고, 채널은 사용자가 겹치게 고를 수 있다. 파트 태그를 넣으면 Equatable 비교(autoReplayIfNeeded)와
  모든 생성 경로를 건드리게 되므로 채널 단위로 나누고, 트랙 이름만 파트에서 가져온다.
- 트랙 이름은 전개에 실제로 쓴 설정(arrangedWith)에서 꺼진 파트(Second Part, Rhythm 이 Off)를 빼고 만든다.
  같은 채널의 파트는 "Chords + Bass" 처럼 잇는다.

### 같은 (채널, 음높이) 가 겹치면 앞 음을 다음 음 시작에서 끊는다
- 실시간 송신에서도 뒤 음의 Off 가 앞 음을 끊으므로 들리는 소리와 같다. Note On/Off 가 중첩되지 않아 어떤 리더도 같은 해석을 한다.
- 같은 tick 에 같은 음이 두 번 시작하면(크래시 동시 타격 등) 센 쪽만 남긴다. 같은 tick 에서는 Off 가 먼저다.

### 파일은 영구 산출물이라 송신보다 엄격하게 거른다
- 음높이 0...127 밖, 시작이 음수이거나 유한하지 않은 이벤트는 버린다. 세기는 1...127.
- bpm 이 유한하지 않거나 0 이하이면 템포는 120 BPM. VLQ 는 0x0FFFFFFF 로 자른다 (최대 곡도 100만 tick 남짓).

### 내보내는 곡은 마지막으로 전개한 곡 그대로
- Arranger.build 는 멜로디 세기를 무작위로 정하므로 내보낼 때 다시 전개하면 들은 곡과 달라진다. buildSong 에서 arrangedSong 을 남긴다.
- arrangedSong 은 관찰되는 프로퍼티다. 메뉴/버튼 비활성 상태가 이 값으로 갱신된다.

### 저장 패널은 async begin
- NSSavePanel.begin() 을 메인 액터 Task 에서 await 한다. runModal 은 중첩 런루프 동안 Task.sleep 기반 타이머 동작이 모호해서 피했다.
- 앱은 샌드박스가 없으므로(ad-hoc 서명) entitlement 나 security-scoped bookmark 는 필요 없다.

## 생략한 것
- Key signature(FF 59): Song 에 키 정보가 없고, 모드·블루스·홀톤 스케일은 장조/단조로 표현되지 않는다. 선택 meta 라 규격 위반이 아니다.
- Program Change: 외부 악기에서 음색을 고르는 앱이다. 드럼은 GM 관례대로 10번 채널(기본값)이면 그대로 맞는다.

## 검증
- 테스트 안의 작은 SMF 리더로 청크 길이, End of Track, Note On/Off 짝과 비중첩을 실제 Arranger.build 산출물(모든 코드 패턴 × 리듬 × 두 번째 파트)에 대해 확인한다.
- AudioToolbox MusicSequenceFileLoadData 로 독립적으로 읽어 노트 수와 템포를 비교한다. 이 API 는 컨덕터 트랙을 tempo track 으로 옮기므로 트랙 수는 단언하지 않는다.
