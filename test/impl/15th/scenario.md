# 15th 시나리오 — 정리 · 플랫폼별 설치 이미지 (R7)

| id | 시험 | 기대 |
|----|------|------|
| E15-01 | `make clean` | `build/`·`.dart_tool/`·Pods·Gradle 캐시 삭제, `dist/` 유지 |
| E15-02 | `make dist` (macOS 호스트) | `dist/` 에 macOS dmg · iOS ipa · Android apk/aab |
| E15-03 | dmg 검증 | `hdiutil verify` VALID, `maeknote.app` + `Applications` 링크, 복사한 앱 실행 시 창 표시 |
| E15-04 | Android 산출물 | ABI별 APK(arm64-v8a, x86_64) + AAB, 32bit 라이브러리 없음 |
| E15-05 | `make dist-linux-docker` | `MaekNote-<ver>-linux-<arch>.tar.gz` (bundle + .desktop) |
| E15-06 | Linux 실행 (깨끗한 Ubuntu 24.04 컨테이너, Xvfb, 키링 없음) | 런타임 패키지 설치 후 25초 동안 종료 없이 실행, 앱 DB 생성 |
| E15-07 | 회귀 | `make test` PASS (키링 없음 시험 1건 추가) |
| E15-08 | 문서 | README(한/영) 설치 이미지·Make 타깃·문제 해결, DEPLOY-PROD-GUIDE.md, PRD R7 |
