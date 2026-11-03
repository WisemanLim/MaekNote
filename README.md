# MaekNote — 멀티 플랫폼 녹음 전사·요약 플레이어

> English: [README.en.md](README.en.md) · 요구사항: [PRD.md](PRD.md) (추가 요구 이력 §8) · 규제/데이터 등급: [COMPLIANCE.md](COMPLIANCE.md) · 구현 계획표: [test/impl/PLAN.md](test/impl/PLAN.md)

VOX 스타일의 작은 플레이어에서 음성·영상 녹음을 재생하면서, **기기 안에서 돌아가는 모델**로 받아쓰기(전사)와
노트 요약(회의록 · 강의노트 · 인터뷰 요약 · 문맥 요약 · 간단한 요약)을 만드는 Flutter 앱입니다.
iOS · Android · macOS · Windows · Linux 를 하나의 코드로 빌드합니다.

## 주요 기능

| 기능 | 내용 | 구현 위치 |
|------|------|-----------|
| 플레이어 | 제목 옆 전체 재생 시간, 헤더를 가리키면 펼쳐지는 시크바·반복/셔플/볼륨·EQ·출력, 10밴드 EQ+프리셋(Voice Boost 등), 출력 장치 선택 | `lib/features/player`, `lib/features/shell/main_screen.dart`(`HoverReveal`) |
| 재생목록·컬렉션 | ＋ 또는 **끌어다 놓기**(파일·폴더, 데스크톱) — 컬렉션 항목·열린 컬렉션에 놓으면 그 컬렉션에도 추가 | `lib/features/library` |
| 전사 | 음성·영상 → 16kHz PCM(libmpv, **전사 속도** 기본 80% — mpv `scaletempo2` 로 음높이 유지한 채 늦춤) → Silero VAD 구간 분할 → Whisper(sherpa-onnx) 인식, 시간은 원래 재생 시간으로 환산. **백그라운드** 진행(진행률·취소), 완료 후 전사 화면에 표시 | `lib/features/transcribe` |
| 노트 > 전사 | 재생 위치에 맞춰 문장 강조·자동 스크롤, 문장을 누르면 그 시각부터 재생, 전문 검색(FTS5) | `transcript_view.dart` |
| 노트 > 요약 | 5종 템플릿(웹 조사 기반 섹션), 전사 정제 → 섹션별 작성, 항목마다 `[mm:ss]` 시간 링크 → 원문 이동 | `lib/features/summary`, `assets/summary/templates.json` |
| 화면 배치 | 왼쪽 VOX 크기 플레이어, 전사·요약 시 오른쪽으로 펼쳐지는 노트 패널 | `lib/features/shell`, `lib/core/window_sizer.dart` |
| 마지막 상태로 시작 | 창 위치·크기·노트 패널, 마지막 재생 파일·위치 복원 | `lib/core/window_state.dart`, `playback_memory.dart` |
| 모델 관리자 | 기기 메모리로 권장 단계(T0~T4), 이어받기 다운로드, SHA256 검증, 삭제·기본 지정, 큰 모델 경고 | `lib/features/models`, `assets/models/manifest.json` |
| 클라우드(선택) | 기본 OFF. 동의 후 OpenAI 호환 또는 Anthropic 으로 **요약만** 전송(전사는 항상 기기 안) | `lib/features/cloud` |
| 내보내기 | TXT · Markdown(요약 포함) · SRT · VTT 파일 저장, **요약 클립보드에 복사**(요약 탭에서 고른 유형, Markdown) | `lib/features/export` |
| 다국어 | 한국어·English 기본(기본값 English), 언어셋 JSON 으로 확장, 설정에서 즉시 전환 | `lib/core/i18n.dart`, `assets/i18n/` |
| 설정 | **팝업**으로 열림. 일반(언어·글꼴·글자 크기) · 오디오 · 모델 · 전사 · 요약 · 클라우드 · 저장공간·개인정보(외부 전송 기록) | `lib/features/settings` |
| 화면 밀도 | VOX 수준 글씨(목록 제목 13 · 보조 11pt)·아이콘 18pt, 데스크톱은 촘촘한 행 | `lib/core/theme.dart` |

