import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:maeknote/app.dart';
import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/i18n.dart';
import 'package:maeknote/core/providers.dart';
import 'package:maeknote/features/cloud/cloud_llm.dart';
import 'package:maeknote/features/export/exporter.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/settings/settings_repo.dart';
import 'package:maeknote/features/settings/settings_view.dart';
import 'package:maeknote/features/summary/summarizer.dart';

import 'support/fakes.dart';
import 'support/i18n.dart';

class _NoSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String? value) async {}
}

Set<String> _placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  final packs = loadPacks();

  test('bundled packs: en + ko with identical keys and placeholders', () {
    expect(packs.packs.keys, containsAll(['en', 'ko']));
    expect(packs.packs['en']!.name, 'English');
    expect(packs.packs['ko']!.name, '한국어');
    final en = packs.packs['en']!.strings, ko = packs.packs['ko']!.strings;
    expect(ko.keys.toSet(), en.keys.toSet());
    for (final k in en.keys) {
      expect(en[k], isNotEmpty, reason: k);
      expect(ko[k], isNotEmpty, reason: k);
      expect(_placeholders(ko[k]!), _placeholders(en[k]!), reason: k);
    }
  });

  test('every key referenced in lib/ exists in the English pack', () {
    final en = packs.packs['en']!.strings;
    final used = <String>{};
    final literal = RegExp(
        r"""(?:tr|trError|AppError|ModelDownloadException|CloudException)\(\s*'([a-zA-Z]+\.[\w.]+)'""");
    final keyArg = RegExp(r"""'((?:settings|cloud|storage|lang|length|summary|export|models|error)\.[\w.]+)'""");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      // 설정 저장 키 상수는 언어셋 키가 아님
      if (!f.path.endsWith('.dart') || f.path.endsWith('settings_repo.dart')) continue;
      final src = f.readAsStringSync();
      used.addAll(literal.allMatches(src).map((m) => m.group(1)!));
      used.addAll(keyArg.allMatches(src).map((m) => m.group(1)!));
    }
    // 코드에서 조합해 만드는 키
    used.addAll([for (final t in SummaryType.values) t.labelKey]);
    used.addAll([for (final k in ModelKind.values) 'models.kind.${k.name}']);
    used.addAll([for (final f in ExportFormat.values) 'export.${f.name}']);
    used.addAll([for (final (_, k) in SettingsPage.tabs) k]);
    used.removeWhere((k) => k.endsWith('.')); // 접두사만 있는 조합 부분
    final missing = used.where((k) => !en.containsKey(k)).toList()..sort();
    expect(missing, isEmpty);
    expect(used.length, greaterThan(100));
  });

  test('default English, unknown language → English, missing key → English → key', () {
    expect(SettingsRepo.defaults[SettingKeys.language], 'en');
    expect(I18n(packs, 'xx').code, 'en');
    final partial = LanguagePacks.fromJson({
      'en': '{"_name":"English","a":"A {n}","b":"B"}',
      'fr': '{"_name":"Français","a":"Un {n}"}',
    });
    final fr = I18n(partial, 'fr');
    expect(fr.t('a', {'n': 3}), 'Un 3');
    expect(fr.t('b'), 'B');
    expect(fr.t('zzz'), 'zzz');
  });

  test('AppError translates and survives DB encoding', () {
    final ko = I18n(packs, 'ko'), en = I18n(packs, 'en');
    const e = AppError('error.downloadHttp', {'code': 503});
    expect(en.error(e), 'Download failed (HTTP 503)');
    expect(ko.error(AppError.decode(e.encode())), '다운로드 실패 (HTTP 503)');
    expect(AppError.decode('plain text'), 'plain text');
    expect(en.error(StateError('x')), contains('x'));
  });

  testWidgets('extra JSON in app data folder adds a language and overrides strings',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('maeknote_i18n');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, 'ja.json'))
        .writeAsStringSync('{"_name":"日本語","app.settings":"設定"}');
    File(p.join(dir.path, 'ko.json'))
        .writeAsStringSync('{"player.play":"플레이"}');
    File(p.join(dir.path, 'bad.json')).writeAsStringSync('{not json');
    final loaded = (await tester.runAsync(
        () => LanguagePacks.load(rootBundle, extraDir: dir.path)))!;
    expect(loaded.packs.keys, containsAll(['en', 'ko', 'ja']));
    expect(loaded.packs.containsKey('bad'), isFalse);
    final ja = I18n(loaded, 'ja');
    expect(ja.t('app.settings'), '設定');
    expect(ja.t('player.pause'), 'Pause'); // 없는 키는 English
    final ko = I18n(loaded, 'ko');
    expect(ko.t('player.play'), '플레이');
    expect(ko.t('player.pause'), '일시정지'); // 나머지 번들 문자열 유지
    expect(ko.available.map((l) => l.name), contains('日本語'));
  });

  testWidgets('switching app language in Settings updates the UI live', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDirProvider.overrideWithValue(Directory.systemTemp.path),
        dbProvider.overrideWithValue(db),
        audioBackendProvider.overrideWithValue(FakeBackend()),
        secretStoreProvider.overrideWithValue(_NoSecrets()),
        catalogProvider.overrideWithValue(
            ModelCatalog.parse(File('assets/models/manifest.json').readAsStringSync())),
        deviceProvider.overrideWithValue(const DeviceSpec(ramMb: 8192, platform: 'x')),
        languagePacksProvider.overrideWithValue(packs),
      ],
      child: const App(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('App language'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('한국어').last);
    await tester.pumpAndSettle();
    expect(find.text('앱 언어'), findsOneWidget);
    expect(find.text('설정'), findsOneWidget);
    // 설정은 팝업 — 닫기 버튼도 한국어
    expect(find.byTooltip('닫기'), findsOneWidget);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('파일을 가져와 재생하세요'), findsOneWidget);
  });
}
