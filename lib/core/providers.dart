// maeknote — 전역 Provider (main 에서 override)
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/cloud/cloud_llm.dart';
import '../features/library/library_repo.dart';
import '../features/models/model_catalog.dart';
import '../features/models/model_store.dart';
import '../features/player/player_service.dart';
import '../features/settings/settings_repo.dart';
import '../features/summary/local_llm.dart';
import '../features/summary/summarizer.dart';
import '../features/summary/summary_service.dart';
import '../features/transcribe/audio_decoder.dart';
import '../features/transcribe/stt_engine.dart';
import '../features/transcribe/transcribe_service.dart';
import '../features/transcribe/transcript_repo.dart';
import 'db.dart';
import 'i18n.dart';
import 'net.dart';
import 'window_sizer.dart';

/// 앱 데이터 루트 (DB · 미디어 사본 · 모델 · 캐시)
final appDirProvider = Provider<String>(
  (ref) => throw UnimplementedError('main() 에서 override'),
);

final dbProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('main() 에서 override'),
);

final audioBackendProvider = Provider<AudioBackend>(
  (ref) => throw UnimplementedError('main() 에서 override'),
);

final catalogProvider = Provider<ModelCatalog>(
  (ref) => throw UnimplementedError('main() 에서 override'),
);

final deviceProvider = Provider<DeviceSpec>(
  (ref) => throw UnimplementedError('main() 에서 override'),
);

/// 번들 + 사용자 언어셋 (main() 에서 load 후 override)
final languagePacksProvider = Provider<LanguagePacks>(
  (ref) => throw UnimplementedError('main() 에서 override'),
);

/// 설정의 앱 언어가 바뀔 때만 다시 만든다 (기본 English)
final i18nProvider = Provider<I18n>((ref) => I18n(
      ref.watch(languagePacksProvider),
      ref.watch(settingsProvider.select((s) => s.get(SettingKeys.language))),
    ));

final networkLogProvider = ChangeNotifierProvider<NetworkLog>((ref) => NetworkLog());

final settingsProvider = ChangeNotifierProvider<SettingsRepo>(
  (ref) => SettingsRepo(ref.watch(dbProvider)),
);

final libraryProvider = ChangeNotifierProvider<LibraryRepo>(
  (ref) => LibraryRepo(ref.watch(dbProvider),
      mediaDir: '${ref.watch(appDirProvider)}/media'),
);

final playerProvider = ChangeNotifierProvider<PlayerService>(
  (ref) => PlayerService(
      ref.watch(audioBackendProvider), ref.read(libraryProvider)),
);

