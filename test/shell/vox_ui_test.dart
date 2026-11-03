// R8: 제목 옆 전체 시간 · 설정 팝업 · 글꼴/글자 크기
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:maeknote/app.dart';
import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/providers.dart';
import 'package:maeknote/features/cloud/cloud_llm.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/player/player_widgets.dart';
import 'package:maeknote/features/settings/settings_repo.dart';

import '../support/fakes.dart';
import '../support/i18n.dart';

class _NoSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String? value) async {}
}

void main() {
  late Directory tmp;
  late AppDatabase db;
  late FakeBackend backend;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('maeknote_ui');
    db = AppDatabase.memory();
    backend = FakeBackend();
    c = ProviderContainer(overrides: [
      appDirProvider.overrideWithValue(tmp.path),
      dbProvider.overrideWithValue(db),
      audioBackendProvider.overrideWithValue(backend),
      secretStoreProvider.overrideWithValue(_NoSecrets()),
      catalogProvider.overrideWithValue(
          ModelCatalog.parse(File('assets/models/manifest.json').readAsStringSync())),
      deviceProvider.overrideWithValue(const DeviceSpec(ramMb: 8192, platform: 'x')),
      languagePacksProvider.overrideWithValue(loadPacks()),
    ]);
  });

  tearDown(() {
    c.dispose();
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(322, 546);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const App()));
    await tester.pumpAndSettle();
  }

  testWidgets('total play time sits on the title row', (tester) async {
    final f = File(p.join(tmp.path, 'toeic.mp3'))..writeAsStringSync('x');
    final item = (await tester.runAsync(() => c.read(libraryProvider).import([f.path])))!.single;
    await pump(tester);
    await tester.runAsync(() => c.read(playerProvider).playItem(item, [item]));
    backend.durationC.add(const Duration(minutes: 29, seconds: 54));
    await tester.pumpAndSettle();
    Finder inHeader(String t) =>
        find.descendant(of: find.byType(PlayerHeader), matching: find.text(t));
    final title = inHeader('toeic');
    final total = inHeader('29:54');
    expect(total.hitTestable(), findsOneWidget);
    expect((tester.getCenter(total).dy - tester.getCenter(title).dy).abs(), lessThan(4));
    expect(tester.getCenter(total).dx, greaterThan(tester.getCenter(title).dx));
  });

  testWidgets('settings opens as a popup over the player and closes', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Import a file to play'), findsOneWidget); // 화면 이동 없음
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('General › font and text size apply to the whole app', (tester) async {
    await pump(tester);
    final ctx = tester.element(find.text('Import a file to play'));
    expect(MediaQuery.textScalerOf(ctx).scale(10), 10);
    expect(Theme.of(ctx).textTheme.bodyMedium!.fontSize, 12); // VOX 수준 기본 크기

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Font'), findsOneWidget);
    await tester.tap(find.text('100%'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('130%').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serif').last);
    await tester.pumpAndSettle();

    final s = c.read(settingsProvider);
    expect(s.get(SettingKeys.fontSize), '130');
    expect(s.get(SettingKeys.font), 'serif');
    final after = tester.element(find.text('Import a file to play'));
    expect(MediaQuery.textScalerOf(after).scale(10), closeTo(13, 0.01));
    expect(Theme.of(after).textTheme.bodyMedium!.fontFamily, 'Times New Roman');
  });

  // OS 의 끌어다 놓기는 desktop_drop 채널 메시지로 들어온다 → 같은 메시지를 흉내 낸다
  Future<void> drop(WidgetTester tester, Offset at, List<String> paths) async {
    Future<void> send(String method, Object args) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'desktop_drop',
            const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
            (_) {});
    await send('entered', [at.dx, at.dy]);
    await tester.pump();
    await send('updated', [at.dx, at.dy]);
    await tester.pump();
    await tester.runAsync(() async {
      await send('performOperation', paths);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('drag & drop: files onto Playlist, folder onto a collection', (tester) async {
    final src = Directory(p.join(tmp.path, 'src', '해커스'))..createSync(recursive: true);
    final a = File(p.join(src.path, 'VOCA_D01.mp3'))..writeAsStringSync('x');
    File(p.join(src.path, 'VOCA_D02.mp3')).writeAsStringSync('x');
    File(p.join(src.path, 'memo.txt')).writeAsStringSync('x');
    await pump(tester);

    await drop(tester, const Offset(160, 450), [a.path]);
    final library = c.read(libraryProvider);
    expect(library.playlist().map((m) => m.title), ['VOCA_D01']);
    expect(find.text('VOCA_D01'), findsOneWidget);

    // 컬렉션 항목 위에 폴더 → 재생 가능한 파일만, 그 컬렉션에도 추가
    final id = library.createCollection('토익');
    await tester.tap(find.text('Collections'));
    await tester.pumpAndSettle();
    await drop(tester, tester.getCenter(find.text('토익')), [src.path]);
    expect(library.playlist().map((m) => m.title), ['VOCA_D01', 'VOCA_D02']);
    expect(library.collectionItems(id).map((m) => m.title), ['VOCA_D01', 'VOCA_D02']);
  });
}
