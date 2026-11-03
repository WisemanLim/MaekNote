import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/providers.dart';
import 'package:maeknote/core/theme.dart';
import 'package:maeknote/features/library/library_repo.dart';
import 'package:maeknote/features/transcribe/note_view.dart';
import 'package:maeknote/features/transcribe/stt_engine.dart';
import 'package:maeknote/features/transcribe/transcript_repo.dart';

import '../support/fakes.dart';
import '../support/i18n.dart';

void main() {
  late Directory tmp;
  late AppDatabase db;
  late FakeBackend backend;
  late ProviderContainer container;
  late List<MediaItem> items;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('maeknote_view');
    db = AppDatabase.memory();
    backend = FakeBackend();
    container = ProviderContainer(overrides: [
      appDirProvider.overrideWithValue(tmp.path),
      dbProvider.overrideWithValue(db),
      audioBackendProvider.overrideWithValue(backend),
    ]);
    final files = [
      for (final n in ['a.mp3', 'b.mp3'])
        (File(p.join(tmp.path, n))..writeAsStringSync('x')).path
    ];
    items = await container.read(libraryProvider).import(files);
    final repo = container.read(transcriptRepoProvider);
    for (final it in items) {
      repo.start(it.id, 'whisper-tiny', 'ko');
      for (var i = 0; i < 40; i++) {
        repo.addSegment(it.id, Segment(i * 5000, i * 5000 + 4000, '${it.title} 문장 $i 회의 내용'));
      }
      repo.update(it.id, TranscriptStatus.done, 1);
    }
  });

  tearDown(() {
    container.dispose();
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: withI18n(MaterialApp(
        theme: buildVoxTheme(),
        home: Scaffold(body: NoteView(summary: (_) => const Text('SUMMARY'))),
      )),
    ));
  }

  bool isActive(WidgetTester tester, String text) => tester
      .getSemantics(find.bySemanticsLabel(RegExp(RegExp.escape(text))))
      .flagsCollection
      .isSelected
      .toBoolOrNull() == true;

  testWidgets('shows hint when nothing is playing', (tester) async {
    await pump(tester);
    expect(find.textContaining('재생목록에서 파일을 선택'), findsOneWidget);
  });

  testWidgets('AC1: playback position highlights and reveals segment within 0.5s',
      (tester) async {
    final handle = tester.ensureSemantics();
    await container.read(playerProvider).playItem(items[0], items);
    await pump(tester);
    expect(find.text('a 문장 0 회의 내용'), findsOneWidget);

    backend.positionC.add(const Duration(seconds: 151)); // 30번째 구간 (150~154s)
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(isActive(tester, 'a 문장 30 회의'), isTrue);
    expect(isActive(tester, 'a 문장 0 회의'), isFalse);
    // 자동 스크롤로 화면에 보임
    final rect = tester.getRect(find.text('a 문장 30 회의 내용'));
    expect(rect.top, inInclusiveRange(0, 800));
    handle.dispose();
  });

  testWidgets('AC2: tapping a segment seeks to its start', (tester) async {
    await container.read(playerProvider).playItem(items[0], items);
    await pump(tester);
    await tester.tap(find.text('a 문장 2 회의 내용'));
    await tester.pump();
    expect(backend.seeks.last, const Duration(milliseconds: 10000));
  });

  testWidgets('search marks matches and jumps between them', (tester) async {
    await container.read(playerProvider).playItem(items[0], items);
    await pump(tester);
    await tester.enterText(find.byType(TextField), '문장 3');
    await tester.pump();
    // '문장 3', '문장 30'~'문장 39' → 11건
    expect(find.text(' 0/11'), findsOneWidget);
    await tester.tap(find.byTooltip('다음 결과'));
    await tester.pumpAndSettle();
    expect(find.text(' 1/11'), findsOneWidget);
  });

  testWidgets('summary sub-tab is reachable', (tester) async {
    await container.read(playerProvider).playItem(items[1], items);
    await pump(tester);
    await tester.tap(find.text('요약'));
    await tester.pumpAndSettle();
    expect(find.text('SUMMARY'), findsOneWidget);
  });
}