## 사용 흐름

1. **＋** 로 음성·영상 파일 가져오기, 또는 데스크톱에서 파일·폴더를 Playlist/Collections 에 **끌어다 놓기** (앱 폴더로 복사되어 재시작 후에도 재생 가능)
   - 재생 제어: 제목 줄(헤더)에 마우스를 올리면 시크바·반복·셔플·볼륨·EQ·출력 줄이 아래로 펼쳐짐 (휴대폰은 헤더를 눌러 열고 닫음)
2. 항목 메뉴(⋮) > **전사하기** — 모델이 없으면 기기에 맞는 권장 모델과 크기·예상 처리 시간을 안내
3. 전사는 **백그라운드**로 진행 — 재생·화면은 그대로이고 목록 배지(⏳60%)와 전사 탭에 진행률만 보임. 끝나면 창이 오른쪽으로 넓어지며 **노트 패널**에 전체 전사가 열림(다른 파일을 재생 중이면 끊지 않고 '전사 완료 · 보기' 알림)
4. **전사** 탭: 재생 위치를 따라 문장이 강조됨, 문장을 누르면 그 위치로 이동
5. **요약** 탭: 유형 칩(회의록 등) 선택 → **생성** → 섹션별 항목의 `[mm:ss]` 를 누르면 전사 탭의 해당 구간으로 이동
6. 패널 왼쪽 위 ‹ 로 닫으면 VOX 크기로 돌아감. 공유 아이콘으로 TXT/MD/SRT/VTT 내보내기 또는 **요약 클립보드에 복사**(요약 탭에서 고른 유형의 최신 요약, Markdown — 없으면 비활성)

## 화면 배치

| 환경 | 배치 |
|------|------|
| 데스크톱 (macOS·Windows·Linux) | 첫 실행 창 = VOX 메인 창 실측 **322 × 574pt**(제목줄 포함, 최소 322 × 480). 노트 아이콘(≡) 또는 전사 완료 → 창이 **737pt** 로 넓어지며 왼쪽 플레이어 322pt + 오른쪽 노트 패널. 닫으면 322pt 로 복귀. 사용자가 이미 더 넓힌 창은 줄이지 않음 |
| 휴대폰 | 같은 구조를 전체 화면으로. 노트는 아이콘 탭으로 전환 |
| 태블릿 (900px 이상) | 플레이어와 노트를 나란히 |

플레이어 칸이 420px 보다 좁으면 볼륨 −/+ 버튼을 숨기고 슬라이더만 둡니다(44pt 터치 영역 유지).

**플레이어 헤더 (VOX 방식, R8)**

| 상태 | 보이는 것 |
|------|-----------|
| 기본 | 폴더명 · **제목 + 전체 재생 시간(같은 줄)** · 얇은 진행선 |
| 헤더를 가리킴 (휴대폰: 누름) | 아래로 슬라이드: 시크바(현재 위치/전체) + 반복·셔플·볼륨·EQ·출력. 벗어나고 0.4초 뒤 닫힘 |
| EQ·출력 패널 사용 중 | 제어줄 계속 열림 |

닫혀 있는 제어줄은 키보드 포커스·스크린리더에서도 숨깁니다.

**끌어다 놓기 (데스크톱)**: 재생목록 → 가져오기, 컬렉션 목록의 항목 위 → 가져오고 그 컬렉션에 추가(항목 강조 표시), 열린 컬렉션 → 그 컬렉션에 추가. 폴더는 하위 폴더까지 펼치고 재생 가능한 확장자만 받습니다. 이미 있는 파일은 다시 복사하지 않고 컬렉션에만 넣습니다.

**글씨·설정 (R8)**: 글씨·아이콘·행 높이를 VOX 수준으로 줄였습니다(목록 제목 13pt, 보조 11pt, 제목 15pt, 아이콘 18pt). 촘촘한 간격은 데스크톱에서만 쓰고 휴대폰은 44pt 터치 영역을 유지합니다. 설정은 화면을 바꾸지 않고 **팝업**으로 열리며(최대 520×640), 일반 > **화면**에서 글꼴(시스템 기본·고딕·명조·고정폭 — OS 글꼴을 순서대로 찾음)과 글자 크기(85·100·115·130%, OS 글자 크기에 곱함)를 고릅니다(`general.font`, `general.fontSize`).

