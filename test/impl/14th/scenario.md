# 14th 시나리오 — 13th 재검증 (화면 잠금 해제 후 전체 통합 시험)

13th 에서 화면 잠금으로 실행하지 못한 전체 화면 흐름 E2E 를 다시 실행한다. 코드 변경 없음.

| id | 시험 | 기대 |
|----|------|------|
| E14-01 | `make test-integration` (player·transcribe·summarize·app_flow(en)·window_state 순차) | 5개 파일 모두 PASS |
| E14-02 | app_flow en: 노트 패널 열기/닫기 | `WINDOW_OPEN 737×574`, `WINDOW_CLOSED 322×574` |
| E14-03 | `flutter test integration_test/app_flow_test.dart -d macos --dart-define=IT_LANG=ko` | PASS, 화면 단계 05~15 통과 |
| E14-04 | window_state | `SAVED` = `RESTORED` |
