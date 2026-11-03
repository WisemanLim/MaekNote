# DEPLOY-PROD-GUIDE — MaekNote 설치 이미지 · 배포

> MaekNote 는 서버가 없는 온디바이스 앱이다. "운영 배포" = 플랫폼별 설치 이미지를 만들어 서명하고 스토어·다운로드 페이지에 올리는 것.
> 이 문서의 명령은 모두 `Makefile` 타겟으로 실행한다. 실제 서명 키·계정은 저장소에 넣지 않는다.

## 1. 한눈에

| 플랫폼 | 명령 (빌드 호스트) | 산출물 (`dist/`) | 서명 상태 (기본) | 배포 전 필요한 것 |
|--------|-------------------|------------------|------------------|-------------------|
| macOS | `make dist-macos` (macOS) | `MaekNote-<ver>-macos-arm64.dmg` | ad-hoc | Developer ID 서명 + 공증 (§3-1) |
| iOS | `make dist-ios` (macOS) | `MaekNote-<ver>-ios-unsigned.ipa` | 없음 | 배포 인증서·프로비저닝 → `make prod-build` 또는 재서명 (§3-2) |
| Android | `make dist-android` (macOS·Linux·Windows) | `MaekNote-<ver>-android-arm64-v8a.apk`, `-x86_64.apk`, `-android.aab` | `android/key.properties` 없으면 디버그 키 | 업로드 키 (§3-3) |
| Linux | `make dist-linux` (Linux) · `make dist-linux-docker` (Docker 가 있는 아무 호스트) | `MaekNote-<ver>-linux-<arch>.tar.gz` | 해당 없음 | — |
| Windows | `make dist-windows` (Windows) · CI | `MaekNote-<ver>-windows-x64.zip` | 없음 | (선택) 코드 서명 인증서 (§3-4) |

- `make dist` = 현재 호스트에서 가능한 것 전부 (macOS: macOS·iOS·Android / Linux: Linux·Android / Windows: Windows).
- 전 플랫폼 한 번에: `v*` 태그 push → `.github/workflows/release.yml` 이 macOS·Linux·Windows 러너에서 빌드해 GitHub Release 에 첨부.
- 버전 = `pubspec.yaml` 의 `version` (`0.1.0+1` → 파일명 `0.1.0`, 빌드 번호 `1`). 배포마다 올린다.
- 앱은 `.env.prod` 로 빌드된다 (`--dart-define-from-file`). `.env.prod` 는 커밋하지 않는다 — 형식은 `.env.example`.

## 2. 정리

| 명령 | 지우는 것 | 남기는 것 |
|------|-----------|-----------|
| `make clean` | `build/`, `.dart_tool/`, `ios/Pods`, `macos/Pods`, `android/.gradle`, `.DS_Store` | `dist/`, 소스, 사용자 데이터 |
| `make distclean` | 위 + `dist/` | 소스, 사용자 데이터 |

내려받은 모델·노트(앱 데이터 폴더)는 어느 명령도 지우지 않는다. 처음 빌드는 의존성을 다시 받으므로 시간이 걸린다.

## 3. 서명 · 배포

### 3-1. macOS (.dmg)
1. Apple Developer Program 의 **Developer ID Application** 인증서를 키체인에 설치.
2. `make dist-macos` 후 서명 → 공증 → 스테이플:
   ```bash
   codesign --deep --force --options runtime --timestamp \
     --entitlements macos/Runner/Release.entitlements \
     --sign "Developer ID Application: <팀 이름> (<TEAM_ID>)" build/dmg/maeknote.app
   hdiutil create -volname MaekNote -srcfolder build/dmg -fs HFS+ -format UDZO -ov dist/MaekNote-<ver>-macos-arm64.dmg
   xcrun notarytool submit dist/MaekNote-<ver>-macos-arm64.dmg --keychain-profile <프로필> --wait
   xcrun stapler staple dist/MaekNote-<ver>-macos-arm64.dmg
   ```
3. 서명·공증 없이 배포하면 Gatekeeper 가 막는다. 내부 시험용은 Finder 에서 우클릭 → 열기.
4. Mac App Store 는 샌드박스 엔타이틀먼트(이미 사용 중)와 App Store 인증서·`com.example` 이 아닌 번들 ID 가 필요 (§5).

### 3-2. iOS (.ipa)
- `dist-ios` 는 서명 없는 ipa — 기기 설치·TestFlight 불가, 재서명 입력용.
- 정식: Xcode 에서 Runner 의 Team·번들 ID 를 배포 계정으로 바꾼 뒤 `make prod-build` (`flutter build ipa`) → `make deploy` (fastlane `ios beta` → TestFlight).
- fastlane 인증은 App Store Connect API 키를 환경변수로 (`APP_STORE_CONNECT_API_KEY_*`) — 파일로 커밋 금지.

