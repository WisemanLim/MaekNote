# MaekNote — cross-platform recording transcription & summary player

> 한국어: [README.md](README.md) · Requirements: [PRD.md](PRD.md) (change history §8) · Compliance: [COMPLIANCE.md](COMPLIANCE.md) · Plan: [test/impl/PLAN.md](test/impl/PLAN.md)

A Flutter app with a compact VOX-style player that plays audio/video recordings and produces transcripts and
note summaries (meeting minutes · lecture notes · interview summary · context summary · brief summary) using
**models that run on the device**. One codebase builds for iOS · Android · macOS · Windows · Linux.

## Features

| Feature | Details | Code |
|---------|---------|------|
| Player | Total play time next to the title; seek bar, repeat/shuffle/volume, EQ and output slide open when you hover the header; 10-band EQ + presets (Voice Boost…), output device | `lib/features/player`, `lib/features/shell/main_screen.dart` (`HoverReveal`) |
| Playlist & collections | ＋ or **drag and drop** files/folders (desktop) — dropping on a collection, or into an open one, also adds to that collection | `lib/features/library` |
| Transcription | Audio/video → 16 kHz PCM (libmpv, **transcription speed** 80 % by default — slowed with mpv `scaletempo2`, pitch kept) → Silero VAD segments → Whisper (sherpa-onnx); times mapped back to the original timeline. Runs in the **background** (progress, cancel), shown when finished | `lib/features/transcribe` |
| Notes › Transcript | Highlights and auto-scrolls the sentence at the playback position, tap to seek, full-text search (FTS5) | `transcript_view.dart` |
| Notes › Summary | 5 templates with researched sections, transcript clean-up then one call per section, `[mm:ss]` time link on every item | `lib/features/summary`, `assets/summary/templates.json` |
| Layout | VOX-sized player on the left, note panel expanding to the right during transcription/summary | `lib/features/shell`, `lib/core/window_sizer.dart` |
| Start where you left off | Restores window position/size/note panel and the last file/position | `lib/core/window_state.dart`, `playback_memory.dart` |
| Model manager | Device RAM → recommended tier (T0–T4), resumable download, SHA256 check, delete/default, oversize warning | `lib/features/models`, `assets/models/manifest.json` |
| Cloud (optional) | Off by default. After consent, sends **summaries only** to an OpenAI-compatible API or Anthropic | `lib/features/cloud` |
| Export | Save TXT · Markdown (with summaries) · SRT · VTT, or **copy the summary to the clipboard** (the type chosen in the Summary tab, as Markdown) | `lib/features/export` |
| Languages | Korean and English built in (default English), extend with JSON packs, switch live | `lib/core/i18n.dart`, `assets/i18n/` |
| Settings | Opens as a **popup**. General (language, font, text size) · Audio · Models · Transcription · Summary · Cloud · Storage & Privacy (outbound log) | `lib/features/settings` |
| Density | VOX-level text (list title 13, secondary 11 pt) and 18 pt icons; compact rows on desktop | `lib/core/theme.dart` |

## How to use

1. **＋** to import audio/video, or on desktop **drag files/folders** onto Playlist/Collections (copied into the app folder so it still plays after restart)
   - Playback controls: hover the title area (header) and the seek bar, repeat, shuffle, volume, EQ and output row slides down (tap the header on phones)
2. Item menu (⋮) › **Transcribe** — without a model, the app recommends one with size and estimated time
3. Transcription runs in the **background** — playback and the screen stay as they are; the list badge (⏳60%) and the Transcript tab show progress only. When it finishes, the window widens and the **note panel** opens with the full transcript (if another file is playing, it is not interrupted; a "Transcription finished · View" notice appears instead)
4. **Transcript** tab follows playback; tap a sentence to seek
5. **Summary** tab: pick a type chip → **Generate** → tap `[mm:ss]` to jump to that part of the transcript
6. ‹ at the top-left of the panel closes it back to VOX size. The share icon exports TXT/MD/SRT/VTT or **copies the summary to the clipboard** (latest summary of the type chosen in the Summary tab, as Markdown — disabled if there is none)

## Layout

| Platform | Layout |
|----------|--------|
| Desktop (macOS·Windows·Linux) | First launch = measured VOX main window **322 × 574 pt** (title bar included, minimum 322 × 480). Notes icon (≡) or a finished transcription → the window widens to **737 pt**: 322 pt player on the left, note panel on the right. Closing returns to 322 pt. A window the user already widened is not shrunk |
| Phone | Same structure full-screen; notes via the icon tab |
| Tablet (≥ 900 px) | Player and notes side by side |

