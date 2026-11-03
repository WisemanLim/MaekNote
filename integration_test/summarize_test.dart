import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/net.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/models/model_store.dart';
import 'package:maeknote/features/settings/settings_repo.dart';
import 'package:maeknote/features/summary/local_llm.dart';
import 'package:maeknote/features/summary/summarizer.dart';
import 'package:maeknote/features/transcribe/stt_engine.dart';

/// 4th 시험의 실제 Whisper tiny 전사 결과
const _segments = [
  Segment(134, 5328, '이제는 세일을 시작하겠습니다. 첫 번째 안 꺼는 다음 분기 마케팅 예산입니다.'),
  Segment(6822, 12880, '예사는 지난 분기보다 10% 늘리기로 결정했습니다. 담당자는 김팀장입니다.'),
  Segment(14406, 19680, '두 번째 안건은 신규 세용입니다. 다음 주 금요일까지 공부를 올리겠습니다.'),
];

const _segmentsEn = [
  Segment(0, 5200, "Let's start the meeting. The first item is next quarter's marketing budget."),
  Segment(6000, 12500, 'We decided to raise the budget by ten percent. Kim will own it.'),
  Segment(13000, 19000, 'The second item is hiring. We will post the job opening by next Friday.'),
];

/// 원문 출력을 로그로 남기는 래퍼
class _Logged implements LlmEngine {
  _Logged(this.inner);
  final LlmEngine inner;
  @override
  String get id => inner.id;
  @override
  Future<String> complete(String system, String user, {int maxTokens = 1024}) async {
    final out = await inner.complete(system, user, maxTokens: maxTokens);
    // ignore: avoid_print
    print('RAW<<<\n$out\n>>>RAW');
    return out;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('download Qwen2.5 0.5B → on-device meeting minutes with time links',
      (tester) async {
    await tester.runAsync(() async {
      final support = (await getApplicationSupportDirectory()).path;
      final db = AppDatabase.open(p.join(support, 'it_models.db'));
      final log = NetworkLog();
      final catalog = ModelCatalog.parse(
          await rootBundle.loadString('assets/models/manifest.json'));
      final store = ModelStore(
        db: db,
        catalog: catalog,
        settings: SettingsRepo(db),
        modelsDir: p.join(support, 'it_models'),
        client: () => GuardedClient(NetPurpose.modelDownload, log),
        networkAllowed: () async => true,
      );
      final spec = catalog.byId('qwen2.5-0.5b')!;
      final sw = Stopwatch()..start();
      await store.install(spec);
      // ignore: avoid_print
      print('DOWNLOAD ${spec.id} ${sw.elapsed.inSeconds}s');

      final engine = LocalLlmEngine(spec.id, store.filesOf(spec)['model.gguf']!);
      final templates = SummaryTemplates.parse(
          await rootBundle.loadString('assets/summary/templates.json'));
      final before = log.records.length;
      // 한국어 녹음 → 한국어 요약, English 전사본 → English 요약
      // (0.5B 는 한국어 녹음을 English 로 요약하지 못함 — 모델 한계, T1 이상 권장)
      for (final (type, lang, segs) in [
        (SummaryType.meeting, 'ko', _segments),
        (SummaryType.lecture, 'ko', _segments),
        (SummaryType.meeting, 'en', _segmentsEn),
      ]) {
        sw.reset();
        final sections = await Summarizer(_Logged(engine), templates)
            .summarize(segs, type: type, language: lang);
        // ignore: avoid_print
        print('SUMMARY ${type.name}/$lang ${sw.elapsedMilliseconds}ms');
        for (final s in sections) {
          // ignore: avoid_print
          print('## ${s.title}');
          for (final i in s.items) {
            // ignore: avoid_print
            print('- ${i.text} @${i.startMs}');
          }
        }
        final items = sections.expand((s) => s.items).toList();
        expect(items, isNotEmpty, reason: type.name);
        // 모든 시간 링크는 실제 구간 시작점 (AC3)
        final starts = segs.map((s) => s.startMs).toSet();
        final linked = items.where((i) => i.startMs != null).toList();
        expect(linked, isNotEmpty, reason: type.name);
        expect(linked.every((i) => starts.contains(i.startMs)), isTrue);
      }
      // 온디바이스 요약 중 외부 전송 0건 (AC6)
      expect(log.records.length, before);
      await engine.dispose();
      db.close();
    });
  });
}
