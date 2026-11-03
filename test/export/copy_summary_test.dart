// R10: 내보내기 메뉴 → 요약 클립보드 복사
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/i18n.dart';
import 'package:maeknote/core/providers.dart';
import 'package:maeknote/core/theme.dart';
import 'package:maeknote/features/export/export_action.dart';
import 'package:maeknote/features/export/exporter.dart';
import 'package:maeknote/features/library/library_repo.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/settings/settings_repo.dart';
import 'package:maeknote/features/summary/summarizer.dart';
import 'package:maeknote/features/summary/summary_service.dart';

import '../support/i18n.dart';

void main() {
  final ko = I18n(loadPacks(), 'ko');
  final meeting = StoredSummary(
      SummaryType.meeting,
      'm',
      const [
        SummarySection('결정사항', [SummaryItem('예산 10% 증액', 6800, 12800)]),
        SummarySection('액션 아이템', [SummaryItem('공고 게시 — 김팀장', null, null)]),
      ],
      DateTime(2026));

  test('summary → Markdown with type, sections and time links (no transcript)', () {
    expect(exportSummary('주간 회의', meeting, tr: ko.t),
        '# 주간 회의\n\n## 회의록\n\n### 결정사항\n- 예산 10% 증액 `[0:06]`\n\n### 액션 아이템\n- 공고 게시 — 김팀장\n');
  });

  late Directory tmp;
  late AppDatabase db;
  late ProviderContainer c;
  late MediaItem item;
  String? clipboard;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('maeknote_copy');
    db = AppDatabase.memory();
    c = ProviderContainer(overrides: [
      appDirProvider.overrideWithValue(tmp.path),
      dbProvider.overrideWithValue(db),
      catalogProvider.overrideWithValue(const ModelCatalog([])),
      summaryTemplatesProvider.overrideWithValue(loadTemplates()),
    ]);
    final f = File(p.join(tmp.path, 'weekly.mp3'))..writeAsStringSync('x');
    item = (await c.read(libraryProvider).import([f.path])).single;
    clipboard = null;
  });

  tearDown(() {
    c.dispose();
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: withI18n(MaterialApp(
        theme: buildVoxTheme(),
        home: Scaffold(appBar: AppBar(actions: [ExportButton(item: item)])),
      )),
    ));
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('내보내기'));
    await tester.pumpAndSettle();
  }

  testWidgets('copies the summary shown in the Summary tab', (tester) async {
    db.db.execute(
        'INSERT INTO summaries(media_id, type, model_id, body, created_at) VALUES (?, ?, ?, ?, ?)',
        [item.id, 'meeting', 'm', encodeSections(meeting.sections), 0]);
    c.read(settingsProvider).set(SettingKeys.summaryType, 'meeting');
    await pump(tester);
    await openMenu(tester);
    await tester.tap(find.text('요약 클립보드에 복사'));
    await tester.pumpAndSettle();
    expect(clipboard, startsWith('# weekly\n\n## 회의록'));
    expect(clipboard, contains('- 예산 10% 증액 `[0:06]`'));
    expect(find.text('요약을 클립보드에 복사했습니다'), findsOneWidget);
  });

  testWidgets('disabled when the shown type has no summary yet', (tester) async {
    c.read(settingsProvider).set(SettingKeys.summaryType, 'lecture');
    await pump(tester);
    await openMenu(tester);
    final entry = tester.widget<PopupMenuItem<Object>>(find.ancestor(
        of: find.text('요약 클립보드에 복사'), matching: find.byType(PopupMenuItem<Object>)));
    expect(entry.enabled, isFalse);
    await tester.tap(find.text('요약 클립보드에 복사'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(clipboard, isNull);
  });
}