## 전사 (속도 · 백그라운드)

| 항목 | 동작 |
|------|------|
| 전사 속도 | 설정 > 전사 > **전사 속도** (50·60·70·**80**·90·100%, 기본 80%, `transcribe.speed`). 디코딩 때 mpv 재생 속도를 늦추고 내장 `scaletempo2` 로 음높이를 유지 → 늘린 16kHz 음성을 인식 → 문장 시간·파일 길이 × 속도 = 원래 재생 시간 |
| 백그라운드 | 전사를 시작해도 재생 중인 파일·화면은 그대로. 목록 배지(⏳60%)와 전사 탭에 진행률만 표시하고 부분 문장은 보이지 않음 (DB 에는 계속 저장 — 취소·오류 시 남은 부분 표시) |
| 완료 | 그 파일이 현재 파일이거나 재생 중인 파일이 없으면 노트 패널(휴대폰: 노트 탭)에 전체 전사가 열림. 다른 파일을 재생 중이면 끊지 않고 **'전사 완료: 제목 · 보기'** 알림 |

실측 (macOS, whisper-tiny, 19.7초 한국어 회의 합성 음성, `integration_test/transcribe_test.dart`):

| 속도 | 늘린 길이 | 전사 시간 | 문장 시간 (원래 기준) | 인식 오류 |
|------|-----------|-----------|----------------------|-----------|
| 100% | 19.67초 | 572ms | 134–5328 · 6822–12880 · 14406–19680 | 5곳 |
| 80% | 24.57초 | 671ms | 312–5338 · 6814–12864 · 14418–19661 | 5곳 |

깨끗한 합성 음성에서는 차이가 없었습니다. 느린 속도는 빠른 발화·잡음이 있는 녹음에서 도움을 기대하는 설정입니다(처리 시간은 약 1/속도 배).

## 마지막 상태로 시작

| 항목 | 저장 시점 | 복원 | 저장 위치(설정 키) |
|------|-----------|------|--------------------|
| 창 위치·크기 (데스크톱) | 창 이동·크기 변경이 멈춘 뒤 0.4초, 시작 직후 1회 | 다음 실행 시 같은 위치·크기. 제목줄이 연결된 화면 안에 보이지 않으면(모니터 분리 등) 기본 위치 | `window.frame` = `x,y,w,h` |
| 노트 패널 (데스크톱) | 열고 닫을 때 | 복원된 창이 737pt 이상이면 열린 상태로 시작 | `window.notePanel` |
| 재생 파일·위치 | 재생 중 5초마다 | 마지막 파일을 **일시정지 상태로** 마지막 위치에 놓음 | `general.lastMediaId`, `general.lastPositionMs` |

재생 위치 복원은 설정 > 일반 > **마지막 재생 파일과 위치 저장**(기본 켬)으로 끌 수 있습니다.
macOS 자체 창 복원은 끄고(`isRestorable = false`) 앱이 직접 복원합니다.

## 요약 템플릿

| 유형 | 섹션 (웹 조사 기반) | 근거 |
|------|---------------------|------|
| 회의록 | 회의 개요 · 안건별 논의 · 결정사항 · 액션 아이템(누가·무엇을·언제까지) · 미결 사항·다음 회의 | Atlassian·Asana·Slack 회의록 템플릿 공통 요소 |
| 강의노트 | 주제·개요 · 핵심 개념·정의 · 주요 내용 · 복습 질문 · 요약 | 코넬 노트(노트·단서 질문·요약) |
| 인터뷰 요약 | 인터뷰 개요 · 핵심 주제 · 주요 질문과 답변 · 인상적인 발언 · 시사점·후속 조치 | 사용자 인터뷰 분석 템플릿 |
| 문맥 요약 | 배경·목적 · 흐름 · 핵심 내용 · 결론·시사점 | 배경→핵심→결론(CQC) |
| 간단한 요약 | 한 줄 요약(TL;DR) · 핵심 포인트 | TL;DR 관례 |