When the player column is narrower than 420 px, the volume −/+ buttons are hidden (the slider stays; 44 pt touch targets kept).

**Player header (VOX style, R8)**

| State | Shown |
|-------|-------|
| Default | folder · **title + total play time on one line** · thin progress line |
| Header hovered (phone: tapped) | slides down: seek bar (position/total) + repeat · shuffle · volume · EQ · output; closes 0.4 s after the pointer leaves |
| EQ or output panel in use | control row stays open |

A closed control row is also hidden from keyboard focus and screen readers.

**Drag and drop (desktop)**: onto the playlist → import; onto a collection in the list → import and add to it (the row is highlighted); into an open collection → add to it. Folders are expanded recursively and only playable extensions are taken. Files already in the playlist are not copied again, only added to the collection.

**Text and settings (R8)**: text, icons and row heights are reduced to VOX level (list title 13 pt, secondary 11 pt, title 15 pt, icons 18 pt). Compact spacing is desktop-only; phones keep 44 pt touch targets. Settings open as a **popup** (up to 520 × 640) instead of a new screen. General › **Appearance** picks the font (system default, sans-serif, serif, monospace — looked up from installed OS fonts) and text size (85/100/115/130 %, multiplied with the OS text size) (`general.font`, `general.fontSize`).

## Transcription (speed · background)

| Item | Behavior |
|------|----------|
| Transcription speed | Settings › Transcription › **Transcription speed** (50/60/70/**80**/90/100 %, default 80 %, `transcribe.speed`). Decoding slows mpv's playback speed with its built-in `scaletempo2` (pitch kept) → the stretched 16 kHz audio is recognized → sentence times and file length × speed = original timeline |
| Background | Starting a transcription does not change the playing file or the screen. The list badge (⏳60%) and the Transcript tab show progress only; partial sentences are not shown (they are still saved — on cancel/error what was done is shown) |
| Finished | If it is the current file, or nothing is playing, the note panel (phone: Notes tab) opens with the full transcript. If another file is playing, it is not interrupted; a **"Transcription finished: title · View"** notice appears |

Measured (macOS, whisper-tiny, 19.7 s synthetic Korean meeting, `integration_test/transcribe_test.dart`):

| Speed | Stretched length | Transcription time | Sentence times (original) | Recognition errors |
|-------|------------------|--------------------|---------------------------|--------------------|
| 100 % | 19.67 s | 572 ms | 134–5328 · 6822–12880 · 14406–19680 | 5 |
| 80 % | 24.57 s | 671 ms | 312–5338 · 6814–12864 · 14418–19661 | 5 |

No difference on clean synthetic speech; slower speeds are meant for fast or noisy recordings (processing takes about 1/speed as long).

## Start where you left off

| Item | Saved when | Restored | Setting key |
|------|------------|----------|-------------|
| Window position/size (desktop) | 0.4 s after moving/resizing stops, and once at startup | Same position/size next launch; if the title bar would not be visible on any connected screen (e.g. monitor unplugged) → default position | `window.frame` = `x,y,w,h` |
| Note panel (desktop) | On open/close | Opens at startup if the restored window is ≥ 737 pt | `window.notePanel` |
| Playback file/position | Every 5 s while playing | Last file loaded **paused** at the last position | `general.lastMediaId`, `general.lastPositionMs` |

Playback restore can be turned off in Settings › General › **Remember last file and position** (on by default).
macOS' own window restoration is off (`isRestorable = false`); the app restores the frame itself.

## Summary templates

| Type | Sections (web research) | Basis |
|------|--------------------------|-------|
| Meeting minutes | Overview · Discussion by agenda item · Decisions · Action items (who, what, by when) · Open issues & next meeting | Common elements of Atlassian, Asana, Slack templates |
| Lecture notes | Topic & overview · Key concepts & definitions · Main points · Review questions · Summary | Cornell notes (notes, cues, summary) |
| Interview summary | Context & interviewee · Key themes · Key questions & answers · Notable quotes · Insights & follow-ups | User-interview synthesis templates |
| Context summary | Background & purpose · Flow · Key points · Conclusion & implications | Context → points → conclusion (CQC) |
| Brief summary | TL;DR · Key points | TL;DR convention |

