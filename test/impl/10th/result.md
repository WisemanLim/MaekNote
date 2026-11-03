# 10th 결과 — UI 다국어

- 판정: **PASS** · 2026-11-02 · macOS 26.6.2

| id | 결과 | 근거 |
|----|------|------|
| E10-01~06 | PASS | test/i18n_test.dart |
| E10-07 | PASS | logs/make-test.txt (총 77건) |
| E10-08 | PASS | logs/it-app-flow-en.txt, it-app-flow-ko.txt, screens/en, screens/ko |
| E10-09 | PASS | logs/it-all.txt |

## 구현
- 언어셋: `assets/i18n/<언어코드>.json` (평면 키, `_name` = 언어 자신의 이름). 162개 키 × en/ko.
- 확장: assets/i18n 에 파일 추가(재빌드) 또는 앱 데이터 폴더 `i18n/<코드>.json`(재빌드 없이, 같은 코드면 키 단위 덮어쓰기). 설정 > 일반 > 앱 언어 목록에 자동 표시.
- 기본 English. 없는 키는 English → 키 이름. Material 기본 위젯은 Flutter 가 지원하는 언어만 따르고 나머지는 English.
- 서비스 오류는 문장 대신 키(`AppError`)로 전달, 화면에서 번역. 전사 오류는 DB 에 키로 저장.

## 회차
- round 1: 시험 6건 실패 — 위변조 시험이 오류 문장 대신 키를 받도록 바뀜, 설정 시험에 언어셋 provider 미주입 (시험 코드 수정)
- round 2: E10-02 오탐 — 설정 저장 키 상수(`settings_repo.dart`)를 언어셋 키로 인식 → 스캔 제외

## 범위 밖 (의도적으로 번역하지 않음)
- 요약 내용: 요약 출력 언어는 별도 설정(설정 > 요약 > 출력 언어, 기본 한국어)을 따름. 모델이 섹션 제목을 쓰지 않을 때의 기본 제목('요약')도 내용으로 취급.
- LLM 프롬프트(한국어), 개발자용 오류(`UnimplementedError`), 모델 이름.
