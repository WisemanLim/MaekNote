# dev-env 결과 / result — maeknote (flutter-app)

- 일시: 2026-11-02 · 호스트: macOS 26.6.2 (arm64) · Flutter 3.41.9 / Dart 3.11.5 · Xcode 27.2
- **판정: PASS** (조건부 — 아래 비고)

| id | 명령 | 결과 | 로그 |
|----|------|------|------|
| ENV-01 | `make preflight` | PASS (Android 라이선스 미승인 경고 `[!]`) | logs/preflight.txt |
| ENV-02 | `make setup` | PASS | logs/setup.txt |
| ENV-03 | local 실행 빌드 `flutter build macos --debug --dart-define-from-file=.env.local` | PASS | logs/local-macos.txt |
| ENV-04 | `make test` (flutter test + analyze) | PASS (1 test, No issues) | logs/make-test.txt |
| ENV-05 | prod 빌드 `flutter build apk --debug` / `flutter build ios --no-codesign` (.env.prod) | PASS | logs/prod-apk.txt, logs/prod-ios.txt |

## 회차 / rounds
- round 1: ENV-03 macOS 빌드 실패 — `MACOSX_DEPLOYMENT_TARGET 10.15` (Xcode 27 지원 범위 12.0~) → Podfile·pbxproj·post_install 12.0 → PASS
- round 1: ENV-04 실패 — `flutter create` 기본 `widget_test.dart` 의 `MyApp` 부재 + analyze const 경고 → 테스트 교체·`dart fix` → PASS
- round 2: ENV-05 iOS 실패 — `IPHONEOS_DEPLOYMENT_TARGET 13.0` (지원 범위 15.0~) → 15.0 으로 동일 수정 → PASS

## 비고
- Android 라이선스: `flutter doctor --android-licenses` 사용자 실행 필요(빌드는 통과).
- Windows/Linux 빌드는 macOS 호스트에서 불가 → CI 매트릭스(windows-latest/ubuntu-latest)로 검증 예정.
- `make prod-build` 는 서명 필요(AAB/IPA) → 서명 없는 동등 빌드로 대체.
