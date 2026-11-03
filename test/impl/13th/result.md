# 13th 결과 — 마지막 상태로 시작

- 판정: **PASS** (전체 화면 흐름 E2E 1건은 화면 잠금으로 미실행 — 아래 비고)
- 일시 2026-11-02 · macOS 26.6.2

| id | 결과 | 근거 |
|----|------|------|
| E13-01~03 | PASS | test/shell/window_state_test.dart |
| E13-04~05 | PASS | integration_test/window_state_test.dart (logs/it-window_state.txt: `SAVED`/`RESTORED` 260,180,737,574) |
| E13-06 | PASS | logs/window-restore.txt — `X=300 Y=200 W=737 H=600`, `X=800 Y=400 W=322 H=574`, 화면 밖 → `X=1520 Y=483`(기본) |
| E13-07 | PASS | logs/window-restore.txt — `X=300 Y=200 W=737 H=574`, 종료 후 `window.notePanel=true`, `general.lastPositionMs=12000` |
| E13-08 | PASS (부분) | make test 89건 PASS, 통합 player·transcribe·summarize·window_state PASS. app_flow(en/ko) 는 비고 참고 |

## 구현
- `lib/core/window_state.dart`: 창 이동·크기 변경이 멈추면(0.4초) `window.frame` 저장, 시작 시 제목줄이 연결된 화면 안에 있을 때만 복원, 시작 직후 실제 위치를 한 번 저장.
- 노트 패널 열림 상태 `window.notePanel` 저장 → 복원된 창이 737pt 이상일 때만 패널을 연 상태로 시작.
- 재생 파일·위치는 기존 PlaybackMemory(설정 '마지막 재생 파일과 위치 저장', 기본 켬)로 일시정지 상태 복원.
- macOS 자체 창 복원(`isRestorable`)은 계속 끔 — 앱이 직접 복원.

## 회차
- round 1: AppleScript(손쉬운 사용)로 창을 옮기는 실제 검증이 창을 찾지 못함(-1719) → DB 에 마지막 위치를 넣고 재실행해 CGWindowList 로 실측하는 방식 + 통합 시험(window_manager) 으로 변경
- round 2: 화면 밖 값으로 시작한 뒤 저장값이 갱신되지 않음 → 시작 직후 실제 위치를 한 번 저장
- 12th 의 전체 흐름 재실행 중 한 번 멈춤(시험 도구 연결 오류 "Cannot close sink while adding stream", logs 12th/it-app-flow-en.txt) — 이후 실행에서 재현 안 됨

## 비고 (환경)
- 23:5x 이후 **화면 잠금**(`CGSSessionScreenIsLocked=1`) 상태: 창 크기 애니메이션이 진행되지 않고 화면 캡처도 불가 → app_flow(en/ko) 는 `WINDOW_OPEN 322` 에서 실패(logs/it-all.txt). 11th 에서 잠금 해제 상태로 같은 단계 PASS.
- 화면 잠금 해제 후 재실행: `make test-integration` (또는 `flutter test integration_test/app_flow_test.dart -d macos --dart-define=IT_LANG=ko`).