처리 순서
1. 긴 녹음(구간 묶음이 여러 개)이면 묶음마다 **정제 노트** 작성 — 문맥상 명백한 오인식 교정, 군더더기·반복 제거, 사람·숫자·날짜·결정·할 일 유지, 근거 줄 번호 `[S번호]` 유지
2. 템플릿 **섹션마다 따로** 작성(작은 모델도 구조를 지키도록) — 최대 항목 수, 근거 `[S번호]` 필수, 없으면 "없음"
3. 내용이 없는 섹션 생략, 프롬프트·지침을 베낀 항목과 "미정/TBD" 만 있는 항목 제거, 근거 번호가 없으면 글자 2-gram 겹침이 가장 큰 원문 구간에 연결

섹션 제목·지침·최대 항목 수·프롬프트(출력 언어별)와 출처 URL 은 `assets/summary/templates.json` 에 있습니다(수정 후 다시 빌드).
길이 설정(짧게/보통/자세히)은 항목 수를 0.5/1/1.5배로 조절합니다. 요약 **내용** 언어는 설정 > 요약 > 출력 언어(기본 한국어)를 따릅니다.
0.5B(T0) 모델은 원문 문장을 그대로 옮기는 경향이 있고 한국어 녹음을 English 로 요약하지 못합니다 — **T1 이상 권장**.

## 언어 (UI 다국어)

- 기본 언어는 **English**, 설정 > 일반 > **앱 언어**에서 바꿉니다(즉시 반영, 뒤로 가기 같은 기본 위젯 포함).
- 언어셋은 `assets/i18n/<언어코드>.json` (현재 179개 키). 키는 평면 구조, `_name` 은 목록에 보일 언어 이름, `{name}` 은 자리표시자:
  ```json
  { "_name": "日本語", "app.settings": "設定", "player.play": "再生" }
  ```
- 언어 추가: ① `assets/i18n/ja.json` 추가 후 다시 빌드(폴더 전체 등록됨) 또는 ② 재빌드 없이 앱 데이터 폴더 `i18n/ja.json` 에 두고 재시작(같은 코드면 키 단위로 덮어씀, 잘못된 JSON 은 무시).
- 없는 키는 English → 키 이름 순으로 대체. 기준 키 목록은 `assets/i18n/en.json`. 오류 메시지도 키로 전달되어 선택한 언어로 표시됩니다.

## 모델 단계 (manifest 기준, 메모리·속도는 추정값)

| 단계 | 대상 기기 (RAM) | 전사 (Whisper int8 ONNX) | 요약 (GGUF Q4_K_M) |
|------|-----------------|--------------------------|--------------------|
| T0 | ≤ 4GB | tiny 103MB · base 160MB | Qwen2.5 0.5B 469MB |
| T1 | ≤ 8GB | small 358MB | Qwen2.5 1.5B 1.0GB |
| T2 | ≤ 16GB | turbo 988MB · medium 902MB | Qwen3 4B 2507 2.3GB |
| T3 | ≤ 32GB | large-v3 1.7GB | Qwen2.5 7B 4.4GB |
| T4 | > 32GB | (large-v3) | Qwen2.5 14B 8.4GB |

모든 모델은 Hugging Face 에서 직접 받고(VAD 는 sherpa-onnx GitHub 릴리스), 라이선스는 MIT(Whisper·VAD) / Apache-2.0(Qwen) 입니다.

## 구조

