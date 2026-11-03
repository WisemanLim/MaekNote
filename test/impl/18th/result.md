# 18th 결과 — 요약 클립보드 복사 (R10) + 끌어다 놓기 강제 종료 신고 조사

- 판정: **PASS**
- 일시 2026-11-03 · macOS 26.6.2 · Flutter 3.41.9

| id | 결과 | 근거 |
|----|------|------|
| E18-01 | PASS | test/export/copy_summary_test.dart — Markdown 정확히 일치 |
| E18-02 | PASS | 같은 파일 — 클립보드 `# weekly\n\n## 회의록…`, 알림 표시 |
| E18-03 | PASS | 같은 파일 — 항목 비활성, 복사 안 됨 |
| E18-04 | PASS | logs/make-test.txt |
| E18-05 | PASS | logs/dist-ls.txt · sha256.txt |

## 신고: "구동 중 추가로 음원을 drag&drop 하면 강제 종료"
| 확인 | 결과 |
|------|------|
| 크래시 보고서 | 12:13(PID 96625) mpv `m_config_cache_from_shadow` assert · 12:17(PID 49641) sqlite3 함수 안에서 주소 0 — 둘 다 `flutter run` 으로 띄운 Debug 앱, 각각 시험이 같은 Debug 앱 번들을 다시 빌드·실행하던 시각 |
| 끌어다 놓기 부하 (혼자) | integration_test/drop_test.dart — 재생 + 10분 파일 백그라운드 전사 중 11개·폴더·중복 반복 놓기: 4회 연속 PASS (logs/it-drop-1~4.txt) |
| 장시간 (혼자) | `IT_HOLD=150` — 150초 동안 놓기·전사·재생 48회 PASS, 크래시 없음 (logs/it-control-A-alone.txt) |
| 다른 시험 앱 빌드·실행과 겹침 | 같은 부하 중 window_state 시험 빌드·실행 → 그 시각(13:01:13) 같은 mpv assert 로 강제 종료 재현 (logs/it-interference-A/B.txt, 보고서 maeknote-2026-11-03-130115.ips) |
| 결론 | 끌어다 놓기 코드 문제 아님 — 실행 중인 Debug 앱 옆에서 같은 앱 번들을 재빌드·실행한 것이 원인. `make test-integration` 이 Debug 앱 실행 중이면 거부하도록 수정. 설치본에는 해당 없음 |

## 함께 고친 것
- 조사 중 발견: 디코더가 mpv 의 비치명적 오류("Error decoding audio." — 깨진 프레임 하나)를 치명적으로 처리해 전사 전체가 실패 → 파일을 열지 못한 경우(1초 후에도 길이 0)만 실패. 이어 붙인 9분 51초 MP3: 오류 30여 회에도 3.4초에 끝까지 디코딩, 739초(÷0.8) WAV
- 사용자 터미널의 Dart 예외("The PlayerService sending notification was…") 는 앞부분이 없어 원인 문구 미확인 — 같은 조건의 시험에서는 재현되지 않음

## 회차
- round 1: 부하 시험 자체 오류(runAsync 중첩) → 시험 수정
- round 2: 20초 표본은 놓기보다 먼저 전사가 끝남 → MP3 프레임을 이어 붙인 10분 파일
- round 3: 그 파일에서 '디코딩 실패' → 위 디코더 수정
- round 4: 한 번 시험 도구가 loading 단계에서 멈춤(앱 CPU 0%, 시험 코드 시작 전) → 재실행 4회 모두 정상, 도구 쪽 일시 문제로 기록
