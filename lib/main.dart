// maeknote — Flutter entrypoint
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/db.dart';
import 'core/i18n.dart';
import 'core/providers.dart';
import 'core/window_sizer.dart';
import 'core/window_state.dart';
import 'features/cloud/cloud_llm.dart';
import 'features/models/model_catalog.dart';
import 'features/player/media_kit_backend.dart';
import 'features/settings/settings_repo.dart';
import 'features/summary/summarizer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final desktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  if (desktop) await windowManager.ensureInitialized();
  final dir = (await getApplicationSupportDirectory()).path;
  final db = AppDatabase.open(p.join(dir, 'maeknote.db'));
  final catalog = ModelCatalog.parse(
      await rootBundle.loadString('assets/models/manifest.json'));
  final device = await detectDevice();
  // 데스크톱: 마지막으로 닫은 위치·크기·노트 패널 상태로 시작
  var notePanelOpen = false;
  if (desktop) {
    final settings = SettingsRepo(db);
    final restored = await restoreWindowFrame(settings);
    notePanelOpen = restored &&
        settings.getBool(SettingKeys.notePanelOpen) &&
        (await windowManager.getSize()).width >= expandedWindowWidth - 1;
    // 실제로 열린 위치를 바로 저장 (화면 밖 값 등으로 복원하지 못한 경우 갱신)
    final keeper = WindowFrameKeeper(settings)..start();
    await keeper.save();
  }
  final templates = SummaryTemplates.parse(
      await rootBundle.loadString('assets/summary/templates.json'));
  // 번들 언어셋 + 앱 데이터 폴더 i18n/*.json (재빌드 없이 언어 추가·수정)
  final languages = await LanguagePacks.load(rootBundle, extraDir: p.join(dir, 'i18n'));
  final cloudKeys = CloudKeys(OsSecretStore());
  await cloudKeys.load();
  runApp(ProviderScope(
    overrides: [
      appDirProvider.overrideWithValue(dir),
      dbProvider.overrideWithValue(db),
      catalogProvider.overrideWithValue(catalog),
      deviceProvider.overrideWithValue(device),
      languagePacksProvider.overrideWithValue(languages),
      summaryTemplatesProvider.overrideWithValue(templates),
      if (desktop) windowSizerProvider.overrideWithValue(DesktopWindowSizer()),
      notePanelProvider.overrideWith((ref) => notePanelOpen),
      cloudKeysProvider.overrideWith((ref) => cloudKeys),
      audioBackendProvider.overrideWithValue(MediaKitBackend()),
    ],
    child: const App(),
  ));
}