```
lib/
├── main.dart · app.dart     # 시작(DB·manifest·언어셋·템플릿·기기 사양 로드, 창 복원) · 라우팅(/ , /settings)
├── core/
│   ├── db.dart              # SQLite + FTS5 마이그레이션
│   ├── i18n.dart            # 언어셋 로드·대체 규칙·AppError
│   ├── window_sizer.dart    # 노트 패널 열고 닫을 때 창 너비 322 ↔ 737
│   ├── window_state.dart    # 창 위치·크기 저장/복원
│   ├── net.dart             # 외부 전송 관문·기록
│   └── theme.dart · format.dart · providers.dart
└── features/
    ├── shell/      메인 화면(헤더·제어줄·아이콘 탭·오른쪽 패널)
    ├── library/    재생목록·컬렉션
    ├── player/     media_kit 엔진 · EQ(lavfi) · 출력 장치 · 재생 위치 기억
    ├── models/     manifest · 기기 단계 · 다운로드(Range 이어받기, SHA256)
    ├── transcribe/ PCM 디코딩 · sherpa-onnx(isolate) · 전사 저장/검색 · 노트 화면
    ├── summary/    템플릿 · 정제/섹션별 생성 · 출력 파싱/시간 연결 · llamadart
    ├── cloud/      OpenAI 호환 · Anthropic Messages API · OS 보안 저장소 키
    ├── export/     TXT/MD/SRT/VTT
    └── settings/   설정 저장소 · 설정 화면
assets/
├── models/manifest.json     # 모델 목록(URL·SHA256·크기·단계)
├── i18n/en.json · ko.json   # UI 언어셋
└── summary/templates.json   # 요약 템플릿·프롬프트·출처
```

데이터는 OS 앱 지원 폴더(`maeknote.db`, `media/`, `models/`, `tmp/`, 선택 `i18n/`)에 저장됩니다. API 키는 Keychain/Keystore/DPAPI/libsecret 에만 저장합니다.

## 사전 요구사항

- Flutter 3.38+ (검증: 3.41.9) / Dart 3.10+
- 최소 OS: iOS 16.4 · macOS 14.0 (llamadart 요구) · Android(Flutter 기본)
- Xcode(iOS·macOS), Android SDK(`flutter doctor --android-licenses` 승인 필요)
- Linux 빌드: `build-essential clang lld llvm cmake ninja-build pkg-config libgtk-3-dev libmpv-dev libsecret-1-dev libjsoncpp-dev` (또는 Docker 로 `make dist-linux-docker`)
- C/C++ 툴체인 불필요 — llama.cpp·sherpa-onnx·libmpv 는 미리 빌드된 바이너리를 받습니다(첫 빌드 시 네트워크 필요).

## 실행

```bash
make preflight                    # flutter doctor
make setup                        # flutter pub get
make macos                        # macOS 실행 (windows / linux / ios / android 동일)
make local-all DEVICE="-d macos"
```

## 환경 (빌드 플레이버)

| 키 | `.env.local` | `.env.prod` | 비고 |
|----|--------------|-------------|------|
| `APP_ENV` / `FLAVOR` | local | prod | `--dart-define-from-file` 로 주입 |
| `API_BASE_URL` | http://localhost:8000 | https://api.example | 스캐폴드 기본값. 현재 앱은 서버를 쓰지 않음 |

클라우드 API 키·모델은 env 파일이 아니라 앱 **설정 > 클라우드**에서 입력합니다.

## Make 타깃

| 타깃 | 설명 |
|------|------|
| `make help` | 타깃 목록 |
| `make preflight` / `make setup` | 툴체인 점검 / 의존성 설치 |
| `make local-all [DEVICE=…]` · `make local-stop` | 실행 / 시뮬레이터·에뮬레이터 종료 |
| `make ios` · `make android` · `make macos` · `make windows` · `make linux` | 플랫폼별 실행 |
| `make test` | 단위·위젯 시험 + analyze (103건) |
| `make test-integration` | macOS 통합 시험 6개 파일 순차 실행 — 전체 화면 흐름(app_flow)·끌어다 놓기 부하(drop: 재생+백그라운드 전사 중 반복 놓기)·실재생(player)·실요약(summarize)·실전사(transcribe)·창 위치(window_state). 첫 실행 시 모델 약 600MB 다운로드, **화면 잠금 해제 상태 필요**, `make macos` 로 띄운 Debug 앱이 있으면 거부 |
| `make local-build` / `make prod-build` | 디버그 APK / AAB+IPA (서명 필요) |
| `make prod-build-desktop` | 현재 호스트 OS 데스크톱 릴리스 빌드 (macOS 는 arm64) |
| `make deploy` | fastlane 스토어 업로드 |
| `make clean` / `make distclean` | 빌드 산출물·중간파일 제거 (`build/`, `.dart_tool/`, Pods, Gradle 캐시) / + `dist/` |
| `make dist` | 현재 호스트에서 만들 수 있는 설치 이미지 전부 → `dist/` |
| `make dist-macos` · `dist-ios` · `dist-android` · `dist-linux` · `dist-linux-docker` · `dist-windows` | 플랫폼별 설치 이미지 (아래 표) |

