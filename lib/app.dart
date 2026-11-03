// maeknote — 앱 루트 (라우팅 + 화면 조립)
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/i18n.dart';
import 'core/providers.dart';
import 'core/theme.dart';
import 'core/window_sizer.dart';
import 'features/library/library_view.dart';
import 'features/models/models_view.dart';
import 'features/player/equalizer_view.dart';
import 'features/player/output_view.dart';
import 'features/player/player_widgets.dart';
import 'features/player/playback_memory.dart';
import 'features/settings/settings_repo.dart';
import 'features/settings/settings_view.dart';
import 'features/shell/main_screen.dart';
import 'features/summary/summary_view.dart';
import 'features/transcribe/note_view.dart';
import 'features/transcribe/transcribe_actions.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  // 설정은 화면 이동이 아니라 팝업(showSettingsDialog)
  final _router = GoRouter(routes: [
    GoRoute(path: '/', builder: (context, _) => const HomePage()),
  ]);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    final font =
        ref.watch(settingsProvider.select((s) => s.get(SettingKeys.font)));
    final scale = fontScaleOf(
        ref.watch(settingsProvider.select((s) => s.get(SettingKeys.fontSize))));
    return I18nScope(
      i18n: i18n,
      child: MaterialApp.router(
        title: 'MaekNote',
        debugShowCheckedModeBanner: false,
        theme: buildVoxTheme(font: font, compact: ref.watch(isDesktopProvider)),
        routerConfig: _router,
        // 설정 > 일반 > 글자 크기: OS 글자 크기 설정에 곱한다
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
                textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale)),
            child: child!,
          );
        },
        // 시스템 위젯(뒤로 가기 등) 문구: Material 이 지원하는 언어만, 나머지는 English
        locale: i18n.locale,
        supportedLocales: [
          for (final p in i18n.available)
            if (GlobalMaterialLocalizations.delegate
                .isSupported(Locale(p.code)))
              Locale(p.code),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
      ),
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final PlaybackMemory _memory;

  @override
  void initState() {
    super.initState();
    // 저장된 EQ · 출력 장치 · 마지막 재생 위치 복원
    applySavedEq(ref);
    final device = ref.read(settingsProvider).get(SettingKeys.outputDevice);
    if (device != 'auto') ref.read(playerProvider).setDevice(device);
    _memory = PlaybackMemory(ref.read(playerProvider),
        ref.read(settingsProvider), ref.read(libraryProvider))
      ..start();
  }

  @override
  void dispose() {
    _memory.stop();
    super.dispose();
  }

  void _more(BuildContext context) {
    final home = this.context;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(context.tr('app.import')),
            onTap: () {
              Navigator.pop(context);
              importMedia(ref);
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(context.tr('app.settings')),
            onTap: () {
              Navigator.pop(context);
              showSettingsDialog(home);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = ref.watch(isDesktopProvider);
    // 노트 패널을 열고 닫을 때 창을 오른쪽으로 펼치거나 되돌린다
    ref.listen<bool>(notePanelProvider, (_, open) {
      final sizer = ref.read(windowSizerProvider);
      if (sizer != null) applyNotePanel(sizer, open);
      // 다음 실행 때 같은 상태로 열기 위해 저장
      ref.read(settingsProvider).setBool(SettingKeys.notePanelOpen, open);
    });
    void closePanel() => ref.read(notePanelProvider.notifier).state = false;
    return MainScreen(
      notePanelOpen: ref.watch(notePanelProvider),
      noteRequest: ref.watch(showNoteRequestProvider),
      onToggleNotePanel: desktop
          ? () => ref.read(notePanelProvider.notifier).update((v) => !v)
          : null,
      header: const PlayerHeader(),
      controls: (panel, toggle) => PlayerControls(panel: panel, toggle: toggle),
      transport: TransportBar(onMore: _more),
      library: LibraryView(
        extraMenu: (context, item) => transcribeMenu(context, ref, item),
        badge: (context, item) => TranscriptBadge(item: item),
      ),
      note: NoteView(
        summary: (item) =>
            SummaryView(key: ValueKey('s${item.id}'), item: item),
        onClose: desktop ? closePanel : null,
      ),
      models: const ModelsView(),
      equalizer: const EqualizerView(),
      output: const OutputView(),
      onOpenSettings: () => showSettingsDialog(context),
    );
  }
}