Pipeline
1. For long recordings (several chunks), write **clean notes** per chunk — fix obvious misrecognitions, drop filler and repetition, keep people/numbers/dates/decisions/tasks and source line numbers `[S<n>]`
2. Write **each template section separately** (so small models keep the structure) — item limit, source `[S<n>]` required, "None" if nothing applies
3. Drop empty sections, items that copy the prompt/guide, and items that are only "TBD"; items without a source are linked to the transcript segment with the largest character-bigram overlap

Titles, guides, item limits, prompts (per output language) and source URLs live in `assets/summary/templates.json` (rebuild after editing).
The length setting scales item limits by 0.5/1/1.5. Summary **content** language follows Settings › Summary › Output language (default Korean).
The 0.5B (T0) model tends to copy transcript sentences and cannot summarize Korean audio in English — **use T1 or higher**.

## Languages (UI)

- Default language is **English**; change it in Settings › General › **App language** (applies immediately, including built-in widgets such as Back).
- Packs live in `assets/i18n/<code>.json` (179 keys today): flat keys, `_name` is the name shown in the list, `{name}` marks a placeholder:
  ```json
  { "_name": "日本語", "app.settings": "設定", "player.play": "再生" }
  ```
- Add a language: ① add `assets/i18n/ja.json` and rebuild (folder is registered), or ② without rebuilding, put `i18n/ja.json` in the app data folder and restart (same code overrides key by key; invalid JSON is ignored).
- Missing keys fall back to English, then to the key name. `assets/i18n/en.json` is the reference. Error messages are passed as keys and shown in the chosen language.

## Model tiers (memory/speed are estimates)

| Tier | Device RAM | Transcription (Whisper int8 ONNX) | Summary (GGUF Q4_K_M) |
|------|-----------|------------------------------------|-----------------------|
| T0 | ≤ 4 GB | tiny 103 MB · base 160 MB | Qwen2.5 0.5B 469 MB |
| T1 | ≤ 8 GB | small 358 MB | Qwen2.5 1.5B 1.0 GB |
| T2 | ≤ 16 GB | turbo 988 MB · medium 902 MB | Qwen3 4B 2507 2.3 GB |
| T3 | ≤ 32 GB | large-v3 1.7 GB | Qwen2.5 7B 4.4 GB |
| T4 | > 32 GB | (large-v3) | Qwen2.5 14B 8.4 GB |

Models download directly from Hugging Face (VAD from the sherpa-onnx GitHub release). Licenses: MIT (Whisper, VAD), Apache-2.0 (Qwen).

## Layout of the code

```
lib/
├── main.dart · app.dart     # startup (DB, manifest, language packs, templates, device spec, window restore) · routes
├── core/                    # db · i18n · window_sizer (322 ↔ 737) · window_state (frame save/restore) · net · theme · providers
└── features/ shell · library · player · models · transcribe · summary · cloud · export · settings
assets/ models/manifest.json · i18n/en.json, ko.json · summary/templates.json
```

Data lives in the OS app-support folder (`maeknote.db`, `media/`, `models/`, `tmp/`, optional `i18n/`). API keys are stored only in Keychain/Keystore/DPAPI/libsecret.

## Requirements

- Flutter 3.38+ (verified 3.41.9) / Dart 3.10+
- Minimum OS: iOS 16.4 · macOS 14.0 (required by llamadart) · Android (Flutter default)
- Xcode (iOS/macOS), Android SDK (accept licenses with `flutter doctor --android-licenses`)
- Linux build deps: `build-essential clang lld llvm cmake ninja-build pkg-config libgtk-3-dev libmpv-dev libsecret-1-dev libjsoncpp-dev` (or build in Docker with `make dist-linux-docker`)
- No C/C++ toolchain needed — llama.cpp, sherpa-onnx and libmpv ship prebuilt binaries (network needed on first build).

## Run

```bash
make preflight
make setup
make macos                        # or windows / linux / ios / android
make local-all DEVICE="-d macos"
```

## Build flavors

| Key | `.env.local` | `.env.prod` | Note |
|-----|--------------|-------------|------|
| `APP_ENV` / `FLAVOR` | local | prod | injected with `--dart-define-from-file` |
| `API_BASE_URL` | http://localhost:8000 | https://api.example | scaffold default; the app uses no server |