전체 화면 흐름을 한국어로: `flutter test integration_test/app_flow_test.dart -d macos --dart-define=IT_LANG=ko` (기본 English).
CI(`.github/workflows/ci.yml`): Android(analyze+test) · iOS · macOS · Windows · Linux 빌드 매트릭스.
릴리스(`.github/workflows/release.yml`): `v*` 태그 push → macOS·Linux·Windows 러너에서 `dist/` 생성 → GitHub Release 첨부.

## 설치 이미지 (배포)

서명·공증·스토어 업로드·CI Secrets 는 [DEPLOY-PROD-GUIDE.md](DEPLOY-PROD-GUIDE.md).

| 플랫폼 | 명령 (빌드 호스트) | `dist/` 산출물 (0.1.0 실측) | 기본 서명 |
|--------|-------------------|-----------------------------|-----------|
| macOS | `make dist-macos` (macOS) | `MaekNote-0.1.0-macos-arm64.dmg` (31MB) | ad-hoc (배포 전 Developer ID + 공증) |
| iOS | `make dist-ios` (macOS) | `MaekNote-0.1.0-ios-unsigned.ipa` (42MB) | 없음 (재서명 또는 `make prod-build`) |
| Android | `make dist-android` | `…-android-arm64-v8a.apk` (155MB) · `…-android-x86_64.apk` (160MB) · `…-android.aab` (233MB) | `android/key.properties` 없으면 디버그 키 |
| Linux | `make dist-linux` (Linux) · `make dist-linux-docker` (Docker) | `MaekNote-0.1.0-linux-arm64.tar.gz` (92MB, Docker on Apple Silicon) | — |
| Windows | `make dist-windows` (Windows) · release CI | `MaekNote-0.1.0-windows-x64.zip` | 없음 |

- macOS 는 Apple Silicon(arm64) 전용 — Flutter 3.41.9 + Xcode 27 에서 universal 빌드 불가(문제 해결 참고). `MACOS_ARCHS="arm64 x86_64"` 로 바꿀 수 있음.
- Android 는 64bit(arm64-v8a, x86_64)만 — 32bit 는 llamadart 라이브러리가 없어 요약 불가.
- Linux 실행 PC 필요 패키지: `libmpv2 libgtk-3-0 libsecret-1-0 libgles2 libegl1`. `.desktop` 파일 동봉.
- 출시 전 `com.example.maeknote` 번들 ID·표시 이름·아이콘 교체 필요 (가이드 §5).

## 시험

`test/dev-env/` (환경 검증) · `test/impl/<Nth>/` (차수별 `scenario.md`·`result.md`·`logs/`·`screens/`). 계획표: `test/impl/PLAN.md`.

