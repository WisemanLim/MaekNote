# 14th 결과 — 13th 재검증

- 판정: **PASS**
- 일시 2026-11-03 · macOS 26.6.2 · 화면 잠금 해제 상태

| id | 결과 | 근거 |
|----|------|------|
| E14-01 | PASS | logs/it-all-en.txt — 5개 파일 모두 `All tests passed!` |
| E14-02 | PASS | logs/it-all-en.txt — `WINDOW_OPEN 737.0x574.0`, `WINDOW_CLOSED 322.0x574.0` |
| E14-03 | PASS | logs/it-app-flow-ko.txt — SHOT 05~15, `00:38 +1: All tests passed!` |
| E14-04 | PASS | logs/it-all-en.txt — `SAVED`/`RESTORED` 260,180,737,574 |

## 비고
- 매 실행 시 `Failed to foreground app; open returned 1` 경고가 출력되나 시험 결과와 무관(flutter 도구가 앱을 앞으로 가져오지 못했다는 안내, 시험은 계속 진행되어 PASS).
- 13th 실패(`WINDOW_OPEN 322`) 원인이 화면 잠금이었음을 확인 — 코드 수정 없이 PASS.
