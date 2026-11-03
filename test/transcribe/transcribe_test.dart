import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/net.dart';
import 'package:maeknote/features/library/library_repo.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/models/model_store.dart';
import 'package:maeknote/features/settings/settings_repo.dart';
import 'package:maeknote/features/transcribe/audio_decoder.dart';
import 'package:maeknote/features/transcribe/stt_engine.dart';
import 'package:maeknote/features/transcribe/transcribe_service.dart';
import 'package:maeknote/features/transcribe/transcript_repo.dart';

class _Decoder implements AudioDecoder {
  double? tempo;
  @override
  Future<Float32List> decode(String path, String tmpDir,
      {void Function(double)? onProgress, double tempo = 1}) async {
    this.tempo = tempo;
    onProgress?.call(1);
    return Float32List(sttSampleRate * 20); // 20초
  }
}

class _Engine implements SttEngine {
  _Engine({this.fail = false, this.hang = false});
  final bool fail;
  final bool hang;
  String? language;

  @override
  Future<void> transcribe(Float32List samples,
      {required SttModelPaths model,
      required String language,
      required void Function(Segment) onSegment,
      required void Function(double) onProgress,
      Completer<void>? cancel}) async {
    this.language = language;
    if (fail) throw StateError('엔진 오류');
    onSegment(const Segment(100, 5000, '첫 번째 안건은 예산입니다'));
    onProgress(0.5);
    if (hang) {
      await cancel!.future;
      throw StateError('취소됨');
    }
    onSegment(const Segment(6000, 12000, '두 번째 안건은 채용입니다'));
    onProgress(1);
  }
}

