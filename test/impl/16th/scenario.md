# 16th 시나리오 — VOX 방식 헤더 · 끌어다 놓기 · 글씨 축소 · 설정 팝업 (R8, Image #9·#10)

| id | 요구 | 시험 | 기대 |
|----|------|------|------|
| E16-01 | 1. 전체 시간을 제목 옆 | vox_ui_test "total play time sits on the title row" | 헤더 안 `29:54` 가 제목과 같은 줄(세로 차 < 4px), 오른쪽 |
| E16-02 | 2. 제어줄 호버 슬라이드 | widget_test 호버 시험 · app_flow 6) 실제 마우스 이동 | 기본 높이 0·눌리지 않음 → 헤더를 가리키면 펼쳐짐 → 제어줄로 옮겨도 유지 → 벗어나고 0.4초 뒤 닫힘. EQ 패널 사용 중 유지 |
| E16-03 | 3. 끌어다 놓기 | player_test (폴더 펼침·확장자 거름, 컬렉션 추가) · vox_ui_test (desktop_drop 채널 메시지로 Playlist·컬렉션 항목에 놓기) | 재생 가능한 파일만 추가, 컬렉션 항목에 놓으면 그 컬렉션에도 |
| E16-04 | 4. 글씨 VOX 수준 | vox_ui_test 기본 bodyMedium 12 · 화면 캡처 | 목록 한 줄(제목 + 흐린 출처 + 길이), 제목 13 · 보조 11pt |
| E16-05 | 5. 설정 팝업 | vox_ui_test · i18n_test · app_flow 7)~8) | Dialog 로 열림, 뒤 화면 유지, 닫기(✕)로 복귀, 탭 아이콘 16 · 글씨 11 |
| E16-06 | 5. 글꼴·글자 크기 | vox_ui_test | 일반 > 화면: 130% → textScaler 1.3, 명조 → fontFamily 'Times New Roman', 설정 저장 |
| E16-07 | 회귀 | make test · app_flow en/ko (macOS 실기) | 모두 PASS, 창 322↔737 |
| E16-08 | 산출물 | make dist · dist-linux-docker | dmg·ipa·apk·aab·linux tar.gz 재생성 |