Cloud API keys and models are entered in **Settings › Cloud**, not in env files.

## Make targets

| Target | Description |
|--------|-------------|
| `make help` | list targets |
| `make preflight` / `make setup` | toolchain check / install deps |
| `make local-all [DEVICE=…]` · `make local-stop` | run / stop simulators |
| `make ios` · `make android` · `make macos` · `make windows` · `make linux` | run per platform |
| `make test` | unit + widget tests + analyze (103 tests) |
| `make test-integration` | 6 macOS integration files, one by one — full UI flow, drag-and-drop stress (repeated drops while playing and transcribing in the background), playback, summary, transcription, window state. Downloads ~600 MB of models on first run; **needs an unlocked screen**; refuses to run while a Debug app from `make macos` is running |
| `make local-build` / `make prod-build` | debug APK / AAB + IPA (signing required) |
| `make prod-build-desktop` | release build for the host desktop OS (arm64 on macOS) |
| `make deploy` | fastlane store upload |
| `make clean` / `make distclean` | remove build outputs and intermediates (`build/`, `.dart_tool/`, Pods, Gradle cache) / plus `dist/` |
| `make dist` | every install image the host can build → `dist/` |
| `make dist-macos` · `dist-ios` · `dist-android` · `dist-linux` · `dist-linux-docker` · `dist-windows` | per-platform install images (table below) |

Full UI flow in Korean: `flutter test integration_test/app_flow_test.dart -d macos --dart-define=IT_LANG=ko` (default English).
CI (`.github/workflows/ci.yml`): Android (analyze + test) · iOS · macOS · Windows · Linux build matrix.
Release (`.github/workflows/release.yml`): push a `v*` tag → `dist/` built on macOS, Linux and Windows runners → attached to the GitHub Release.

## Install images (distribution)

Signing, notarization, store upload and CI secrets: [DEPLOY-PROD-GUIDE.md](DEPLOY-PROD-GUIDE.md) (Korean).

| Platform | Command (build host) | Output in `dist/` (measured, 0.1.0) | Default signing |
|----------|----------------------|-------------------------------------|-----------------|
| macOS | `make dist-macos` (macOS) | `MaekNote-0.1.0-macos-arm64.dmg` (31 MB) | ad-hoc (Developer ID + notarization before release) |
| iOS | `make dist-ios` (macOS) | `MaekNote-0.1.0-ios-unsigned.ipa` (42 MB) | none (re-sign or `make prod-build`) |
| Android | `make dist-android` | `…-android-arm64-v8a.apk` (155 MB) · `…-android-x86_64.apk` (160 MB) · `…-android.aab` (233 MB) | debug key unless `android/key.properties` exists |
| Linux | `make dist-linux` (Linux) · `make dist-linux-docker` (Docker) | `MaekNote-0.1.0-linux-arm64.tar.gz` (92 MB, Docker on Apple Silicon) | — |
| Windows | `make dist-windows` (Windows) · release CI | `MaekNote-0.1.0-windows-x64.zip` | none |

- macOS images are Apple Silicon (arm64) only: a universal build fails with Flutter 3.41.9 + Xcode 27 (see Troubleshooting). Override with `MACOS_ARCHS="arm64 x86_64"`.
- Android is 64-bit only (arm64-v8a, x86_64): llamadart ships no 32-bit library, so summaries could not run there.
- Linux runtime packages: `libmpv2 libgtk-3-0 libsecret-1-0 libgles2 libegl1`. A `.desktop` file is included.
- Replace the `com.example.maeknote` bundle ID, display name and icon before a store release (guide §5).

## Tests

`test/dev-env/` (environment check) · `test/impl/<Nth>/` (per-iteration `scenario.md`, `result.md`, `logs/`, `screens/`). Plan: `test/impl/PLAN.md`.
dev-env and iterations 1st–18th PASS (14th re-ran the full integration suite, including the en/ko UI flow, with the screen unlocked; 15th = cleanup and install images; 16th = VOX-style header, drag and drop, settings popup, font and text size; 17th = transcription speed and background transcription; 18th = copy summary to clipboard). See the Korean README for the per-iteration table.

## Troubleshooting (seen during development)