void main() {
  late Directory tmp;
  late AppDatabase db;
  late SettingsRepo settings;
  late LibraryRepo library;
  late TranscriptRepo repo;
  late ModelStore store;
  late MediaItem item;
  late _Decoder decoder;

  ModelSpec spec(String id, ModelKind kind, List<String> files) => ModelSpec(
      id: id, kind: kind, name: id, tier: 0, ramMb: 1, license: 'MIT',
      minPerHour: 1,
      files: [for (final f in files) ModelFile(f, 'https://x', 'a' * 64, 1)]);
  final catalog = ModelCatalog([
    spec('vad', ModelKind.vad, ['vad.onnx']),
    spec('stt', ModelKind.stt, ['encoder.onnx', 'decoder.onnx', 'tokens.txt']),
  ]);

  void installAll() {
    for (final m in catalog.models) {
      db.db.execute('INSERT INTO installed_models VALUES (?, ?, ?, 0)',
          [m.id, m.kind.name, store.dirOf(m.id)]);
    }
  }

  TranscribeService service(SttEngine engine) => TranscribeService(
      repo: repo, models: store, settings: settings, library: library,
      decoder: decoder, engine: engine, tmpDir: tmp.path);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('maeknote_stt');
    decoder = _Decoder();
    db = AppDatabase.memory();
    settings = SettingsRepo(db);
    library = LibraryRepo(db, mediaDir: p.join(tmp.path, 'media'));
    repo = TranscriptRepo(db);
    store = ModelStore(db: db, catalog: catalog, settings: settings,
        modelsDir: p.join(tmp.path, 'models'),
        client: () => GuardedClient(NetPurpose.modelDownload, NetworkLog()),
        networkAllowed: () async => true);
    final f = File(p.join(tmp.path, 'meeting.mp4'))..writeAsStringSync('x');
    item = (await library.import([f.path])).single;
  });

  tearDown(() async {
    db.close();
    await tmp.delete(recursive: true);
  });

  test('AC4: no STT model → ModelMissingException, nothing started', () async {
    await expectLater(service(_Engine()).transcribe(item),
        throwsA(isA<ModelMissingException>()));
    expect(repo.info(item.id).status, TranscriptStatus.none);
  });

  test('success stores timed segments, status done, duration', () async {
    installAll();
    settings.set(SettingKeys.sttLanguage, 'ko');
    final engine = _Engine();
    await service(engine).transcribe(item);
    expect(engine.language, 'ko');
    final info = repo.info(item.id);
    expect(info.status, TranscriptStatus.done);
    expect(info.modelId, 'stt');
    // 기본 전사 속도 80%: 늘린 음성의 시간 × 0.8 = 원래 시간
    final segs = repo.segments(item.id);
    expect(decoder.tempo, 0.8);
    expect(segs.map((s) => (s.startMs, s.endMs)), [(80, 4000), (4800, 9600)]);
    expect(library.byId(item.id)!.durationMs, 16000);
  });

  test('speed 100% decodes as-is; out-of-range speed is clamped', () async {
    installAll();
    settings.set(SettingKeys.sttSpeed, '100');
    await service(_Engine()).transcribe(item);
    expect(decoder.tempo, 1.0);
    expect(repo.segments(item.id).map((s) => (s.startMs, s.endMs)), [(100, 5000), (6000, 12000)]);
    expect(library.byId(item.id)!.durationMs, 20000);
    expect(sttTempoOf('30'), 0.5);
    expect(sttTempoOf('abc'), 0.8);
  });

  test('engine failure → status error with message', () async {
    installAll();
    await expectLater(service(_Engine(fail: true)).transcribe(item), throwsStateError);
    final info = repo.info(item.id);
    expect(info.status, TranscriptStatus.error);
    expect(info.error, '엔진 오류');
  });

  test('cancel stops job and keeps partial segments', () async {
    installAll();
    final s = service(_Engine(hang: true));
    final job = s.transcribe(item);
    await Future<void>.delayed(Duration.zero);
    expect(s.isRunning(item.id), isTrue);
    s.cancel(item.id);
    await expectLater(job, throwsStateError);
    expect(repo.info(item.id).error, '취소됨');
    expect(repo.segments(item.id), hasLength(1));
    expect(s.isRunning(item.id), isFalse);
  });

  test('re-transcribe replaces old segments', () async {
    installAll();
    await service(_Engine()).transcribe(item);
    await service(_Engine()).transcribe(item);
    expect(repo.segments(item.id), hasLength(2));
  });

  test('search: FTS for ≥3 chars, LIKE for short query', () async {
    installAll();
    await service(_Engine()).transcribe(item);
    final segs = repo.segments(item.id);
    expect(repo.search(item.id, '안건은 예산'), {segs[0].id});
    expect(repo.search(item.id, '채용'), {segs[1].id});
    expect(repo.search(item.id, '안건'), {segs[0].id, segs[1].id});
    expect(repo.search(item.id, '"'), isEmpty);
  });

  test('segmentIndexAt finds segment at or before position', () {
    const segs = [Segment(100, 5000, 'a'), Segment(6000, 12000, 'b')];
    expect(segmentIndexAt(segs, 0), -1);
    expect(segmentIndexAt(segs, 100), 0);
    expect(segmentIndexAt(segs, 5500), 0);
    expect(segmentIndexAt(segs, 6000), 1);
    expect(segmentIndexAt(segs, 99999), 1);
  });

  test('WAV parser handles header with unknown data size', () {
    final b = BytesBuilder()
      ..add('RIFF'.codeUnits)
      ..add([0, 0, 0, 0])
      ..add('WAVE'.codeUnits)
      ..add('fmt '.codeUnits)
      ..add([16, 0, 0, 0])
      ..add(List.filled(16, 0))
      ..add('data'.codeUnits)
      ..add([0xFF, 0xFF, 0xFF, 0xFF])
      ..add([0x00, 0x40, 0x00, 0xC0]); // 16384, -16384
    expect(parseWavS16(b.toBytes()), [0.5, -0.5]);
    expect(() => parseWavS16(Uint8List(4)), throwsFormatException);
  });
}
