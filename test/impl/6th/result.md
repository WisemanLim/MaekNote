# 6th 결과 — Epic 6 요약

- 판정: **PASS** · 2026-11-02 · macOS 26.6.2 (Apple Silicon, Metal)

| id | 결과 | 근거 |
|----|------|------|
| E6-01~09 | PASS | test/summary/summary_test.dart |
| E6-10 | PASS | integration_test/summarize_test.dart (logs/it-summarize.txt) |

## 실측 (E6-10)
- 다운로드 Qwen2.5 0.5B Q4_K_M(491MB) 20초(첫 회), 이후 캐시
- 회의록 0.7초 / 간단 요약 0.2초 (3구간 입력)
- 출력 예 (round 2):
  ```
  ## 안건
  - 세일 시작 계획 [S0]
  - 마케팅 예산 결정 [S1]
  - 신규 세용 [S2]
  ## 결정사항
  - 10% 늘리기로 결정한 마케팅 예산 [S1]
  ```
- 0.5B(T0)는 품질 한계(전사 오인식 그대로 반영, 담당자 근거 번호 오류). T1 이상 권장.

## 회차
- round 1: E6-10 실패 — 0.5B 모델이 전사본을 그대로 반복(logs/it-summarize-r1.txt) → 프롬프트를 "자료 먼저 · 지시+형식 예시 마지막" 구조로 변경 → PASS (logs/it-summarize-r2.txt)
- round 2: 간단 요약에서 같은 항목 반복 → 파서에서 중복 제거
- round 3: E6-09 실패 — 전사 탭이 새로 열릴 때 일시정지 상태면 강조가 안 됨(실제 버그) → 마운트 직후 현재 위치로 강조 계산 + 시험의 semantics handle 정리 → PASS
