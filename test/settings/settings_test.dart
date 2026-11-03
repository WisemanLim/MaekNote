import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/i18n.dart';
import 'package:maeknote/core/providers.dart';
import 'package:maeknote/core/theme.dart';
import 'package:maeknote/features/cloud/cloud_llm.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/player/playback_memory.dart';
import 'package:maeknote/features/settings/settings_repo.dart';
import 'package:maeknote/features/settings/settings_view.dart';

import '../support/fakes.dart';
import '../support/i18n.dart';

class _MemSecrets implements SecretStore {
  final m = <String, String>{};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String? value) async =>
      value == null || value.isEmpty ? m.remove(key) : m[key] = value;
}

void main() {
  late Directory tmp;
  late AppDatabase db;
  late FakeBackend backend;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('maeknote_settings');
    db = AppDatabase.memory();
    backend = FakeBackend();
    c = ProviderContainer(overrides: [
      appDirProvider.overrideWithValue(tmp.path),
      dbProvider.overrideWithValue(db),
      audioBackendProvider.overrideWithValue(backend),
      secretStoreProvider.overrideWithValue(_MemSecrets()),
      catalogProvider.overrideWithValue(
          ModelCatalog.parse(File('assets/models/manifest.json').readAsStringSync())),
      deviceProvider.overrideWithValue(const DeviceSpec(ramMb: 16384, platform: 'macos')),
      languagePacksProvider.overrideWithValue(loadPacks()),
    ]);
  });

  tearDown(() {
    c.dispose();
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: withI18n(MaterialApp(theme: buildVoxTheme(), home: const SettingsPage())),
    ));
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('7 icon tabs as in PRD §7', (tester) async {
    await pump(tester);
    final ko = I18n(loadPacks(), 'ko');
    for (final (_, key) in SettingsPage.tabs) {
      expect(find.text(ko.t(key)), findsOneWidget);
    }
    expect(SettingsPage.tabs, hasLength(7));
    expect(find.text('마지막 재생 파일과 위치 저장'), findsOneWidget);
  });

  testWidgets('cloud toggle requires consent; cancel keeps on-device', (tester) async {
    await pump(tester);
    await openTab(tester, '클라우드');
    expect(find.text('현재 요약 엔진: 온디바이스'), findsOneWidget);

    await tester.tap(find.text('클라우드로 요약'));
    await tester.pumpAndSettle();
    expect(find.textContaining('다른 사람의 발언(개인정보)'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).getBool(SettingKeys.cloudEnabled), isFalse);

    await tester.tap(find.text('클라우드로 요약'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('동의하고 사용'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).getBool(SettingKeys.cloudEnabled), isTrue);
  });

  testWidgets('saving API key switches active engine (anthropic)', (tester) async {
    c.read(settingsProvider)
      ..setBool(SettingKeys.cloudEnabled, true)
      ..set(SettingKeys.cloudProvider, 'anthropic');
    await pump(tester);
    await openTab(tester, '클라우드');
    await tester.enterText(find.widgetWithText(TextField, 'API 키'), 'sk-test');
    await tester.tap(find.byTooltip('API 키 저장'));
    await tester.pumpAndSettle();
    expect(find.text('현재 요약 엔진: cloud:anthropic:claude-opus-5-5'), findsOneWidget);
    expect(c.read(cloudKeysProvider).of(CloudProvider.anthropic), 'sk-test');
  });

  testWidgets('transcription language choice persists', (tester) async {
    await pump(tester);
    await openTab(tester, '전사');
    await tester.tap(find.text('자동 감지'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('한국어').last);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).get(SettingKeys.sttLanguage), 'ko');
  });

  testWidgets('models tab embeds model manager with Wi-Fi policy', (tester) async {
    await pump(tester);
    await openTab(tester, '모델');
    expect(find.text('Wi-Fi 연결에서만 모델 다운로드'), findsOneWidget);
    expect(find.textContaining('권장 T2'), findsOneWidget);
  });

  test('playback memory saves position and restores paused', () async {
    final f = File(p.join(tmp.path, 'a.mp3'))..writeAsStringSync('x');
    final item = (await c.read(libraryProvider).import([f.path])).single;
    final player = c.read(playerProvider);
    final settings = c.read(settingsProvider);
    final mem = PlaybackMemory(player, settings, c.read(libraryProvider));
    await mem.start();
    await player.playItem(item, [item]);
    backend.positionC.add(const Duration(seconds: 42));
    expect(settings.get(SettingKeys.lastMediaId), '${item.id}');
    expect(settings.get(SettingKeys.lastPositionMs), '42000');
    mem.stop();

    // 재시작 시뮬레이션: 새 엔진에서 일시정지 상태로 42초 위치 복원
    final backend2 = FakeBackend();
    final c2 = ProviderContainer(overrides: [
      appDirProvider.overrideWithValue(tmp.path),
      dbProvider.overrideWithValue(db),
      audioBackendProvider.overrideWithValue(backend2),
    ]);
    addTearDown(c2.dispose);
    await PlaybackMemory(c2.read(playerProvider), c2.read(settingsProvider),
            c2.read(libraryProvider))
        .start();
    expect(c2.read(playerProvider).current?.id, item.id);
    expect(c2.read(playerProvider).playing, isFalse);
    expect(backend2.seeks.last, const Duration(seconds: 42));
  });
}
