// 실제 앱 화면을 조작하는 E2E: 모델 다운로드 → 전사 → 노트(전사·요약) → EQ/출력 → 설정
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:maeknote/app.dart';
import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/i18n.dart';
import 'package:maeknote/core/providers.dart';
import 'package:maeknote/core/window_sizer.dart';
import 'package:maeknote/features/cloud/cloud_llm.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/player/media_kit_backend.dart';
import 'package:maeknote/features/player/player_widgets.dart';
import 'package:maeknote/features/settings/settings_repo.dart';
import 'package:maeknote/features/summary/summarizer.dart';
import 'package:maeknote/features/transcribe/transcript_repo.dart';

import 'support.dart';

class _NoSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String? value) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('full app flow through the UI', (tester) async {
    final dir = p.join((await getApplicationSupportDirectory()).path, 'it_app');
    await Directory(dir).create(recursive: true);
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(playerWindowWidth, 574));
    final db = AppDatabase.open(p.join(dir, 'maeknote.db'));
    final catalog =
        ModelCatalog.parse(await rootBundle.loadString('assets/models/manifest.json'));
    final packs = await LanguagePacks.load(rootBundle);
    // --dart-define=IT_LANG=ko 로 한국어 흐름 (기본 English)
    const lang = String.fromEnvironment('IT_LANG', defaultValue: 'en');
    final t = I18n(packs, lang).t;
    final c = ProviderContainer(overrides: [
      appDirProvider.overrideWithValue(dir),
      dbProvider.overrideWithValue(db),
      catalogProvider.overrideWithValue(catalog),
      deviceProvider.overrideWithValue(await detectDevice()),
      audioBackendProvider.overrideWithValue(MediaKitBackend()),
      secretStoreProvider.overrideWithValue(_NoSecrets()),
      languagePacksProvider.overrideWithValue(packs),
      summaryTemplatesProvider.overrideWithValue(SummaryTemplates.parse(
          await rootBundle.loadString('assets/summary/templates.json'))),
      windowSizerProvider.overrideWithValue(DesktopWindowSizer()),
    ]);
    final settings = c.read(settingsProvider)
      ..setBool(SettingKeys.wifiOnlyDownload, false)
      ..setBool(SettingKeys.savePosition, false)
      ..setBool(SettingKeys.eqEnabled, false)
      ..set(SettingKeys.sttLanguage, 'ko')
      ..set(SettingKeys.language, lang);
    await c.read(libraryProvider).clear();

    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const App()));
    await tester.pumpAndSettle();

    Future<void> wait(bool Function() cond, {int seconds = 120}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!cond()) {
        if (DateTime.now().isAfter(end)) throw StateError('timeout');
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }
    }

    /// 창 크기 애니메이션이 끝날 때까지 실제 창 크기를 확인
    Future<Size> windowWidth(double target) async {
      final end = DateTime.now().add(const Duration(seconds: 10));
      var size = await windowManager.getSize();
      while (size.width != target && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        size = await windowManager.getSize();
      }
      return size;
    }

    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('SHOT:$name');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1500)));
    }

    await shot('01-empty');

    // 1) 모델 탭에서 다운로드 (확인 대화상자 경유)
    final store = c.read(modelStoreProvider);
    await tester.tap(find.byIcon(Icons.memory));
    await tester.pumpAndSettle();
    Future<void> install(String name, String id) async {
      if (store.isInstalled(id)) return;
      final tile = find.ancestor(of: find.text(name), matching: find.byType(ListTile));
      await tester.tap(find.descendant(of: tile, matching: find.byTooltip(t('models.download'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton).last); // 다운로드 / 그래도 다운로드
      await wait(() => store.isInstalled(id), seconds: 300);
    }

    await install('Whisper tiny (int8)', 'whisper-tiny');
    await shot('02-models-stt');
    await tester.tap(find.text(t('models.kind.llm')));
    await tester.pumpAndSettle();
    await install('Qwen2.5 0.5B Instruct (Q4_K_M)', 'qwen2.5-0.5b');
    store.setDefault(catalog.byId('qwen2.5-0.5b')!);
    await shot('03-models-llm');

    // 2) 파일 가져오기 (파일 선택 창은 자동화 불가 → 저장소 직접 호출) 후 재생
    final files = await tester.runAsync(() async =>
        writeFixtures(p.join((await getTemporaryDirectory()).path, 'it_app_src')));
    await tester.runAsync(() => c.read(libraryProvider).import([files!.mp3, files.mp4]));
    await tester.tap(find.byIcon(Icons.queue_music));
    await tester.pumpAndSettle();
    await c.read(playerProvider).setVolume(0);
    await tester.tap(find.text('meeting_ko').last); // mp4
    await wait(() => c.read(playerProvider).playing);
    await c.read(playerProvider).togglePlay();
    await shot('04-playlist');

    // 3) 항목 메뉴 → 전사하기
    final item = c.read(playerProvider).current!;
    await tester.tap(find.byTooltip(t('library.itemMenu')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('transcribe.start')));
    final repo = c.read(transcriptRepoProvider);
    // 전사는 백그라운드: 진행 중에는 패널이 열리지 않고 목록 배지로 진행률만 보인다
    await wait(() => repo.info(item.id).status != TranscriptStatus.none);
    if (repo.info(item.id).running) {
      expect(c.read(notePanelProvider), isFalse);
      await shot('04a-transcribing-background');
    }
    await wait(() => repo.info(item.id).status == TranscriptStatus.done);
    // 완료되면 노트 패널이 오른쪽으로 펼쳐지고(Image #8) 전체 전사가 표시된다
    await wait(() => c.read(notePanelProvider));
    final opened = (await tester.runAsync(() => windowWidth(expandedWindowWidth)))!;
    // ignore: avoid_print
    print('WINDOW_OPEN ${opened.width}x${opened.height}');
    expect(opened.width, expandedWindowWidth);
    await shot('05-panel-opened');

    // 4) 노트 > 전사: 재생 위치 추적 (오른쪽 패널)
    final segs = repo.segments(item.id);
    expect(segs.length, greaterThanOrEqualTo(2));
    await tester.tap(find.text(segs[1].text));
    await wait(() =>
        c.read(playerProvider).position.value.inMilliseconds >= segs[1].startMs - 300);
    await c.read(playerProvider).togglePlay(); // 재생 → 위치 진행
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await c.read(playerProvider).togglePlay();
    await shot('06-note-transcript');

    // 5) 노트 > 요약: 회의록 생성 → 시간 링크
    await tester.tap(find.text(t('note.summary')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, t('summary.type.meeting')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('summary.generate')));
    final summaries = c.read(summaryServiceProvider);
    await wait(() => summaries.latest(item.id, SummaryType.meeting) != null);
    await shot('07-note-summary');
    final link = find.descendant(
        of: find.byType(TextButton), matching: find.textContaining(RegExp(r'^\[\d+:\d\d\]$')));
    expect(link, findsWidgets);
    await tester.tap(link.first);
    await tester.pumpAndSettle();
    await shot('08-summary-link-to-transcript');

    // 6) 헤더(제목)를 가리키면 시크바·볼륨·반복·EQ 가 펼쳐진다 → EQ · 출력 장치 패널
    expect(find.byTooltip(t('player.equalizer')).hitTestable(), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(PlayerHeader)));
    await tester.pumpAndSettle();
    expect(find.byTooltip(t('player.equalizer')).hitTestable(), findsOneWidget);
    await shot('09a-controls-hover');
    await mouse.moveTo(tester.getCenter(find.byTooltip(t('player.equalizer'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t('player.equalizer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice Boost').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await shot('09-equalizer');
    expect(settings.getBool(SettingKeys.eqEnabled), isTrue);
    await tester.tap(find.byTooltip(t('player.output')));
    await shot('10-output');
    await tester.tap(find.byTooltip(t('player.output')));
    await tester.pumpAndSettle();

    // 7) 설정
    await tester.tap(find.byTooltip(t('app.settings')));
    await shot('11-settings-general');
    await tester.ensureVisible(find.text(t('settings.tab.models')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('settings.tab.models')));
    await shot('12-settings-models');
    await tester.ensureVisible(find.text(t('settings.tab.cloud')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('settings.tab.cloud')));
    await shot('13-settings-cloud');
    await tester.ensureVisible(find.text(t('settings.tab.storage')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('settings.tab.storage')));
    await shot('14-settings-storage');

    // 8) 설정 팝업 닫고 노트 패널 닫기 → 창이 플레이어 너비로 복귀
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.byTooltip(t('common.close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t('note.closePanel')));
    final closed = (await tester.runAsync(() => windowWidth(playerWindowWidth)))!;
    // ignore: avoid_print
    print('WINDOW_CLOSED ${closed.width}x${closed.height}');
    expect(closed.width, playerWindowWidth);
    await shot('15-panel-closed');

    // 외부 전송은 모델 다운로드뿐 (AC6)
    expect(c.read(networkLogProvider).records.where((r) => r.purpose.name == 'cloud'), isEmpty);
    settings.setBool(SettingKeys.eqEnabled, false);
  });
}
