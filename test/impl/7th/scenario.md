# 7th — Epic 7 클라우드(선택) · 내보내기 (F6, F7)

| id | 목적 | 입력 | 기대 | 우선 |
|----|------|------|------|------|
| E7-01 | Anthropic 요청 규격 | 기본 모델 | POST /v1/messages, x-api-key, anthropic-version 2026-10-21, fallbacks "default" + beta 헤더, temperature 미전송, text 블록만 결합 | P0 |
| E7-02 | 거절·오류 | stop_reason refusal / 401 | CloudException | P0 |
| E7-03 | fallback 미지원 모델 | claude-haiku-5-5 | beta 헤더·fallbacks 미전송 | P1 |
| E7-04 | OpenAI 호환 | 게이트웨이 URL(끝 / 포함) | /chat/completions, Bearer 키 | P1 |
| E7-05 | 전송 관문 | 정책 OFF→ON | OFF 차단·기록 0, ON 기록 1 | P0 |
| E7-06 | AC6 | 클라우드 OFF(기본), 키 있음 | 온디바이스 엔진 사용, 외부 전송 0건 | P0 |
| E7-07 | 설정 미완료 | ON + 키 없음 / OpenAI 모델명 없음 | 온디바이스 유지 → 모델명 지정 시 클라우드 | P1 |
| E7-08 | Anthropic 선택 | ON + 키 | claude-opus-5-5 엔진 | P1 |
| E7-09 | 키 보관 (COMPLIANCE 규제대상) | 키 저장·재로드·삭제 | 보안 저장소에만, settings DB 미기록 | P0 |
| E7-10 | 내보내기 | SRT·VTT·TXT·MD | 형식별 시간 표기·요약 포함 | P0 |
