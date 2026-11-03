# 7th 결과 — Epic 7 클라우드·내보내기

- 판정: **PASS** · 2026-11-02 · 회차 1 (재시도 없음)

| id | 결과 | 근거 |
|----|------|------|
| E7-01~10 | PASS | test/cloud/cloud_export_test.dart (MockClient) |

## 비고
- Dart 공식 Anthropic SDK 가 없어 Messages API 를 HTTP 로 직접 호출(claude-api 스킬 규격 확인).
- 실제 클라우드 호출은 사용자 API 키가 필요 → MANUAL: 설정 > 클라우드에서 동의 후 키 입력 → 요약 생성 → 모델 표시가 `cloud:…` 인지 확인.
- 전사(STT)는 항상 온디바이스. 클라우드는 요약에만 사용 (PRD F6 범위 내 결정).
- 저장 대화상자(FilePicker.saveFile) 동작은 MANUAL.
