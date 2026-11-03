# 4th 결과 — Epic 4 추론 코어 + 전사

- 판정: **PASS** · 2026-11-02 · macOS 26.6.2 (Apple Silicon)

| id | 결과 | 근거 |
|----|------|------|
| E4-01~04 | PASS | integration_test/transcribe_test.dart (logs/it-transcribe.txt) |
| E4-05~11 | PASS | test/transcribe/transcribe_test.dart (logs/make-test.txt) |

## 실측 (E4-01~03)
- 디코딩: mp3 19.67s, mp4 19.58s
- 다운로드: whisper-tiny + VAD 8초, 요청 4건
- 전사: 697ms (19.7초 음성, 실시간 대비 약 28배), 구간 3개
  - [134–5328] 이제는 세일을 시작하겠습니다. 첫 번째 안 꺼는 다음 분기 마케팅 예산입니다.
  - [6822–12880] 예사는 지난 분기보다 10% 늘리기로 결정했습니다. 담당자는 김팀장입니다.
  - [14406–19680] 두 번째 안건은 신규 세용입니다. 다음 주 금요일까지 공부를 올리겠습니다.
- tiny 모델 특성상 오인식 존재(회의→세일, 채용→세용) — 정확도 지표(WER)는 PRD §5 가정값, small 이상 권장.

## 회차
- round 1: analyze — 구독 리스트 제네릭 타입 오류 → `StreamSubscription<Object>` 로 수정
- round 2: 단위 시험 5건 실패 — 시험용 가짜 카탈로그의 STT 파일명이 규약(encoder/decoder/tokens)과 달랐음(시험 코드 수정) → PASS

## 비고
- 디코딩은 libmpv(FFmpeg 포함)의 `ao=pcm` 출력을 사용 → 5개 플랫폼 동일 코드. macOS 외 플랫폼은 MANUAL.
