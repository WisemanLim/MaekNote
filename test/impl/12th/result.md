# 12th 결과 — 요약 템플릿 개선

- 판정: **PASS** · 2026-11-02

| id | 결과 | 근거 |
|----|------|------|
| E12-01~05 | PASS | test/summary/summary_test.dart |
| E12-06 | PASS | integration_test/summarize_test.dart (logs/it-summarize.txt) |

## 템플릿 근거 (웹 조사)
- 회의록: 개요(일시·참석자) · 안건별 논의 · 결정사항 · 액션 아이템(할 일·담당자·기한) · 미결/다음 회의 — Atlassian, Asana, Slack, Fyxer 템플릿 공통 요소
- 강의노트: 코넬 노트(노트·단서 질문·요약) — University of Portland, University of Calgary 안내서
- 인터뷰: 개요·대상 · 주제 · 인용 · 시사점 · 후속 조치 — usercall, dscout
- 문맥/간단: 배경 → 핵심 → 결론(CQC), TL;DR — slite, datamarks
- 출처 URL 은 templates.json `_sources`.

## 실측 (E12-06, Qwen2.5 0.5B)
- 회의록(ko) 1.2초 / 강의노트(ko) 0.6초 / 회의록(en) 0.1초
- 모든 항목이 원문 구간과 연결(round 3 이후 @null 0건)
- 한계: 0.5B 는 원문 문장을 그대로 옮기는 경향, 한국어 녹음 → English 요약 불가(“None”) — T1 이상 권장

## 회차
- round 1: 0.5B 가 지침의 형식 기호("안건: 논의 요지")·시스템 문장을 그대로 출력, "미정"만 있는 항목 (logs/it-summarize-r1.txt) → 지침을 문장형으로 바꾸고 베낀 항목·자리표시 단어 필터
- round 2: 출력 예시 문구 변형 베끼기, 근거 없는 항목 시간 연결 실패 다수(조사 때문에 단어 불일치), 영어에서 제목+지침 통째 출력 (logs/it-summarize-r2.txt) → 예시 줄 제거, 글자 2-gram 매칭, 지침 포함 항목 제거 → PASS
- 시험 코드: 지침 문구 변경에 따라 기대값 갱신, 통합 E2E 에 템플릿 provider 주입 누락 수정
- 전체 앱 E2E(en/ko) 재실행은 13th 에서 수행(같은 회기에 창 위치 복원 코드가 추가됨)
