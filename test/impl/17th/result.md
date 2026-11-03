# 17th 결과 — 전사 속도 · 백그라운드 전사 (R9)

- 판정: **PASS**
- 일시 2026-11-03 · macOS 26.6.2 · Flutter 3.41.9

| id | 결과 | 근거 |
|----|------|------|
| E17-01 | PASS | test/transcribe/transcribe_test.dart — tempo 0.8, (80,4000)·(4800,9600), 길이 16000 |
| E17-02 | PASS | 같은 파일 — 100% 그대로, `sttTempoOf('30')`=0.5·`'abc'`=0.8 |
| E17-03 | PASS | logs/it-transcribe.txt — `DECODE tempo=0.8 24.57s`, 100%/80% 둘 다 3문장·마지막 끝 19680/19661ms(원래 시간)·키워드 인식 |
| E17-04 | PASS | test/shell/note_panel_test.dart — 패널 닫힘·재생 그대로·배지 60%·부분 문장 숨김 · screens/*/04a-transcribing-background.png |
| E17-05 | PASS | note_panel_test · logs/it-app-flow-en/ko.txt `WINDOW_OPEN 737` · screens/*/05-panel-opened.png |
| E17-06 | PASS | note_panel_test — music 재생 유지, '전사 완료: meeting' → 보기 → meeting·패널 |
| E17-07 | PASS | make test 100건(17th 시점) · app_flow en/ko PASS |
| E17-08 | PASS | 18th 와 함께 dist 재생성 (18th/logs/dist-ls.txt) |

## 실측 (whisper-tiny, 19.7초 합성 회의)
| 속도 | 늘린 길이 | 전사 시간 | 인식 오류 |
|------|-----------|-----------|-----------|
| 100% | 19.67초 | 572ms | 5곳 |
| 80% | 24.57초 | 671ms | 5곳 |

깨끗한 합성 음성에서는 인식 차이 없음 — 빠른 발화·잡음 녹음용 설정. 기본값은 요청대로 80%.

## 회차
- round 1: `af=lavfi=[atempo]` 로 늦추자 디코딩 실패 — media_kit 의 FFmpeg 에 atempo 없음(`equalizer`·`aresample` 만) → mpv `speed` + 내장 `scaletempo2`
- round 2: 화면 캡처가 시험 앱이 아닌, 같은 시각 사용자가 띄운 MaekNote 창을 찍음(첫 장부터 737px) → 해당 캡처 삭제, 시험 전부터 떠 있던 앱 창은 제외하도록 캡처 방식 수정 후 재실행. 시험 DB 는 별도 폴더(`it_app/`)라 사용자 데이터 영향 없음
