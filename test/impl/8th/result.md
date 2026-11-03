# 8th 결과 — Epic 8 설정 화면 + 전체 앱 E2E

- 판정: **PASS** (E8-09 macOS 릴리스 빌드는 도구 체인 이슈로 제외 — 아래 비고)
- 일시 2026-11-02 · macOS 26.6.2 · Flutter 3.41.9 · Xcode 27.2

| id | 결과 | 근거 |
|----|------|------|
| E8-01~06 | PASS | test/settings/settings_test.dart |
| E8-07 | PASS | test/app_layout_test.dart |
| E8-08 | PASS | integration_test/app_flow_test.dart (logs/it-app-flow.txt, 35초), screens/01~14 |
| E8-09 | PASS (apk·ios·macOS debug) / 환경 이슈 (macOS release) | logs/build-apk.txt, build-ios.txt, build-macos-release.txt |

## 화면 (screens/)
01 빈 상태 · 02/03 모델(STT/LLM) · 04/05 재생목록(전사 배지) · 06 전사 탭 위치 추적 · 07 요약(회의록·시간 링크) · 08 요약→전사 이동 · 09 EQ(Voice Boost) · 10 출력 장치 · 11~14 설정

## 회차
- round 1: E8-08 시험 준비 오류(it_app 폴더 미생성) → 시험 코드 수정
- round 2: E8-08 에서 **휴대폰 폭 제어줄 23px overflow** 발견(실제 버그) → 420px 미만에서 볼륨 −/+ 숨김 (44pt 터치 영역 유지) + 회귀 시험 E8-07 추가 (logs/it-app-flow-r1.txt)
- round 3: E8-07 실패 — GoRouter 가 static 이라 앱 인스턴스 간 라우트 상태 공유 → 앱 상태 소유로 변경 → PASS
- round 4: Android 릴리스 매니페스트에 INTERNET 권한 누락(템플릿은 debug/profile 에만) → 추가 후 빌드 PASS

## 비고 (환경 이슈)
- `flutter build macos --release` 가 `release_unpack_macos ... does not contain architectures "arm64 x86_64"` 로 실패.
  빈 `flutter create` 앱도 동일하게 실패 → Flutter 3.41.9 + Xcode 27.2 도구 체인 문제(프로젝트 무관).
  대응: Flutter stable 업그레이드 후 재시도, 또는 Apple Silicon 전용 배포 시 Release ARCHS=arm64 지정(사용자 결정 필요).
- Windows/Linux 빌드·실행, iOS/Android 실기기 구동은 MANUAL (CI 매트릭스 + 실기기 확인).