| 차수 | 내용 | 판정 | 핵심 근거 |
|------|------|------|-----------|
| dev-env | 툴체인·빌드 | PASS | iOS/macOS 배포 대상 상향 |
| 1st | 기반 | PASS | 스키마·FTS5·셸 |
| 2nd | 플레이어 | PASS | 실재생 mp3/mp4 + EQ 필터 반영 |
| 3rd | 모델 관리자 | PASS | 이어받기·위변조 차단·AC4/AC5 |
| 4th | 전사 | PASS | Whisper tiny 실다운로드, 19.7초 한국어 회의 0.7초 전사 |
| 5th | 전사 탭 | PASS | AC1·AC2 |
| 6th | 요약 | PASS | Qwen2.5 0.5B 실요약, AC3 |
| 7th | 클라우드·내보내기 | PASS | Messages API 규격, AC6 |
| 8th | 설정·전체 E2E | PASS | 실제 앱 UI 전 과정 + 화면 14장 |
| 9th | 창 크기 = VOX (R2) | PASS | 322×574 실측 일치 |
| 10th | UI 다국어 (R3) | PASS | en/ko 키 정합성, JSON 확장, 실시간 전환, 두 언어 전체 흐름 |
| 11th | 오른쪽 노트 패널 (R4) | PASS | 창 실측 322↔737, 전사 시작 시 자동 펼침, 화면 en/ko |
| 12th | 요약 템플릿 개선 (R5) | PASS | 5종 섹션 구조, 정제·섹션별 생성, 실모델 시간 링크 100% |
| 13th | 마지막 상태로 시작 (R6) | PASS | 실제 재실행 위치·크기 복원, 화면 밖 → 기본 위치 |
| 14th | 13th 재검증 (화면 잠금 해제) | PASS | `make test-integration` 5개 파일 + app_flow ko PASS, 코드 변경 없음 |
| 15th | 정리 · 설치 이미지 (R7) | PASS | `make clean` 13.7GB 정리, dmg·ipa·apk·aab·linux tar.gz 생성, dmg 실행·Linux 컨테이너 실행 확인 |
| 16th | VOX 방식 헤더·끌어다 놓기·설정 팝업·글꼴 (R8) | PASS | 제목 옆 전체 시간, 헤더 호버 슬라이드(실제 마우스 이동), 채널 흉내 드롭, 화면 en/ko, dist 재생성 |
| 17th | 전사 속도·백그라운드 전사 (R9) | PASS | 기본 80%: 늘린 음성 24.57초·시간은 원래 기준, 진행 중 패널·재생 유지, 완료 시 패널 표시/다른 곡 재생 중 '보기' 알림, 화면 en/ko, dist 재생성 |
| 18th | 요약 클립보드 복사 (R10) | PASS | 내보내기 메뉴 → 요약 탭 유형의 최신 요약 Markdown 복사·알림, 요약 없으면 비활성, dist 재생성 |

## 문제 해결 (실제로 겪은 것)

