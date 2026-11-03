import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/i18n.dart';
import 'package:maeknote/core/providers.dart';
import 'package:maeknote/core/theme.dart';
import 'package:maeknote/features/library/library_repo.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/summary/summarizer.dart';
import 'package:maeknote/features/transcribe/note_view.dart';
import 'package:maeknote/features/transcribe/stt_engine.dart';
import 'package:maeknote/features/transcribe/transcribe_service.dart';
import 'package:maeknote/features/transcribe/transcript_repo.dart';
import 'package:maeknote/features/summary/summary_view.dart';

import '../support/fakes.dart';
import '../support/i18n.dart';

class _Engine implements LlmEngine {
  _Engine(this.reply);
  final String Function(String user) reply;
  final calls = <String>[];
  @override
  String get id => 'fake-llm';
  @override
  Future<String> complete(String system, String user, {int maxTokens = 1024}) async {
    calls.add(user);
    return reply(user);
  }
}

const _segs = [
  Segment(0, 4000, '오늘 회의를 시작하겠습니다 첫 번째 안건은 마케팅 예산입니다'),
  Segment(5000, 9000, '예산은 십 퍼센트 늘리기로 결정했습니다'),
  Segment(10000, 15000, '두 번째 안건은 신규 채용입니다'),
];

void main() {
  group('parseSummary', () {
    test('sections, bullets, single and range refs map to segment times', () {
      final out = parseSummary('''
## 안건
- 마케팅 예산 논의 [S0]
- 신규 채용 [S2]
## 결정사항
* 예산 10% 증액 [S0-S1]
1. 담당자 미정
''', _segs);
      expect(out.map((s) => s.title), ['안건', '결정사항']);
      expect(out[0].items[0].text, '마케팅 예산 논의');
      expect((out[0].items[1].startMs, out[0].items[1].endMs), (10000, 15000));
      expect((out[1].items[0].startMs, out[1].items[0].endMs), (0, 9000));
    });

    test('missing refs fall back to best word overlap; duplicates removed', () {
      final out = parseSummary('- 신규 채용 안건\n- 신규 채용 안건\n- zzz', _segs);
      expect(out.single.title, '요약');
      expect(out.single.items.map((i) => i.text), ['신규 채용 안건', 'zzz']);
      expect(out.single.items[0].startMs, 10000);
      expect(out.single.items[1].startMs, isNull);
    });

    test('out-of-range refs and non-bullet lines are ignored', () {
      final out = parseSummary('설명 문장\n- 항목 [S99]', _segs);
      expect(out.single.items.single.text, '항목');
    });

    test('roundtrip JSON', () {
      final s = parseSummary('## A\n- x [S1]', _segs);
      expect(encodeSections(decodeSections(encodeSections(s))), encodeSections(s));
    });
  });

  group('Summarizer (templates)', () {
    final templates = loadTemplates();

    test('researched templates: 5 types, ko/en titles and guides, prompts', () {
      expect(templates.templates.keys.toSet(), SummaryType.values.toSet());
      for (final t in templates.templates.values) {
        expect(t.sections.length, greaterThanOrEqualTo(2));
        for (final sec in t.sections) {
          for (final lang in ['ko', 'en']) {
            expect(sec.title[lang], isNotEmpty, reason: sec.id);
            expect(sec.guide[lang], isNotEmpty, reason: sec.id);
          }
          expect(sec.max, greaterThan(0));
        }
      }
      final meeting = templates.templates[SummaryType.meeting]!.sections.map((s) => s.id);
      expect(meeting, containsAllInOrder(['overview', 'discussion', 'decisions', 'actions']));
      final lecture = templates.templates[SummaryType.lecture]!.sections.map((s) => s.id);
      expect(lecture, containsAll(['cues', 'summary'])); // 코넬 노트
      for (final lang in ['ko', 'en']) {
        final p = templates.prompts[lang]!;
        expect(p['refine'], contains('{material}'));
        for (final k in ['{material}', '{purpose}', '{title}', '{guide}', '{max}', '{none}']) {
          expect(p['section'], contains(k), reason: '$lang $k');
        }
      }
      expect(templates.lang('fr'), 'en');
    });

    test('short transcript → one call per section, template order, empty sections dropped',
        () async {
      final e = _Engine((u) {
        if (u.contains('지금 쓸 부분: 결정사항')) return '- 예산을 10% 늘리기로 결정 [S1]';
        if (u.contains('지금 쓸 부분: 안건별 논의')) {
          return '- 마케팅 예산: 증액 논의 [S0-S1]\n- 신규 채용: 공고 일정 [S2]';
        }
        return '- 없음';
      });
      final out = await Summarizer(e, templates).summarize(_segs, type: SummaryType.meeting);
      expect(e.calls, hasLength(5));
      expect(e.calls.first, contains('문서 종류: 회의록'));
      expect(e.calls.first, contains('[S2] 두 번째 안건은 신규 채용입니다'));
      expect(e.calls[3], contains('누가 무엇을 언제까지'));
      expect(out.map((s) => s.title), ['안건별 논의', '결정사항']);
      expect((out[0].items[0].startMs, out[0].items[0].endMs), (0, 9000));
      expect(out[1].items.single.startMs, 5000);
    });

    test('English output language → English prompts and section titles', () async {
      final e = _Engine((u) => u.contains('Section to write now: Decisions')
          ? '- Budget raised by 10% [S1]'
          : '- None');
      final out = await Summarizer(e, templates)
          .summarize(_segs, type: SummaryType.meeting, language: 'en');
      expect(e.calls.first, contains('Document type: meeting minutes'));
      expect(out.single.title, 'Decisions');
    });

    test('long transcript → refined notes per chunk (global S numbers) then sections',
        () async {
      final long = [
        for (var i = 0; i < 30; i++) Segment(i * 1000, i * 1000 + 900, '문장 $i ${'가' * 100}')
      ];
      final progress = <(int, int)>[];
      final e = _Engine((u) =>
          u.contains('<전사본>') ? '- 정제된 사실 [S25]' : '- 핵심 개념 정리 [S25]');
      final out = await Summarizer(e, templates, maxChunkChars: 1000).summarize(long,
          type: SummaryType.lecture, onProgress: (d, t) => progress.add((d, t)));
      final refines = e.calls.where((c) => c.contains('<전사본>')).toList();
      final sections = e.calls.where((c) => c.contains('<자료>')).toList();
      expect(refines.length, greaterThan(1));
      expect(sections, hasLength(5));
      expect(refines[1], isNot(contains('[S0] 문장 0')));
      expect(sections.first, contains('- 정제된 사실 [S25]'));
      expect(sections.first, isNot(contains('문장 0')));
      expect(progress.last, (refines.length + 5, refines.length + 5));
      expect(out.first.items.single.startMs, 25000);
    });

    test('length setting scales the item limit and truncates', () async {
      final e = _Engine((_) => [for (var i = 0; i < 9; i++) '- 항목 $i [S0]'].join('\n'));
      final short = await Summarizer(e, templates)
          .summarize(_segs, type: SummaryType.brief, length: 'short');
      expect(short.last.items, hasLength(3)); // key points 5 → 3
      expect(e.calls.last, contains('최대 3개'));
      final long = await Summarizer(e, templates)
          .summarize(_segs, type: SummaryType.brief, length: 'long');
      expect(long.first.items, hasLength(2)); // TL;DR 1 → 2 (round 1.5)
      expect(long.last.items, hasLength(8)); // 5 → 8
    });

    test('every summary type has a distinct label', () {
      final en = I18n(loadPacks(), 'en');
      expect(SummaryType.values.map((t) => en.t(t.labelKey)).toSet(), hasLength(5));
      expect(SummaryType.values.every((t) => en.t(t.labelKey) != t.labelKey), isTrue);
    });
  });

  group('SummaryService + view', () {
    late Directory tmp;
    late AppDatabase db;
    late FakeBackend backend;
    late ProviderContainer container;
    late MediaItem item;
    late _Engine engine;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('maeknote_sum');
      db = AppDatabase.memory();
      backend = FakeBackend();
      engine = _Engine((u) => u.contains('지금 쓸 부분: 결정사항') ? '- 예산 증액 [S1]' : '- 없음');
      container = ProviderContainer(overrides: [
        appDirProvider.overrideWithValue(tmp.path),
        dbProvider.overrideWithValue(db),
        audioBackendProvider.overrideWithValue(backend),
        catalogProvider.overrideWithValue(ModelCatalog([
          ModelSpec(id: 'llm', kind: ModelKind.llm, name: 'llm', tier: 0, ramMb: 1,
              license: 'MIT', minPerHour: 1,
              files: [ModelFile('model.gguf', 'https://x', 'a' * 64, 1)]),
        ])),
        deviceProvider.overrideWithValue(const DeviceSpec(ramMb: 8192, platform: 'x')),
        localLlmProvider.overrideWithValue((spec, path) => engine),
        summaryTemplatesProvider.overrideWithValue(loadTemplates()),
      ]);
      final f = File(p.join(tmp.path, 'm.mp3'))..writeAsStringSync('x');
      item = (await container.read(libraryProvider).import([f.path])).single;
      final repo = container.read(transcriptRepoProvider);
      repo.start(item.id, 'stt', 'ko');
      for (final s in _segs) {
        repo.addSegment(item.id, s);
      }
      repo.update(item.id, TranscriptStatus.done, 1);
    });

    tearDown(() {
      container.dispose();
      db.close();
      tmp.deleteSync(recursive: true);
    });

    test('no LLM installed → ModelMissingException(llm)', () async {
      await expectLater(
          container.read(summaryServiceProvider).summarize(item.id, SummaryType.brief),
          throwsA(isA<ModelMissingException>()
              .having((e) => e.kind, 'kind', ModelKind.llm)));
    });

    test('saves latest summary per type with model id', () async {
      db.db.execute("INSERT INTO installed_models VALUES ('llm', 'llm', '/x', 0)");
      final svc = container.read(summaryServiceProvider);
      final s = await svc.summarize(item.id, SummaryType.meeting);
      expect(s.modelId, 'fake-llm');
      expect(svc.latest(item.id, SummaryType.meeting)!.sections.single.items.single.startMs, 5000);
      expect(svc.latest(item.id, SummaryType.lecture), isNull);
    });

    testWidgets('AC3: time link seeks to source and switches to transcript tab',
        (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      db.db.execute("INSERT INTO installed_models VALUES ('llm', 'llm', '/x', 0)");
      await container.read(playerProvider).playItem(item, [item]);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: withI18n(MaterialApp(
          theme: buildVoxTheme(),
          home: Scaffold(
              body: NoteView(summary: (it) => SummaryView(item: it))),
        )),
      ));
      await tester.tap(find.text('요약'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('회의록'));
      await tester.pump();
      await tester.tap(find.text('생성'));
      await tester.pumpAndSettle();
      expect(find.text('예산 증액'), findsOneWidget);

      await tester.tap(find.text('[0:05]'));
      await tester.pumpAndSettle();
      expect(backend.seeks.last, const Duration(seconds: 5));
      backend.positionC.add(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      // 전사 탭으로 전환되고 해당 구간이 선택(강조)됨
      expect(find.text('예산은 십 퍼센트 늘리기로 결정했습니다'), findsOneWidget);
      final row = tester.getSemantics(find.bySemanticsLabel(RegExp('예산은 십 퍼센트')));
      expect(row.flagsCollection.isSelected.toBoolOrNull(), isTrue);
      handle.dispose();
    });
  });
}
