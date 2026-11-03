# maeknote — flutter-app (wise-vibe wds-scaffold)
# 모드: local | prod  — .env.<mode> 를 --dart-define-from-file 로 주입 (서버 compose 는 별도 서버 프로파일)
.PHONY: help preflight setup local-all local-stop ios android macos windows linux test test-integration local-build prod-build prod-build-desktop deploy clean distclean dist dist-macos dist-ios dist-android dist-linux dist-linux-docker dist-windows
DEVICE ?=          # -d ios | -d android | -d <id>
VERSION := $(shell sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
DIST    := dist
NAME    := MaekNote-$(VERSION)
HOST    := $(shell uname -s | sed -e 's/MINGW.*/Windows/' -e 's/MSYS.*/Windows/')
help:        ## 타겟 목록
	@grep -hE '^[a-z][a-z-]*:.*## ' $(MAKEFILE_LIST) | sed -E 's/:[^#]*##/\t/' | awk -F'\t' '{printf "  %-18s %s\n", $$1, $$2}'
preflight:   ## 툴체인 점검 (flutter doctor)
	flutter --version && flutter doctor
setup:       ## 의존성 설치
	flutter pub get
local-all:   ## [local] 시뮬레이터/에뮬레이터 실행 (.env.local)
	flutter run $(DEVICE) --dart-define-from-file=.env.local
local-stop:  ## [local] 시뮬레이터/에뮬레이터 종료
	xcrun simctl shutdown all 2>/dev/null || true; adb emu kill 2>/dev/null || true
ios:         ## iOS 시뮬레이터 실행 (.env.local)
	flutter run -d ios --dart-define-from-file=.env.local
android:     ## Android 에뮬레이터 실행 (.env.local)
	flutter run -d android --dart-define-from-file=.env.local
macos:       ## macOS 데스크톱 실행 (.env.local)
	flutter run -d macos --dart-define-from-file=.env.local
windows:     ## Windows 데스크톱 실행 (.env.local, Windows 호스트)
	flutter run -d windows --dart-define-from-file=.env.local
linux:       ## Linux 데스크톱 실행 (.env.local, Linux 호스트)
	flutter run -d linux --dart-define-from-file=.env.local
test:        ## flutter test + analyze
	flutter test && flutter analyze
test-integration: ## 통합 시험 (macOS 호스트, 실제 모델 다운로드 ~600MB 포함)
	@# 같은 Debug 앱(make macos 등)이 떠 있으면 시험 빌드·실행이 그 앱을 죽인다(mpv assert) → 먼저 종료
	@if pgrep -f 'Build/Products/Debug/maeknote.app/Contents/MacOS/maeknote' >/dev/null; then \
	  echo "실행 중인 Debug MaekNote 를 종료한 뒤 다시 실행하세요 (같은 앱 번들을 다시 빌드·실행하면 실행 중인 앱이 강제 종료됨)"; exit 1; fi
	@# 데스크톱은 한 실행에서 앱 재기동이 실패하므로 파일별로 순차 실행
	for f in integration_test/*_test.dart; do flutter test $$f -d macos || exit 1; done
local-build: ## [local] 디버그 APK (.env.local)
	flutter build apk --debug --dart-define-from-file=.env.local
prod-build:  ## [prod] AAB + IPA (.env.prod)
	flutter build appbundle --dart-define-from-file=.env.prod && flutter build ipa --dart-define-from-file=.env.prod
prod-build-desktop: ## [prod] 현재 호스트 OS 데스크톱 릴리스 빌드 (.env.prod)
	FLUTTER_XCODE_ARCHS="$(MACOS_ARCHS)" flutter build $$(uname -s | sed -e 's/Darwin/macos/' -e 's/Linux/linux/' -e 's/MINGW.*\|MSYS.*/windows/') --release --dart-define-from-file=.env.prod
deploy:      ## 스토어 업로드 (fastlane android beta / ios beta)
	cd fastlane && fastlane android beta   # iOS: fastlane ios beta

# ----- 정리 / 설치 이미지 (DEPLOY-PROD-GUIDE.md) -----
clean:       ## 빌드 산출물·중간파일 제거 (build, .dart_tool, Pods, Gradle 캐시) — dist/ 는 유지
	flutter clean
	rm -rf ios/Pods macos/Pods android/.gradle android/.kotlin
	find . -name .DS_Store -not -path './.git/*' -delete
distclean: clean ## clean + dist/ 설치 이미지까지 제거
	rm -rf $(DIST)
dist:        ## 현재 호스트에서 만들 수 있는 설치 이미지 전부 → dist/
ifeq ($(HOST),Darwin)
	$(MAKE) dist-macos dist-ios dist-android
else ifeq ($(HOST),Linux)
	$(MAKE) dist-linux dist-android
else
	$(MAKE) dist-windows
endif
	@ls -lh $(DIST)
MACOS_ARCHS ?= arm64
dist-macos:  ## [macOS] .app → .dmg (기본 arm64, ad-hoc 서명; 배포 서명·공증은 가이드)
	@# Flutter 3.41.9 + Xcode 27 lipo 에서 universal(arm64 x86_64) 빌드가 실패 → 기본 arm64 (가이드 §문제 해결)
	FLUTTER_XCODE_ARCHS="$(MACOS_ARCHS)" flutter build macos --release --dart-define-from-file=.env.prod
	rm -rf build/dmg && mkdir -p build/dmg $(DIST)
	cp -R build/macos/Build/Products/Release/maeknote.app build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "MaekNote" -srcfolder build/dmg -fs HFS+ -format UDZO -ov $(DIST)/$(NAME)-macos-$(subst $(eval) ,-,$(MACOS_ARCHS)).dmg
dist-ios:    ## [macOS] iOS 서명 없는 .ipa (배포 서명은 가이드 — prod-build 또는 재서명)
	flutter build ios --release --no-codesign --dart-define-from-file=.env.prod
	rm -rf build/ipa-unsigned && mkdir -p build/ipa-unsigned/Payload $(DIST)
	cp -R build/ios/iphoneos/Runner.app build/ipa-unsigned/Payload/
	cd build/ipa-unsigned && zip -qry ../../$(DIST)/$(NAME)-ios-unsigned.ipa Payload
dist-android: ## Android ABI별 .apk + .aab (android/key.properties 없으면 디버그 키 서명)
	@# 단일 APK(전체 ABI)는 ~360MB → ABI별로 나눈다. 32bit(armeabi-v7a)는 llamadart 라이브러리가 없어 요약이 안 되므로 제외
	flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64 --dart-define-from-file=.env.prod
	flutter build appbundle --release --target-platform android-arm64,android-x64 --dart-define-from-file=.env.prod
	mkdir -p $(DIST)
	for a in arm64-v8a x86_64; do cp build/app/outputs/flutter-apk/app-$$a-release.apk $(DIST)/$(NAME)-android-$$a.apk; done
	cp build/app/outputs/bundle/release/app-release.aab $(DIST)/$(NAME)-android.aab
dist-linux:  ## [Linux 호스트] 번들 → .tar.gz (+ .desktop)
	flutter build linux --release --dart-define-from-file=.env.prod
	$(eval ARCH := $(shell uname -m | sed -e 's/x86_64/x64/' -e 's/aarch64/arm64/'))
	rm -rf build/linux-pkg && mkdir -p build/linux-pkg $(DIST)
	cp -R build/linux/$(ARCH)/release/bundle build/linux-pkg/maeknote
	cp packaging/linux/maeknote.desktop build/linux-pkg/maeknote/
	tar -C build/linux-pkg -czf $(DIST)/$(NAME)-linux-$(ARCH).tar.gz maeknote
dist-linux-docker: ## [Docker] 호스트 아키텍처용 Linux .tar.gz 를 컨테이너에서 빌드
	docker build -f packaging/linux/Dockerfile --build-arg VERSION=$(VERSION) --output type=local,dest=$(DIST) .
dist-windows: ## [Windows 호스트] Release 폴더 → .zip
	flutter build windows --release --dart-define-from-file=.env.prod
	powershell -NoProfile -Command "New-Item -ItemType Directory -Force $(DIST) | Out-Null; Compress-Archive -Force -Path build/windows/x64/runner/Release/* -DestinationPath $(DIST)/$(NAME)-windows-x64.zip"
