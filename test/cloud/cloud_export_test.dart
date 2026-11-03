import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/i18n.dart';
import 'package:maeknote/core/net.dart';
import 'package:maeknote/core/providers.dart';
import 'package:maeknote/features/cloud/cloud_llm.dart';
import 'package:maeknote/features/export/exporter.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/settings/settings_repo.dart';
import 'package:maeknote/features/summary/summarizer.dart';
import 'package:maeknote/features/summary/summary_service.dart';
import 'package:maeknote/features/transcribe/stt_engine.dart';
import 'package:maeknote/features/transcribe/transcript_repo.dart';

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

class _BrokenSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => throw Exception('Libsecret error');
  @override
  Future<void> write(String key, String? value) async => throw Exception('Libsecret error');
}

class _Local implements LlmEngine {
  int calls = 0;
  @override
  String get id => 'local';
  @override
  Future<String> complete(String system, String user, {int maxTokens = 1024}) async {
    calls++;
    return '- 로컬 요약 [S0]';
  }
}

void main() {
  group('AnthropicEngine', () {
    test('sends Messages API request with fallbacks and joins text blocks', () async {
      late http.Request sent;
      final client = MockClient((req) async {
        sent = req;
        return http.Response(
            jsonEncode({
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'thinking', 'thinking': ''},
                {'type': 'text', 'text': '## 요약\n'},
                {'type': 'text', 'text': '- 항목 [S0]'},
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
      final e = AnthropicEngine(apiKey: 'k', model: anthropicDefaultModel, client: client);
      expect(await e.complete('sys', 'user', maxTokens: 512), '## 요약\n- 항목 [S0]');
      expect(sent.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(sent.headers['x-api-key'], 'k');
      expect(sent.headers['anthropic-version'], '2026-10-21');
      expect(sent.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-opus-5-5');
      expect(body['fallbacks'], 'default');
      expect(body['system'], 'sys');
      expect(body['max_tokens'], 512);
      expect(body.containsKey('temperature'), isFalse);
    });

    test('refusal and HTTP errors raise CloudException', () async {
      final refusal = MockClient((_) async =>
          http.Response(jsonEncode({'stop_reason': 'refusal', 'content': []}), 200));
      await expectLater(
          AnthropicEngine(apiKey: 'k', model: 'claude-haiku-5-5', client: refusal)
              .complete('s', 'u'),
          throwsA(isA<CloudException>()));
      final err = MockClient((_) async => http.Response('{}', 401));
      await expectLater(
          AnthropicEngine(apiKey: 'k', model: 'x', client: err).complete('s', 'u'),
          throwsA(isA<CloudException>()));
    });

    test('models without server-side fallback omit the beta', () async {
      late http.Request sent;
      final client = MockClient((req) async {
        sent = req;
        return http.Response(jsonEncode({'stop_reason': 'end_turn', 'content': []}), 200);
      });
      await AnthropicEngine(apiKey: 'k', model: 'claude-haiku-5-5', client: client)
          .complete('s', 'u');
      expect(sent.headers.containsKey('anthropic-beta'), isFalse);
      expect((jsonDecode(sent.body) as Map).containsKey('fallbacks'), isFalse);
    });
  });

  test('OpenAI-compatible engine posts chat completions', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': '- ok'}}
            ]
          }),
          200);
    });
    final e = OpenAiCompatibleEngine(
        baseUrl: 'https://gw.example/v1/', apiKey: 'k', model: 'm', client: client);
    expect(await e.complete('s', 'u'), '- ok');
    expect(sent.url.toString(), 'https://gw.example/v1/chat/completions');
    expect(sent.headers['authorization'], 'Bearer k');
  });

  test('GuardedClient blocks when policy is off and logs when on', () async {
    final log = NetworkLog();
    var on = false;
    final c = GuardedClient(NetPurpose.cloud, log,
        inner: MockClient((_) async => http.Response('', 200)), allowed: () => on);
    await expectLater(c.get(Uri.parse('https://x')), throwsA(isA<NetBlockedException>()));
    expect(log.records, isEmpty);
    on = true;
    await c.get(Uri.parse('https://x'));
    expect(log.of(NetPurpose.cloud), hasLength(1));
  });

  group('engine selection (AC6)', () {
    late Directory tmp;
    late AppDatabase db;
    late ProviderContainer c;
    late _Local local;
    late _MemSecrets secrets;
    late int mediaId;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('maeknote_cloud');
      db = AppDatabase.memory();
      local = _Local();
      secrets = _MemSecrets();
      c = ProviderContainer(overrides: [
        appDirProvider.overrideWithValue(tmp.path),
        dbProvider.overrideWithValue(db),
        audioBackendProvider.overrideWithValue(FakeBackend()),
        secretStoreProvider.overrideWithValue(secrets),
        catalogProvider.overrideWithValue(ModelCatalog([
          ModelSpec(id: 'llm', kind: ModelKind.llm, name: 'llm', tier: 0, ramMb: 1,
              license: 'MIT', minPerHour: 1,
              files: [ModelFile('model.gguf', 'https://x', 'a' * 64, 1)]),
        ])),
        deviceProvider.overrideWithValue(const DeviceSpec(ramMb: 8192, platform: 'x')),
        localLlmProvider.overrideWithValue((spec, path) => local),
        summaryTemplatesProvider.overrideWithValue(loadTemplates()),
      ]);
      db.db.execute("INSERT INTO installed_models VALUES ('llm', 'llm', '/x', 0)");
      final f = File(p.join(tmp.path, 'a.mp3'))..writeAsStringSync('x');
      mediaId = (await c.read(libraryProvider).import([f.path])).single.id;
      final repo = c.read(transcriptRepoProvider)..start(mediaId, 'stt', 'ko');
      repo.addSegment(mediaId, const Segment(0, 1000, '회의 시작'));
      repo.update(mediaId, TranscriptStatus.done, 1);
    });

    tearDown(() {
      c.dispose();
      db.close();
      tmp.deleteSync(recursive: true);
    });

    test('cloud OFF (default) → on-device engine, zero network records', () async {
      await c.read(cloudKeysProvider).set(CloudProvider.anthropic, 'secret');
      c.read(settingsProvider).set(SettingKeys.cloudProvider, 'anthropic');
      final s = await c.read(summaryServiceProvider).summarize(mediaId, SummaryType.brief);
      expect(s.modelId, 'local');
      expect(local.calls, 2); // 간단한 요약 = 2개 섹션
      expect(c.read(networkLogProvider).records, isEmpty);
    });

    test('cloud ON without key / OpenAI without model → still on-device', () async {
      final settings = c.read(settingsProvider)..setBool(SettingKeys.cloudEnabled, true);
      expect(c.read(cloudLlmProvider)(), isNull);
      await c.read(cloudKeysProvider).set(CloudProvider.openai, 'k');
      settings.set(SettingKeys.cloudProvider, 'openai');
      expect(c.read(cloudLlmProvider)(), isNull);
      settings.set(SettingKeys.cloudModel, 'my-model');
      expect(c.read(cloudLlmProvider)()!.id, 'cloud:openai:my-model');
    });

    test('cloud ON + anthropic key → Anthropic engine with default model', () async {
      c.read(settingsProvider)
        ..setBool(SettingKeys.cloudEnabled, true)
        ..set(SettingKeys.cloudProvider, 'anthropic');
      await c.read(cloudKeysProvider).set(CloudProvider.anthropic, 'k');
      expect(c.read(cloudLlmProvider)()!.id, 'cloud:anthropic:claude-opus-5-5');
    });

    test('API keys persist in secret store, not in the settings DB', () async {
      await c.read(cloudKeysProvider).set(CloudProvider.anthropic, 'sk-test');
      expect(secrets.m['cloud.apiKey.anthropic'], 'sk-test');
      final rows = db.db.select("SELECT value FROM settings WHERE value LIKE '%sk-test%'");
      expect(rows, isEmpty);
      final reloaded = CloudKeys(secrets);
      await reloaded.load();
      expect(reloaded.of(CloudProvider.anthropic), 'sk-test');
      await reloaded.set(CloudProvider.anthropic, '');
      expect(secrets.m, isEmpty);
    });

    test('app still starts when the OS secret store is unavailable', () async {
      final keys = CloudKeys(_BrokenSecrets());
      await keys.load(); // throws nothing
      expect(keys.of(CloudProvider.anthropic), isNull);
    });
  });

  group('export', () {
    final ko = I18n(loadPacks(), 'ko');
    const segs = [
      Segment(1500, 4250, '첫 문장'),
      Segment(3723000, 3725010, '한 시간 뒤'),
    ];

    test('SRT uses comma millis and sequence numbers', () {
      final out = exportTranscript('t', segs, ExportFormat.srt, tr: ko.t);
      expect(out, startsWith('1\n00:00:01,500 --> 00:00:04,250\n첫 문장\n\n2\n01:02:03,000 --> 01:02:05,010'));
    });

    test('VTT header and dot millis', () {
      final out = exportTranscript('t', segs, ExportFormat.vtt, tr: ko.t);
      expect(out, startsWith('WEBVTT\n\n00:00:01.500 --> 00:00:04.250\n첫 문장'));
    });

    test('TXT and Markdown include timestamps and summaries', () {
      expect(exportTranscript('회의', segs, ExportFormat.txt, tr: ko.t),
          '회의\n\n[0:01] 첫 문장\n[1:02:03] 한 시간 뒤\n');
      final md = exportTranscript('회의', segs, ExportFormat.md, tr: ko.t, summaries: [
        StoredSummary(SummaryType.meeting, 'm',
            const [SummarySection('결정사항', [SummaryItem('예산 증액', 1500, 4250)])],
            DateTime(2026)),
      ]);
      expect(md, contains('## 회의록'));
      expect(md, contains('- 예산 증액 `[0:01]`'));
      expect(md, contains('- `[1:02:03]` 한 시간 뒤'));
    });
  });
}
