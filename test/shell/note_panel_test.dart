import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:maeknote/app.dart';
import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/providers.dart';
import 'package:maeknote/core/window_sizer.dart';
import 'package:maeknote/core/i18n.dart';
import 'package:maeknote/features/cloud/cloud_llm.dart';
import 'package:maeknote/features/library/library_repo.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/transcribe/audio_decoder.dart';
import 'package:maeknote/features/transcribe/stt_engine.dart';

import '../support/fakes.dart';
import '../support/i18n.dart';

class _NoSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String? value) async {}
}

class _Decoder implements AudioDecoder {
  @override
  Future<Float32List> decode(String path, String tmpDir,
          {void Function(double)? onProgress, double tempo = 1}) async =>
      Float32List(sttSampleRate);
}

/// 첫 문장을 낸 뒤 [release] 될 때까지 기다리는 엔진 (전사 진행 중 상태 유지)
class _GatedEngine implements SttEngine {
  final release = Completer<void>();
  @override
  Future<void> transcribe(Float32List samples,
      {required SttModelPaths model,
      required String language,
      required void Function(Segment) onSegment,
      required void Function(double) onProgress,
      Completer<void>? cancel}) async {
    onSegment(const Segment(0, 2000, '첫 번째 안건은 예산입니다'));
    onProgress(0.5);
    await Future.any([release.future, cancel!.future]);
    if (cancel.isCompleted) throw const AppError('error.cancelled');
    onSegment(const Segment(3000, 5000, '두 번째 안건은 채용입니다'));
    onProgress(1);
  }
}

class _FakeSizer implements WindowSizer {
  _FakeSizer(this.current);
  Size current;
  final calls = <Size>[];
  @override
  Future<Size> size() async => current;
  @override
  Future<void> setSize(Size size) async {
    calls.add(size);
    current = size;
  }
}

void main() {
  test('opening expands VOX window to 737 wide; closing returns to 322', () async {
    final s = _FakeSizer(const Size(322, 574));
    await applyNotePanel(s, true);
    expect(s.current, const Size(737, 574));
    await applyNotePanel(s, false);
    expect(s.current, const Size(322, 574));
  });

  test('a window the user already widened is not shrunk when opening', () async {
    final s = _FakeSizer(const Size(1200, 800));
    await applyNotePanel(s, true);
    expect(s.calls, isEmpty);
    final small = _FakeSizer(const Size(322, 574));
    await applyNotePanel(small, false);
    expect(small.calls, isEmpty);
  });

  late Directory tmp;
  late AppDatabase db;
  late _FakeSizer sizer;
  late _GatedEngine engine;
  late FakeBackend backend;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('maeknote_panel');
    db = AppDatabase.memory();
    sizer = _FakeSizer(const Size(322, 574));
    engine = _GatedEngine();
    backend = FakeBackend();
    ModelSpec spec(String id, ModelKind kind, List<String> files) => ModelSpec(
        id: id, kind: kind, name: id, tier: 0, ramMb: 1, license: 'MIT', minPerHour: 1,
        files: [for (final f in files) ModelFile(f, 'https://x', 'a' * 64, 1)]);
    c = ProviderContainer(overrides: [
      appDirProvider.overrideWithValue(tmp.path),
      dbProvider.overrideWithValue(db),
      audioBackendProvider.overrideWithValue(backend),
      secretStoreProvider.overrideWithValue(_NoSecrets()),
      catalogProvider.overrideWithValue(ModelCatalog([
        spec('vad', ModelKind.vad, ['vad.onnx']),
        spec('stt', ModelKind.stt, ['encoder.onnx', 'decoder.onnx', 'tokens.txt']),
      ])),
      deviceProvider.overrideWithValue(const DeviceSpec(ramMb: 8192, platform: 'x')),
      languagePacksProvider.overrideWithValue(loadPacks()),
      isDesktopProvider.overrideWithValue(true),
      windowSizerProvider.overrideWithValue(sizer),
      audioDecoderProvider.overrideWithValue(_Decoder()),
      sttEngineProvider.overrideWithValue(engine),
    ]);
    for (final id in ['vad', 'stt']) {
      db.db.execute('INSERT INTO installed_models VALUES (?, ?, ?, 0)', [id, id, '/x']);
    }
  });

  tearDown(() {
    c.dispose();
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<List<MediaItem>> importFiles(WidgetTester tester, List<String> names) async {
    final paths = [
      for (final n in names) (File(p.join(tmp.path, n))..writeAsStringSync('x')).path
    ];
    return (await tester.runAsync(() => c.read(libraryProvider).import(paths)))!;
  }

  Future<void> startFromMenu(WidgetTester tester, int index) async {
    await tester.tap(find.byTooltip('Item menu').at(index));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transcribe'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    engine.release.complete();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  testWidgets('transcription runs in the background; finished transcript opens in the panel',
      (tester) async {
    tester.view.physicalSize = const Size(322, 546);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await importFiles(tester, ['meeting.mp3']);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const App()));
    await tester.pumpAndSettle();

    await startFromMenu(tester, 0);
    // 백그라운드: 패널·재생은 그대로, 목록 배지로 진행률만
    expect(c.read(notePanelProvider), isFalse);
    expect(c.read(playerProvider).current, isNull);
    expect(find.text('60%'), findsOneWidget); // 디코딩 20% + 전사 50% × 0.8

    // 진행 중에 노트를 열어도 부분 문장 대신 진행 안내만
    tester.view.physicalSize = const Size(737, 546);
    await tester.tap(find.text('meeting'));
    await tester.pump();
    c.read(notePanelProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(find.text('첫 번째 안건은 예산입니다'), findsNothing);
    expect(find.textContaining('Transcribing in the background'), findsOneWidget);
    c.read(notePanelProvider.notifier).state = false;
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(322, 546);
    await tester.pump();

    // 완료 → 노트 패널이 펼쳐지고 전체 전사 표시
    await finish(tester);
    expect(c.read(notePanelProvider), isTrue);
    expect(sizer.calls.last, const Size(737, 574));
    tester.view.physicalSize = const Size(737, 546);
    await tester.pumpAndSettle();
    expect(find.text('첫 번째 안건은 예산입니다'), findsOneWidget);
    expect(find.text('두 번째 안건은 채용입니다'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 패널의 닫기 버튼 → 플레이어 너비로 복귀
    await tester.tap(find.byTooltip('Close notes'));
    await tester.pumpAndSettle();
    expect(c.read(notePanelProvider), isFalse);
    expect(sizer.calls.last, const Size(322, 574));
  });

  testWidgets('finishing while another file plays → "View" notice, playback untouched',
      (tester) async {
    tester.view.physicalSize = const Size(322, 546);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final items = await importFiles(tester, ['meeting.mp3', 'music.mp3']);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const App()));
    await tester.pumpAndSettle();
    await tester.runAsync(() => c.read(playerProvider).playItem(items[1], items));
    await tester.pump();

    await startFromMenu(tester, 0);
    await finish(tester);
    expect(c.read(playerProvider).current?.title, 'music');
    expect(c.read(notePanelProvider), isFalse);
    expect(find.text('Transcription finished: meeting'), findsOneWidget);

    await tester.tap(find.text('View'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(c.read(playerProvider).current?.title, 'meeting');
    expect(c.read(notePanelProvider), isTrue);
  });
}
