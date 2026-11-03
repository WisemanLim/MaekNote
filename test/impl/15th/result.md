# 15th 결과 — 정리 · 플랫폼별 설치 이미지 (R7)

- 판정: **PASS** (Windows 는 Windows 호스트/release CI 필요 — 이 호스트에서 미실행)
- 일시 2026-11-03 · macOS 26.6.2 · Flutter 3.41.9 · Xcode 27.2 · Docker 29.9.2 (arm64)

| id | 결과 | 근거 |
|----|------|------|
| E15-01 | PASS | 처음 정리 13.7GB(build 7.5G + .dart_tool 6.2G). logs/make-clean.txt — 9.1GB 삭제, dist 718M·6개 유지 |
| E15-02 | PASS | logs/dist-all.txt, logs/dist-ls.txt, logs/sha256.txt |
| E15-03 | PASS | logs/dmg-smoke.txt — VALID, arm64, ad-hoc, 실행 창 737×574 @ (300,200) (마지막 상태 복원) |
| E15-04 | PASS | arm64-v8a 155MB · x86_64 160MB · aab 233MB (aab lib: arm64-v8a, x86_64 만) |
| E15-05 | PASS | logs/dist-linux-docker.txt — linux-arm64.tar.gz 92MB |
| E15-06 | PASS | logs/linux-smoke.txt — rc=124(시간 초과까지 실행 유지), maeknote.db 생성 |
| E15-07 | PASS | logs/make-test.txt — 90건, analyze 문제 없음 |
| E15-08 | PASS | README.md·README.en.md·DEPLOY-PROD-GUIDE.md·PRD v0.8 |

## 산출물 (`dist/`, 0.1.0)
| 파일 | 크기 |
|------|------|
| MaekNote-0.1.0-macos-arm64.dmg | 31M |
| MaekNote-0.1.0-ios-unsigned.ipa | 42M |
| MaekNote-0.1.0-android-arm64-v8a.apk | 155M |
| MaekNote-0.1.0-android-x86_64.apk | 160M |
| MaekNote-0.1.0-android.aab | 233M |
| MaekNote-0.1.0-linux-arm64.tar.gz | 92M |

## 회차
- round 1: macOS release `does not contain architectures "arm64 x86_64"` — 원인: Xcode 27 `lipo -verify_arch` 가 아키텍처 여러 개를 거부(`requires exactly one input file`). PATH lipo 대체 스크립트(일반 PATH, `FLUTTER_XCODE_PATH`) 모두 Xcode 툴체인 경로가 앞서 효과 없음 → `FLUTTER_XCODE_ARCHS=arm64` 로 해결 (Apple Silicon 전용)
- round 2: Linux Docker `CMAKE_MAKE_PROGRAM is not set`, `Failed to find any of [ld.lld, ld]` → `build-essential lld`; 이어서 `[llvm-ar, ar]` → `llvm`
- round 3: 단일 APK 374MB → `--split-per-abi`; armeabi-v7a APK 에 llamadart 라이브러리 없음 → 32bit 제외(`--target-platform` + Gradle `packaging.jniLibs.excludes`; `abiFilters` 는 Flutter 플러그인이 덮어써 효과 없음)
- round 4: Linux 실행 `Couldn't open libGLESv2.so.2` → 런타임 패키지 `libgles2 libegl1` 문서화. 이어서 키링 없는 환경에서 `PlatformException(Libsecret error …)` 로 시작 중단 → `CloudKeys.load` 가 읽기 실패를 무시하도록 수정 + 시험 추가, 전체 이미지 재빌드

## 미검증
- Windows zip (Windows 호스트 또는 `.github/workflows/release.yml`)
- Linux x64 · 실제 데스크톱 세션, iOS·Android 기기 설치/실행 (연결된 기기 없음)
- 배포 서명(Developer ID·공증, iOS 배포, Android 업로드 키) — 인증서 없음, DEPLOY-PROD-GUIDE.md §3
