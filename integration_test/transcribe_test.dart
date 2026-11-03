import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('decode audio/video → download whisper-tiny → Korean transcript',
      (tester) async {
    await tester.runAsync(() async {
      final support = (await getApplicationSupportDirectory()).path;
      final tmp = p.join((await getTemporaryDirectory()).path, 'it_stt');
      final files = await writeFixtures(tmp);

      // 1) mpv PCM 디코딩: mp3·mp4 모두 16kHz 모노 ≈ 19.7초
      final decoder = MpvPcmDecoder();
      for (final path in [files.mp3, files.mp4]) {
        final pcm = await decoder.decode(path, tmp);
        final sec = pcm.length / sttSampleRate;
        // ignore: avoid_print
        print('DECODE ${p.basename(path)} ${sec.toStringAsFixed(2)}s');
        expect(sec, closeTo(19.7, 0.5), reason: path);
      }
      // 전사 속도 80%: 음높이를 유지한 채 늘린 음성 ≈ 19.7 / 0.8 = 24.6초
      final slow = await decoder.decode(files.mp3, tmp, tempo: 0.8);
      // ignore: avoid_print
      print('DECODE tempo=0.8 ${(slow.length / sttSampleRate).toStringAsFixed(2)}s');
      expect(slow.length / sttSampleRate, closeTo(19.7 / 0.8, 0.6));

      // 2) 실제 모델 다운로드 (캐시: 앱 지원 폴더, 재실행 시 재사용)
      final db = AppDatabase.open(p.join(support, 'it_models.db'));
      final settings = SettingsRepo(db)..setBool(SettingKeys.wifiOnlyDownload, false);
      final log = NetworkLog();
      final catalog = ModelCatalog.parse(
          await rootBundle.loadString('assets/models/manifest.json'));
      final store = ModelStore(
        db: db,
        catalog: catalog,
        settings: settings,
        modelsDir: p.join(support, 'it_models'),
        client: () => GuardedClient(NetPurpose.modelDownload, log),
        networkAllowed: () async => true,
      );
      final sw = Stopwatch()..start();
      await store.install(catalog.byId('whisper-tiny')!);
      // ignore: avoid_print
      print('DOWNLOAD whisper-tiny+vad ${sw.elapsed.inSeconds}s requests=${log.records.length}');
      expect(store.isInstalled('vad-silero'), isTrue);

      // 3) 전사 (영상 파일로)
      final library = LibraryRepo(db, mediaDir: p.join(tmp, 'media'));
      await library.clear();
      final item = (await library.import([files.mp4])).single;
      final repo = TranscriptRepo(db);
      final service = TranscribeService(
        repo: repo,
        models: store,
        settings: settings..set(SettingKeys.sttLanguage, 'ko'),
        library: library,
        decoder: decoder,
        engine: SherpaSttEngine(),
        tmpDir: tmp,
      );
      final logBefore = log.records.length;
      // 같은 파일을 100%·80%(기본) 속도로 전사해 비교 — 시간은 둘 다 원래 재생 시간 기준
      for (final speed in ['100', '80']) {
        settings.set(SettingKeys.sttSpeed, speed);
        sw.reset();
        await service.transcribe(item);
        final segs = repo.segments(item.id);
        // ignore: avoid_print
        print('TRANSCRIBE speed=$speed% ${sw.elapsedMilliseconds}ms segments=${segs.length}');
        for (final s in segs) {
          // ignore: avoid_print
          print('SEG speed=$speed% [${s.startMs}-${s.endMs}] ${s.text}');
        }
        expect(repo.info(item.id).status, TranscriptStatus.done);
        expect(segs.length, greaterThanOrEqualTo(2));
        expect(segs.first.startMs, lessThan(2000));
        expect(segs.last.endMs, greaterThan(15000));
        expect(segs.last.endMs, lessThan(21000)); // 늘린 시간(24.6초)이 아니라 원래 시간
        expect(library.byId(item.id)!.durationMs, closeTo(19700, 600));
        final all = segs.map((s) => s.text).join(' ');
        expect(['회의', '예산', '채용', '안건'].any(all.contains), isTrue, reason: all);
      }
      // 전사 중 외부 전송 0건 (PRD AC6)
      expect(log.records.length, logBefore);
      db.close();
    });
  });
}