/// 데스크톱(창 크기 조절 가능)이면 노트를 오른쪽 패널로 펼친다
final isDesktopProvider = Provider<bool>(
    (ref) => Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// 데스크톱 창 크기 조절 (모바일·시험에서는 null)
final windowSizerProvider = Provider<WindowSizer?>((ref) => null);

/// 노트(전사·요약) 패널 열림 — 전사를 시작하면 자동으로 열린다
final notePanelProvider = StateProvider<bool>((ref) => false);

/// 노트(전사 탭)를 앞으로 띄워 달라는 요청 횟수 — 휴대폰은 노트 탭으로 전환 (전사 완료 시)
final showNoteRequestProvider = StateProvider<int>((ref) => 0);

/// 재생목록 검색어 (null = 검색창 닫힘)
final librarySearchProvider = StateProvider<String?>((ref) => null);

final modelStoreProvider = ChangeNotifierProvider<ModelStore>((ref) {
  final settings = ref.read(settingsProvider);
  return ModelStore(
    db: ref.watch(dbProvider),
    catalog: ref.watch(catalogProvider),
    settings: settings,
    modelsDir: '${ref.watch(appDirProvider)}/models',
    client: () =>
        GuardedClient(NetPurpose.modelDownload, ref.read(networkLogProvider)),
    networkAllowed: () async {
      if (!settings.getBool(SettingKeys.wifiOnlyDownload)) return true;
      final c = await Connectivity().checkConnectivity();
      // 모바일 데이터만 연결된 경우 차단 (데스크톱 유선·Wi-Fi 는 허용)
      return !(c.contains(ConnectivityResult.mobile) &&
          !c.contains(ConnectivityResult.wifi) &&
          !c.contains(ConnectivityResult.ethernet));
    },
  );
});

final transcriptRepoProvider = ChangeNotifierProvider<TranscriptRepo>(
  (ref) => TranscriptRepo(ref.watch(dbProvider)),
);

final audioDecoderProvider = Provider<AudioDecoder>((ref) => MpvPcmDecoder());
final sttEngineProvider = Provider<SttEngine>((ref) => SherpaSttEngine());

final transcribeServiceProvider = Provider<TranscribeService>(
  (ref) => TranscribeService(
    repo: ref.watch(transcriptRepoProvider),
    models: ref.watch(modelStoreProvider),
    settings: ref.read(settingsProvider),
    library: ref.read(libraryProvider),
    decoder: ref.watch(audioDecoderProvider),
    engine: ref.watch(sttEngineProvider),
    tmpDir: '${ref.watch(appDirProvider)}/tmp',
  ),
);

/// 온디바이스 LLM 은 한 번에 하나만 메모리에 둔다
final localLlmProvider = Provider<LlmEngine Function(ModelSpec, String)>((ref) {
  LocalLlmEngine? loaded;
  ref.onDispose(() => loaded?.dispose());
  return (spec, path) {
    if (loaded?.id != spec.id) {
      loaded?.dispose();
      loaded = LocalLlmEngine(spec.id, path);
    }
    return loaded!;
  };
});

final secretStoreProvider = Provider<SecretStore>((ref) => OsSecretStore());

/// main() 에서 load() 후 override
final cloudKeysProvider = ChangeNotifierProvider<CloudKeys>(
  (ref) => CloudKeys(ref.watch(secretStoreProvider)),
);

/// 클라우드 옵션이 켜지고 API 키가 있을 때만 엔진 반환 (기본: 온디바이스)
final cloudLlmProvider = Provider<LlmEngine? Function()>((ref) {
  final settings = ref.read(settingsProvider);
  final keys = ref.read(cloudKeysProvider);
  return () {
    if (!settings.getBool(SettingKeys.cloudEnabled)) return null;
    final provider = CloudProvider.values.asNameMap()[settings.get(SettingKeys.cloudProvider)] ??
        CloudProvider.openai;
    final key = keys.of(provider);
    final model = settings.get(SettingKeys.cloudModel);
    // OpenAI 호환은 모델명을 직접 지정해야 사용 (게이트웨이마다 다름)
    if (key == null || (provider == CloudProvider.openai && model.isEmpty)) return null;
    final client = GuardedClient(NetPurpose.cloud, ref.read(networkLogProvider),
        allowed: () => settings.getBool(SettingKeys.cloudEnabled));
    return switch (provider) {
      CloudProvider.anthropic => AnthropicEngine(
          apiKey: key, model: model.isEmpty ? anthropicDefaultModel : model, client: client),
      CloudProvider.openai => OpenAiCompatibleEngine(
          baseUrl: settings.get(SettingKeys.cloudBaseUrl),
          apiKey: key,
          model: model,
          client: client),
    };
  };
});

/// 요약 템플릿 (assets/summary/templates.json, main() 에서 로드)
final summaryTemplatesProvider = Provider<SummaryTemplates>(
  (ref) => throw UnimplementedError('main() 에서 override'),
);

final summaryServiceProvider = ChangeNotifierProvider<SummaryService>(
  (ref) => SummaryService(
    db: ref.watch(dbProvider),
    transcripts: ref.watch(transcriptRepoProvider),
    models: ref.watch(modelStoreProvider),
    settings: ref.read(settingsProvider),
    templates: ref.watch(summaryTemplatesProvider),
    localEngine: ref.watch(localLlmProvider),
    cloudEngine: ref.watch(cloudLlmProvider),
  ),
);