- **macOS/iOS 빌드 실패 `MACOSX_DEPLOYMENT_TARGET 10.15` / `IPHONEOS_DEPLOYMENT_TARGET 13.0`**: Xcode 27 은 macOS 12 / iOS 15 미만 미지원, llamadart 는 macOS 14.0 / iOS 16.4 요구 → `Podfile`·`project.pbxproj`·Podfile `post_install` 에서 상향(반영됨).
- **`flutter build macos --release` 가 `does not contain architectures "arm64 x86_64"` 로 실패**: Xcode 27 의 `lipo -verify_arch` 가 아키텍처를 여러 개 받지 않음(`requires exactly one input file`) → Flutter 3.41.9 의 universal 확인 실패. `make dist-macos`·`prod-build-desktop` 은 `FLUTTER_XCODE_ARCHS=arm64` 로 빌드. PATH 에 lipo 대체 스크립트를 두는 우회는 Xcode 가 툴체인 경로를 앞에 두어 효과 없음.
- **Linux Docker 빌드 `Failed to find any of [ld.lld, ld]` / `[llvm-ar, ar]`**: 네이티브 빌드 훅 요구 → `build-essential lld llvm` 추가(반영됨).
- **Linux 실행 즉시 종료 `Couldn't open libGLESv2.so.2`**: 실행 PC 에 `libgles2 libegl1` 필요.
- **키링 없는 Linux 에서 시작 중 멈춤 `PlatformException(Libsecret error …)`**: 시작 시 API 키 읽기 실패를 무시하도록 수정(`CloudKeys.load`). 이 경우 클라우드 키 저장은 불가.
- **전체 ABI 단일 APK 가 ~360MB**: ABI별 APK 로 분리, 32bit 제외.
- **Android 빌드 `Could not find method kotlin()` (desktop_drop 0.8.0)**: 플러그인 Gradle 스크립트가 kotlin 플러그인 없이 `kotlin {}` 사용 → `desktop_drop ^0.7.0` 으로 고정(0.8.4 는 connectivity_plus 와 충돌, 0.9 는 Dart 3.13 필요).
- **시험에서 실제 파일 복사가 멈춤**: `testWidgets` 안의 파일 입출력은 `tester.runAsync` 로 감싸야 함.
- **실행 중인 앱에 파일을 끌어다 놓자 강제 종료 (`Lost connection to device`, mpv `m_config_cache_from_shadow` assert / sqlite 안 주소 0)**: `make macos`(flutter run) 로 띄운 Debug 앱이 있는 동안 통합 시험이 **같은 Debug 앱 번들을 다시 빌드·실행**해서 생김. 재현: 한 앱이 끌어다 놓기·재생·전사를 150초 반복 → 혼자면 48회 무사, 다른 시험 앱을 빌드·실행하면 몇 초 안에 같은 크래시. 끌어다 놓기 자체의 문제 아님 → `make test-integration` 은 Debug 앱이 떠 있으면 실행을 거부함. 설치본(dmg 등)에는 해당 없음.
- **긴 녹음 전사가 '디코딩 실패'로 끝남**: mpv 는 깨진 프레임에 "Error decoding audio." 를 내고 계속 재생하는데 디코더가 이를 치명적 오류로 처리 → 파일을 열지 못한 경우(1초 지나도 길이 모름)만 실패로 바꿈(`audio_decoder.dart`). 9분 51초 MP3(프레임 이어 붙임, 오류 30여 회)를 3.4초에 끝까지 디코딩.
- **전사 속도를 바꾸자 디코딩 실패 `error.decodeFailed`**: media_kit 의 FFmpeg 에는 `atempo` 필터가 없음(`equalizer`·`aresample` 만) → mpv `speed` + 내장 `scaletempo2` 로 변경(반영됨).
- **샌드박스 macOS 앱이 원본 파일을 다시 못 읽음**: 가져올 때 앱 폴더로 복사(`LibraryRepo.import`).
- **macOS 창이 지정 크기 대신 이전 크기로 열림**: macOS 창 상태 복원이 덮어씀 → `isRestorable = false`, 위치·크기 복원은 앱이 직접 수행(`window_state.dart`).
- **322pt 창에서 English 문구가 넘침**: 노트 헤더 버튼은 아이콘(툴팁), 재생목록 전사 배지는 "⏳20%" 로 축약.
- **0.5B 모델이 전사본·지침·예시를 그대로 베낌**: 지침을 문장형으로, 베낀 항목·자리표시 단어 필터, 근거 없는 항목은 2-gram 매칭으로 원문 연결. 품질이 필요하면 T1 이상.
- **`flutter test integration_test -d macos` 일괄 실행 시 두 번째 파일부터 "Unable to start the app"**: 데스크톱 앱 재기동 한계 → `make test-integration` 은 파일별 순차 실행.
- **화면이 잠기면 통합 시험의 창 크기 애니메이션이 진행되지 않음**(화면 캡처도 실패): 잠금 해제 후 실행. 매 실행의 `Failed to foreground app; open returned 1` 경고는 무해.
- **Android 릴리스에서 다운로드 불가**: `android/app/src/main/AndroidManifest.xml` 에 INTERNET 권한 추가(반영됨).

## 알려진 제한 / 미검증

- Windows 설치 이미지·실행은 미검증(Windows 호스트/release CI 필요). Linux 는 arm64 컨테이너(Xvfb)에서 시작만 확인 — 실제 데스크톱·x64 미검증.
- iOS · Android 설치 이미지는 생성만 확인 — 기기·에뮬레이터 설치·실행 미검증(연결된 기기 없음).
- macOS dmg 는 ad-hoc 서명 — 다른 Mac 에서는 Gatekeeper 가 막음(Developer ID 서명·공증 필요).
- 클라우드 실제 호출은 사용자 API 키가 필요해 미검증(요청 규격은 시험으로 검증).
- 화자 분리 · 앱 내 녹음 · 번역 · 유료화 · 익명 통계는 범위 밖(PRD §3, §8).
- `ramMb`·처리 시간(`minPerHour`)은 추정값입니다.