- **macOS/iOS build fails on `MACOSX_DEPLOYMENT_TARGET 10.15` / `IPHONEOS_DEPLOYMENT_TARGET 13.0`**: Xcode 27 dropped them and llamadart needs macOS 14.0 / iOS 16.4 — raised in `Podfile`, `project.pbxproj` and Podfile `post_install` (done).
- **`flutter build macos --release` fails with `does not contain architectures "arm64 x86_64"`**: Xcode 27's `lipo -verify_arch` rejects more than one architecture (`requires exactly one input file`), so Flutter 3.41.9's universal check fails. `make dist-macos` and `prod-build-desktop` build with `FLUTTER_XCODE_ARCHS=arm64`. Putting a replacement `lipo` script first on PATH does not help, because Xcode puts its toolchain first.
- **Linux Docker build: `Failed to find any of [ld.lld, ld]` / `[llvm-ar, ar]`**: the native build hooks need them → `build-essential lld llvm` added (done).
- **Linux app exits at once with `Couldn't open libGLESv2.so.2`**: install `libgles2 libegl1`.
- **Linux without a keyring stops at startup with `PlatformException(Libsecret error …)`**: startup now ignores a failed key read (`CloudKeys.load`); cloud keys cannot be saved on such systems.
- **A single all-ABI APK is ~360 MB**: split per ABI, 32-bit dropped.
- **Android build: `Could not find method kotlin()` (desktop_drop 0.8.0)**: its Gradle script uses `kotlin {}` without the Kotlin plugin → pinned `desktop_drop ^0.7.0` (0.8.4 conflicts with connectivity_plus, 0.9 needs Dart 3.13).
- **A test hangs on real file copies**: file I/O inside `testWidgets` must run in `tester.runAsync`.
- **Dropping a file onto the running app force-quits it (`Lost connection to device`, mpv `m_config_cache_from_shadow` assert / jump to address 0 inside sqlite)**: caused by integration tests **rebuilding and launching the same Debug app bundle** while a Debug app started with `make macos` (flutter run) was running. Reproduced: one app looping drop + play + transcribe for 150 s survives 48 rounds alone, but crashes within seconds when another test build is launched. Not a drag-and-drop bug → `make test-integration` now refuses to run while that Debug app is running. Installed builds (dmg etc.) are not affected.
- **Long recordings end with "decode failed"**: mpv reports "Error decoding audio." for a broken frame and keeps playing, but the decoder treated it as fatal → now it only fails when the file cannot be opened (no duration after 1 s) (`audio_decoder.dart`). A 9 min 51 s MP3 (concatenated frames, ~30 such errors) now decodes to the end in 3.4 s.
- **Decoding fails (`error.decodeFailed`) once a transcription speed is set**: media_kit's FFmpeg has no `atempo` filter (only `equalizer`, `aresample`) → switched to mpv `speed` with its built-in `scaletempo2` (done).
- **Sandboxed macOS app cannot reopen original files**: imports are copied into the app folder (`LibraryRepo.import`).
- **macOS window reopens at a previous size**: macOS window restoration overrode it → `isRestorable = false`; the app restores position/size itself (`window_state.dart`).
- **English labels overflow at 322 pt**: note header actions are icon buttons (tooltips) and the playlist badge is shortened to "⏳20%".
- **0.5B model copies the transcript, guides or examples**: guides are plain sentences, copied items and placeholder-only items are filtered, items without a source are linked by bigram overlap. Use T1+ for quality.
- **`flutter test integration_test -d macos` fails from the second file with "Unable to start the app"**: desktop relaunch limit → `make test-integration` runs files one by one.
- **With the screen locked, window-resize animations in integration tests do not progress** (screenshots fail too): run with the screen unlocked. The `Failed to foreground app; open returned 1` warning on each run is harmless.
- **Android release cannot download**: INTERNET permission added to the main manifest (done).

## Known limits / not verified

- The Windows image and runtime are not verified (needs a Windows host or the release CI). Linux was only checked to start in an arm64 container (Xvfb); a real desktop and x64 are not verified.
- iOS and Android images were built but not installed on a device or emulator (none connected).
- The macOS dmg is ad-hoc signed, so Gatekeeper blocks it on other Macs until it gets a Developer ID signature and notarization.
- Real cloud calls need a user API key and were not exercised (request format is covered by tests).
- Speaker diarization, in-app recording, translation, paid tiers and anonymous telemetry are out of scope (PRD §3, §8).
- `ramMb` and processing-time estimates (`minPerHour`) are assumptions.
