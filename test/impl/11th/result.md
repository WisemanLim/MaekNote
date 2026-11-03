# 11th 결과 — 오른쪽 노트 패널

- 판정: **PASS** · 2026-11-02 · macOS 26.6.2

| id | 결과 | 근거 |
|----|------|------|
| E11-01~03 | PASS | test/widget_test.dart (데스크톱 3건) |
| E11-04~06 | PASS | test/shell/note_panel_test.dart |
| E11-07 | PASS | logs/it-app-flow-en.txt, it-app-flow-ko.txt (`WINDOW_OPEN 737.0x574.0`, `WINDOW_CLOSED 322.0x574.0`), screens/en·ko |

## 구현
- `window_manager` 로 데스크톱 창 너비 조절 (`lib/core/window_sizer.dart`): 열기 737 (Image #8 비율: 322 + 415), 닫기 322. 모바일·태블릿은 기존 방식(탭 / 900px 이상 나란히).
- 전사를 시작하면 자동으로 패널이 열리고 해당 파일을 플레이어에 불러옴. 패널 왼쪽 위 ‹ 로 닫기.

## 회차
- round 1: 위젯 시험이 멈춤 — testWidgets 안의 실제 파일 복사를 runAsync 없이 대기(시험 코드)
- round 2: **실제 버그 2건** — 322px 에서 English 문구가 길어 넘침: 노트 헤더 "Cancel transcription" 버튼(32px), 재생목록 배지 "Transcribing 20%"(76px) → 아이콘 버튼·"⏳20%" 배지(전체 문구는 툴팁)
- round 3: E11-07 닫힘 측정이 창 애니메이션 도중(335px)에 읽힘 → 실제 창 크기가 목표에 닿을 때까지 확인 (logs/it-app-flow-en-r1.txt)
- round 4: 이전 실패 실행이 남긴 EQ 켜짐 상태로 토글이 반대 → 시험 시작 시 초기화 (logs/it-app-flow-en-r2.txt)
- 추가 보정: 볼륨 −/+ 숨김 기준을 창 폭 → 플레이어 칸 폭으로 (패널을 펼쳐도 322px 플레이어 유지)
