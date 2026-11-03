# 16th 결과 — VOX 방식 헤더 · 끌어다 놓기 · 글씨 축소 · 설정 팝업 (R8)

- 판정: **PASS**
- 일시 2026-11-03 · macOS 26.6.2 · Flutter 3.41.9

| id | 결과 | 근거 |
|----|------|------|
| E16-01 | PASS | test/shell/vox_ui_test.dart · screens/*/04-playlist.png (제목 오른쪽 `0:19`) |
| E16-02 | PASS | test/widget_test.dart 호버 2건 · app_flow 6) 실제 마우스 이동 후 EQ 누름 · screens/*/09a-controls-hover.png |
| E16-03 | PASS | test/player/player_test.dart 2건 · vox_ui_test 드롭(채널 메시지 → Playlist·컬렉션 항목) |
| E16-04 | PASS | vox_ui_test(bodyMedium 12) · screens/*/04-playlist.png (VOX 처럼 한 줄 행) |
| E16-05 | PASS | vox_ui_test · i18n_test(닫기) · app_flow 8) Dialog 확인 · screens/*/11-settings-general.png |
| E16-06 | PASS | vox_ui_test (130% → 1.3, 명조 → Times New Roman, 저장) |
| E16-07 | PASS | logs/make-test.txt 98건 · logs/it-app-flow-en.txt·ko.txt (WINDOW 737/322, 화면 16장씩) |
| E16-08 | PASS | logs/dist-ls.txt 6개 · logs/dmg-smoke.txt(실행·창) · logs/linux-smoke.txt(실행 유지) |

## 구현
- 헤더: 폴더명 · 제목 + **전체 시간(같은 줄)** · 얇은 진행선. 시크바 + 반복·셔플·볼륨·EQ·출력은 `HoverReveal`(lib/features/shell/main_screen.dart) — 가리키면 펼침, 벗어나고 0.4초 뒤 닫힘, 터치는 헤더 누름, EQ·출력 패널 중 유지, 닫히면 포커스·스크린리더 제외.
- 끌어다 놓기: `MediaDropZone`(desktop_drop) — Playlist, 컬렉션 목록(놓은 항목 강조·추가), 열린 컬렉션. 폴더 재귀·확장자 거름(`mediaPathsFrom`), `LibraryRepo.importTo`. macOS 샌드박스 보안 범위 북마크 열고 닫음.
- 글씨: 테마 전체 축소(목록 13/11, 제목 15, 아이콘 18, 행 약 36px), 목록 한 줄(제목 + 흐린 출처). 촘촘한 간격은 데스크톱만(휴대폰 44pt 터치 영역 유지 — PRD §7 접근성).
- 설정: `showSettingsDialog` 팝업(최대 520×640), `/settings` 경로 삭제, 탭 아이콘 16·글씨 11, 일반 > 화면: 글꼴(시스템·고딕·명조·고정폭, OS 글꼴 순서대로) · 글자 크기(85~130%, OS 크기에 곱함).

## 회차
- round 1: 화면 캡처에서 목록이 두 줄(제목/출처)로 VOX 보다 성김 → 한 줄 행으로 변경 후 en/ko 재실행
- round 2: 새 위젯 시험이 멈춤 — `testWidgets` 안 실제 파일 복사 → `tester.runAsync`
- round 3: `make dist` Android 실패 `Could not find method kotlin()` (desktop_drop 0.8.0 Gradle) → 0.8.4 는 connectivity_plus 충돌, 0.9 는 Dart 3.13 필요 → `^0.7.0`(0.7.1) 고정, 전체 재시험·재빌드 (실패 로그 logs/dist-all-round1-fail.txt)

## 미검증
- 실제 OS 끌어다 놓기(Finder·탐색기에서 마우스로) — 채널 메시지 흉내로 Dart 쪽 경로 전체만 확인
- 휴대폰 실기기에서 헤더 누름 동작·터치 영역
