// 실제 앱(mpv·sqlite)에서 끌어다 놓기: 재생 중 + 백그라운드 전사 중에 반복해서 놓아도 죽지 않는지.
// OS 끌어다 놓기는 macOS 플러그인이 보내는 것과 같은 'performOperation_macos' 메시지로 흉내 낸다.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:maeknote/app.dart';
import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/i18n.dart';
import 'package:maeknote/core/providers.dart';
import 'package:maeknote/core/window_sizer.dart';
import 'package:maeknote/features/cloud/cloud_llm.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/player/media_kit_backend.dart';
import 'package:maeknote/features/settings/settings_repo.dart';
import 'package:maeknote/features/summary/summarizer.dart';
import 'package:maeknote/features/transcribe/transcript_repo.dart';

import 'support.dart';

class _NoSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String? value) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('drops while playing and transcribing in the background', (tester) async {
    final support = (await getApplicationSupportDirectory()).path;
    final dir = p.join(support, 'it_app'); // app_flow 이 받아 둔 whisper-tiny 재사용
    await Directory(dir).create(recursive: true);
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(playerWindowWidth, 574));
    final db = AppDatabase.open(p.join(dir, 'maeknote.db'));
    final c = ProviderContainer(overrides: [
      appDirProvider.overrideWithValue(dir),
      dbProvider.overrideWithValue(db),
      catalogProvider.overrideWithValue(
          ModelCatalog.parse(await rootBundle.loadString('assets/models/manifest.json'))),
      deviceProvider.overrideWithValue(await detectDevice()),
      audioBackendProvider.overrideWithValue(MediaKitBackend()),
      secretStoreProvider.overrideWithValue(_NoSecrets()),
      languagePacksProvider.overrideWithValue(await LanguagePacks.load(rootBundle)),
      summaryTemplatesProvider.overrideWithValue(SummaryTemplates.parse(
          await rootBundle.loadString('assets/summary/templates.json'))),
      windowSizerProvider.overrideWithValue(DesktopWindowSizer()),
    ]);
    c.read(settingsProvider)
      ..setBool(SettingKeys.savePosition, false)
      ..set(SettingKeys.sttLanguage, 'ko');
    final library = c.read(libraryProvider);
    await library.clear();
    expect(c.read(modelStoreProvider).defaultModel(ModelKind.stt), isNotNull,
        reason: 'app_flow_test 를 먼저 실행해 whisper-tiny 를 받아 두어야 함');

    // 끌어다 놓을 파일들: 서로 다른 이름 10개 + 폴더 1개
    final tmp = p.join((await getTemporaryDirectory()).path, 'it_drop');
    await Directory(tmp).create(recursive: true);
    final fx = await writeFixtures(tmp);
    final files = <String>[
      for (var i = 0; i < 10; i++)
        (await File(i.isEven ? fx.mp3 : fx.mp4)
                .copy(p.join(tmp, 'drop_$i${i.isEven ? '.mp3' : '.mp4'}')))
            .path,
    ];
    // 전사가 놓기보다 오래 걸리도록 약 10분짜리 MP3 (MP3 는 프레임을 이어 붙여도 재생됨)
    final mp3 = await File(fx.mp3).readAsBytes();
    final long = File(p.join(tmp, 'long_meeting.mp3'));
    await long.writeAsBytes([for (var i = 0; i < 30; i++) ...mp3]);
    files[0] = long.path;
    final folder = Directory(p.join(tmp, 'folder'))..createSync(recursive: true);
    await File(fx.mp3).copy(p.join(folder.path, 'in_folder.mp3'));

    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const App()));
    await tester.pumpAndSettle();

    Future<void> send(String method, Object args) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage('desktop_drop',
            const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)), (_) {});
    Future<void> drop(List<String> paths, {bool dirs = false}) async {
      const at = [160.0, 400.0];
      await send('entered', at);
      await send('updated', at);
      await send('performOperation_macos', [
        for (final path in paths) {'path': path, 'apple-bookmark': null, 'isDirectory': dirs},
      ]);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
    }

    // 1) 첫 파일을 놓고 재생
    await drop([files[0]]);
    final first = library.playlist().single;
    await tester.runAsync(() => c.read(playerProvider).playItem(first, [first]));
    await c.read(playerProvider).setVolume(0);

    // 2) 백그라운드 전사 시작 (두 번째 mpv 인스턴스로 디코딩)
    final job = c.read(transcribeServiceProvider).transcribe(first);
    // ignore: avoid_print
    job.catchError((Object e) => print('JOB_ERROR ${e is AppError ? e.args : e}'));

    // 3) 재생·전사 중에 하나씩, 여러 개, 폴더, 이미 있는 파일을 연달아 놓는다
    for (var i = 1; i < 6; i++) {
      await drop([files[i]]);
    }
    await drop(files.sublist(6));
    await drop([folder.path], dirs: true);
    await drop([files[0], files[1]]); // 이미 있음 → 중복 추가 없음
    expect(tester.takeException(), isNull);

    expect(c.read(transcriptRepoProvider).info(first.id).running, isTrue,
        reason: '놓는 동안 전사가 실제로 백그라운드에서 돌고 있어야 함');
    await tester.runAsync(() => job.timeout(const Duration(minutes: 5)));
    expect(c.read(transcriptRepoProvider).info(first.id).status, TranscriptStatus.done);
    expect(library.playlist(), hasLength(11));
    expect(c.read(playerProvider).current?.id, first.id);
    // ignore: avoid_print
    print('DROP_OK items=${library.playlist().length} '
        'segments=${c.read(transcriptRepoProvider).segments(first.id).length}');
    // 진단용: --dart-define=IT_HOLD=<초> 동안 놓기·재생·전사를 반복하며 앱을 살려 둔다
    const hold = int.fromEnvironment('IT_HOLD');
    final until = DateTime.now().add(const Duration(seconds: hold));
    var round = 0;
    while (DateTime.now().isBefore(until)) {
      round++;
      final extra = (await File(fx.mp3).copy(p.join(tmp, 'hold_$round.mp3'))).path;
      await drop([extra]);
      final added = library.playlist().last;
      await tester.runAsync(() => c.read(transcribeServiceProvider).transcribe(added));
      await tester.runAsync(() => c.read(playerProvider).playItem(added, [added]));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    }
    if (hold > 0) print('HOLD_OK rounds=$round'); // ignore: avoid_print
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (c.read(playerProvider).playing) await c.read(playerProvider).togglePlay();
  });
}