### 3-3. Android (.apk / .aab)
1. 업로드 키 생성 (한 번, 안전한 곳에 백업):
   ```bash
   keytool -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. `android/key.properties` (비커밋 — `.gitignore` 등록됨):
   ```properties
   storeFile=upload-keystore.jks
   storePassword=<비밀번호>
   keyAlias=upload
   keyPassword=<비밀번호>
   ```
3. `make dist-android` — 파일이 있으면 업로드 키, 없으면 디버그 키로 서명 (`android/app/build.gradle.kts`).
4. Play 콘솔 업로드는 `.aab`, 직접 배포는 `.apk` — 휴대폰·태블릿은 `arm64-v8a`, `x86_64` 는 에뮬레이터·크롬북용. 전체 ABI 단일 APK 는 ~360MB 라 나눴다. 32bit(armeabi-v7a) 기기는 지원하지 않는다(llamadart 라이브러리 없음 → `build.gradle.kts` `packaging` 에서 제외). `make deploy` = fastlane `android beta` (internal 트랙, 서비스 계정 JSON 은 환경변수로).

### 3-4. Windows (.zip) · Linux (.tar.gz)
- Windows: zip 을 풀고 `maeknote.exe` 실행. SmartScreen 경고를 없애려면 코드 서명 인증서로 `signtool sign /fd sha256 /tr <타임스탬프 URL> /td sha256 maeknote.exe` 후 압축. 설치 프로그램(MSIX·Inno Setup)은 미구현.
- Linux: `tar xzf MaekNote-<ver>-linux-<arch>.tar.gz && ./maeknote/maeknote`. 실행 PC 에 `libmpv2`·`libgtk-3-0`·`libsecret-1-0`·`libgles2`·`libegl1` 필요 (Ubuntu 24.04: `sudo apt install libmpv2 libgtk-3-0 libsecret-1-0 libgles2 libegl1`). 키링(gnome-keyring 등)이 없으면 클라우드 API 키를 저장할 수 없다 — 앱은 키 없이 시작하고 온디바이스 기능은 그대로 동작. 메뉴 등록은 `maeknote/maeknote.desktop` 을 `~/.local/share/applications/` 에 복사하고 `Exec=` 를 실제 경로로.
- `dist-linux-docker` 는 **Docker 호스트의 CPU 아키텍처**용만 만든다 (Apple Silicon → `linux-arm64`). x64 는 Linux x64 호스트나 CI.

### 3-5. CI Secrets (release.yml)
| Secret | 내용 | 없을 때 |
|--------|------|---------|
| `ENV_PROD` | `.env.prod` 전체 내용 | `.env.example` 로 빌드 |
| `ANDROID_KEYSTORE_B64` | `base64 -i upload-keystore.jks` | 디버그 키 서명 |
| `ANDROID_KEY_PROPERTIES` | key.properties 내용 (`storeFile=upload-keystore.jks`) | 디버그 키 서명 |

macOS 공증·iOS 배포 서명·Windows 코드 서명은 CI 에 넣지 않았다 — 인증서를 확보한 뒤 §3-1·3-2·3-4 단계를 워크플로에 추가.

## 4. 배포 전 점검

1. `make test` PASS, `make test-integration` PASS (macOS, 화면 잠금 해제).
2. `pubspec.yaml` 버전 올림 → `make distclean && make dist`.
3. 각 이미지를 깨끗한 기기/VM 에 설치해 실행: 파일 열기 → 재생 → 최소형 모델 다운로드 → 전사 → 요약.
4. 서명 확인: macOS `spctl -a -vv -t install <dmg>`, Android `apksigner verify --print-certs <apk>`.
5. `v<ver>` 태그 push → release 워크플로 결과·첨부 파일 확인.

## 5. 출시 전 바꿔야 하는 값 (사용자 결정)

| 항목 | 현재 | 위치 |
|------|------|------|
| 번들 ID / applicationId | `com.example.maeknote` (스토어 거부됨) | `android/app/build.gradle.kts`, `ios/`·`macos/` Xcode 설정, `linux/CMakeLists.txt` |
| 표시 이름 | `maeknote` / `Maeknote` | `macos/Runner/Configs/AppInfo.xcconfig`, `ios/Runner/Info.plist`, `AndroidManifest.xml` |
| 저작권 문구 | `com.example` | `AppInfo.xcconfig` |
| 앱 아이콘 | Flutter 기본 | 플랫폼별 아이콘 리소스 |

## 6. 문제 해결

- **Linux 빌드(Docker) `Failed to find any of [ld.lld, ld]` / `[llvm-ar, ar]`, CMake `CMAKE_MAKE_PROGRAM is not set`**: llamadart·sherpa 네이티브 빌드 훅이 clang 옆의 lld·llvm-ar·make 를 찾음 → `packaging/linux/Dockerfile` 에 `build-essential lld llvm` (반영됨). Linux 호스트에서 직접 빌드할 때도 같은 패키지 필요.
- **Linux 실행 즉시 종료 `Couldn't open libGLESv2.so.2`**: `libgles2 libegl1` 설치.
- **Linux 에서 키링이 없으면 시작 중 멈춤** `PlatformException(Libsecret error …)`: 시작 시 키 읽기 실패를 무시하도록 수정(`CloudKeys.load`, 반영됨).

- **macOS universal 빌드 실패** `Binary …/FlutterMacOS does not contain architectures "arm64 x86_64"`: Xcode 27 의 `lipo -verify_arch` 가 아키텍처를 여러 개 받지 않음(`requires exactly one input file`) → Flutter 3.41.9 실패. `dist-macos` 는 기본 `MACOS_ARCHS=arm64` (Apple Silicon 전용). Intel 지원은 수정된 Flutter 로 올린 뒤 `make dist-macos MACOS_ARCHS="arm64 x86_64"`. PATH 에 lipo 대체 스크립트를 두는 방법은 Xcode 가 툴체인 경로를 앞에 두어 효과 없음(확인함).
- **Android 빌드 전 라이선스**: `flutter doctor --android-licenses` 로 SDK 라이선스 수락.
