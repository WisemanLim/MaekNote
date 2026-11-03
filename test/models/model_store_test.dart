import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/net.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/models/model_store.dart';
import 'package:maeknote/features/settings/settings_repo.dart';

/// Range 요청을 지원하는 정적 파일 서버
class _Server {
  _Server(this.files);
  final Map<String, List<int>> files;
  final rangeHeaders = <String?>[];
  late HttpServer server;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = files[req.uri.path];
      if (body == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final range = req.headers.value('range');
      rangeHeaders.add(range);
      var start = 0;
      if (range != null) {
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        req.response.statusCode = 206;
      }
      req.response.add(body.sublist(start));
      await req.response.close();
    });
  }

  String url(String path) => 'http://127.0.0.1:${server.port}$path';
}

String _sha(List<int> b) => sha256.convert(b).toString();

void main() {
  late Directory tmp;
  late AppDatabase db;
  late SettingsRepo settings;
  late NetworkLog log;
  late _Server server;
  final vadBytes = utf8.encode('vad-model');
  final encBytes = List<int>.generate(50000, (i) => i % 251);
  final tokBytes = utf8.encode('tokens');

  ModelCatalog catalog({String? encSha}) => ModelCatalog([
        ModelSpec(
            id: 'vad', kind: ModelKind.vad, name: 'VAD', tier: 0, ramMb: 10,
            license: 'MIT', minPerHour: 0,
            files: [ModelFile('vad.onnx', server.url('/vad'), _sha(vadBytes), vadBytes.length)]),
        ModelSpec(
            id: 'stt-a', kind: ModelKind.stt, name: 'STT A', tier: 0, ramMb: 100,
            license: 'MIT', minPerHour: 5,
            files: [
              ModelFile('encoder.onnx', server.url('/enc'), encSha ?? _sha(encBytes), encBytes.length),
              ModelFile('tokens.txt', server.url('/tok'), _sha(tokBytes), tokBytes.length),
            ]),
      ]);

  ModelStore store(ModelCatalog c, {bool network = true}) => ModelStore(
        db: db,
        catalog: c,
        settings: settings,
        modelsDir: p.join(tmp.path, 'models'),
        client: () => GuardedClient(NetPurpose.modelDownload, log),
        networkAllowed: () async => network,
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('maeknote_models');
    db = AppDatabase.memory();
    settings = SettingsRepo(db);
    log = NetworkLog();
    server = _Server({'/vad': vadBytes, '/enc': encBytes, '/tok': tokBytes});
    await server.start();
  });

  tearDown(() async {
    await server.server.close(force: true);
    db.close();
    await tmp.delete(recursive: true);
  });

  test('bundled manifest is complete and verifiable', () {
    final c = ModelCatalog.parse(File('assets/models/manifest.json').readAsStringSync());
    for (final m in c.models) {
      for (final f in m.files) {
        expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: m.id);
        expect(Uri.parse(f.url).scheme, 'https');
        expect(f.size, greaterThan(0));
      }
    }
    // STT · LLM 모두 T0(소형)부터 고사양까지 제공
    for (final kind in [ModelKind.stt, ModelKind.llm]) {
      final tiers = c.ofKind(kind).map((m) => m.tier).toSet();
      expect(tiers, containsAll([0, 1, 2, 3]), reason: kind.name);
    }
    expect(c.ofKind(ModelKind.llm).map((m) => m.tier), contains(4));
  });

  test('device tier, fit and recommendation', () {
    final c = ModelCatalog.parse(File('assets/models/manifest.json').readAsStringSync());
    expect(const DeviceSpec(ramMb: 4096, platform: 'x').tier, 0);
    expect(const DeviceSpec(ramMb: 8192, platform: 'x').tier, 1);
    expect(const DeviceSpec(ramMb: 16384, platform: 'x').tier, 2);
    expect(const DeviceSpec(ramMb: 65536, platform: 'x').tier, 4);

    const phone = DeviceSpec(ramMb: 6144, platform: 'android');
    expect(phone.fit(c.byId('qwen2.5-14b')!), Fit.unsupported);
    expect(phone.fit(c.byId('whisper-tiny')!), Fit.ok);
    expect(c.recommended(ModelKind.stt, phone)!.id, 'whisper-small');
    expect(c.recommended(ModelKind.llm, phone)!.id, 'qwen2.5-1.5b');

    const mac = DeviceSpec(ramMb: 16384, platform: 'macos');
    expect(c.recommended(ModelKind.stt, mac)!.tier, 2);
    expect(c.recommended(ModelKind.llm, mac)!.id, 'qwen3-4b');
  });

  test('install STT downloads VAD first, verifies hashes, records network use', () async {
    final s = store(catalog());
    await s.install(s.catalog.byId('stt-a')!);
    expect(s.isInstalled('vad'), isTrue);
    expect(s.isInstalled('stt-a'), isTrue);
    expect(File(s.filesOf(s.catalog.byId('stt-a')!)['encoder.onnx']!).readAsBytesSync(), encBytes);
    expect(s.defaultModel(ModelKind.stt)!.id, 'stt-a');
    expect(log.of(NetPurpose.modelDownload).length, 3);
    expect(log.of(NetPurpose.cloud), isEmpty);
  });

  test('tampered file (hash mismatch) is rejected and removed', () async {
    final s = store(catalog(encSha: 'a' * 64));
    await expectLater(s.install(s.catalog.byId('stt-a')!),
        throwsA(isA<ModelDownloadException>()));
    expect(s.isInstalled('stt-a'), isFalse);
    final dir = Directory(s.dirOf('stt-a'));
    expect(dir.listSync().whereType<File>().map((f) => p.basename(f.path)),
        isNot(contains(anyOf('encoder.onnx', 'encoder.onnx.part'))));
    expect(s.downloads['stt-a']!.error,
        isA<ModelDownloadException>().having((e) => e.key, 'key', 'error.hashMismatch'));
  });

  test('partial download resumes with Range header', () async {
    final s = store(catalog());
    final dir = Directory(s.dirOf('stt-a'))..createSync(recursive: true);
    File(p.join(dir.path, 'encoder.onnx.part')).writeAsBytesSync(encBytes.sublist(0, 20000));
    await s.install(s.catalog.byId('stt-a')!);
    expect(server.rangeHeaders, contains('bytes=20000-'));
    expect(File(p.join(dir.path, 'encoder.onnx')).readAsBytesSync(), encBytes);
  });

  test('wifi-only policy blocks download without network calls', () async {
    final s = store(catalog(), network: false);
    await expectLater(s.install(s.catalog.byId('vad')!), throwsA(isA<ModelDownloadException>()));
    expect(log.records, isEmpty);
    expect(s.isInstalled('vad'), isFalse);
  });

  test('delete removes files and clears default', () async {
    final s = store(catalog());
    final spec = s.catalog.byId('stt-a')!;
    await s.install(spec);
    s.setDefault(spec);
    await s.delete(spec);
    expect(s.isInstalled('stt-a'), isFalse);
    expect(Directory(s.dirOf('stt-a')).existsSync(), isFalse);
    expect(settings.get(SettingKeys.defaultSttModel), '');
  });
}
