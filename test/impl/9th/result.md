# 9th 결과 — 데스크톱 창 크기 = VOX

- 판정: **PASS** · 2026-11-02 · macOS 26.6.2

| id | 결과 | 근거 |
|----|------|------|
| E9-01 | PASS | logs/window-size.txt (`VOX 322 574` / `maeknote 322 574`), screens/00-launch.png |
| E9-02 | PASS | `isRestorable = false` 적용 후 재실행 322×574 |
| E9-03 | PASS (설정값) | `minSize 322×480` — 수동 축소 확인은 MANUAL |
| E9-04 | 설정 완료 / 실행 MANUAL | windows/runner/main.cpp, linux/runner/my_application.cc |
| E9-05 | PASS | test/app_layout_test.dart (322×546 추가, 71건 PASS) |
| E9-06 | PASS | logs/it-app-flow.txt, screens/00~14 (모두 322×574 px) |
| E9-07 | PASS | logs/it-all.txt |

## 회차
- round 1: E9-01 실패 — awake 시점엔 322×574 이지만 macOS 창 상태 복원이 이전 크기(351×632)로 덮어씀 → `isRestorable = false` → PASS
- round 2: E9-06 — 322px 폭에서 설정 탭 '클라우드'·'저장공간·개인정보'가 가로 스크롤 영역 밖이라 시험 탭이 빗나감(시험 코드 문제, 앱은 스크롤로 접근 가능) → `ensureVisible` 후 탭 → PASS (logs/it-app-flow-r1.txt)
- round 3: E9-07 — 8th 의 일괄 실행(logs 8th/it-all.txt)은 두 번째 파일부터 "Unable to start the app on the device"(데스크톱 앱 재기동 한계) → Make 타깃을 파일별 순차 실행으로 변경 → PASS

## 화면 검토 메모 (사용자 시험 참고, 수정은 별도 요청 시)
- 노트(전사/요약) 영역 높이가 약 250px 로 좁음 — 요약 항목 3~4개만 보임.
- 설정 상단 탭 7개 중 4~5개만 보이고 나머지는 가로 스크롤.
- 요약 탭의 유형 칩 5개 중 3개만 보이고 나머지는 가로 스크롤, 모델명·생성 시각이 두 줄로 줄바꿈.
- 900px 이상으로 창을 넓히면 노트가 오른쪽 패널로 함께 표시됨(기존 동작 유지).
