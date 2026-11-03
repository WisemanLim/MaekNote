// maeknote — 설정 화면 (VOX 설정 창의 아이콘 탭 + 섹션 구조, Image #5)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/net.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../cloud/cloud_llm.dart';
import '../models/models_view.dart';
import '../player/equalizer.dart';
import '../player/equalizer_view.dart';
import '../summary/summarizer.dart';
import '../transcribe/transcribe_service.dart';
import 'settings_repo.dart';

/// 설정 팝업 — 화면 이동 없이 현재 창 위에 연다
Future<void> showSettingsDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: const SettingsPage(),
        ),
      ),
    );

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// (아이콘, 언어셋 키)
  static const tabs = [
    (Icons.settings, 'settings.tab.general'),
    (Icons.graphic_eq, 'settings.tab.audio'),
    (Icons.memory, 'settings.tab.models'),
    (Icons.subject, 'settings.tab.transcription'),
    (Icons.summarize, 'settings.tab.summary'),
    (Icons.cloud_outlined, 'settings.tab.cloud'),
    (Icons.lock_outline, 'settings.tab.storage'),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('settings.title')),
          titleTextStyle: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: VoxColors.text),
          toolbarHeight: 40,
          automaticallyImplyLeading: false,
          backgroundColor: VoxColors.panel,
          actions: [
            IconButton(
              tooltip: context.tr('common.close'),
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.maybePop(context),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            labelPadding: const EdgeInsets.symmetric(horizontal: 10),
            tabs: [
              for (final (icon, key) in tabs)
                Tab(
                  height: 44,
                  iconMargin: const EdgeInsets.only(bottom: 2),
                  icon: Icon(icon, size: 16),
                  text: context.tr(key),
                ),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _GeneralTab(),
          _AudioTab(),
          _ModelsTab(),
          _TranscribeTab(),
          _SummaryTab(),
          _CloudTab(),
          _StorageTab(),
        ]),
      ),
    );
  }
}

/// 섹션 제목 + 항목 (VOX 설정의 "General:" 같은 묶음)
class _Section extends StatelessWidget {
  const _Section(this.titleKey, this.children);
  final String titleKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
            child: Text(context.tr(titleKey),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: VoxColors.accent)),
          ),
          ...children,
          const Divider(height: 1),
        ],
      );
}

class _Check extends ConsumerWidget {
  const _Check(this.keyName, this.labelKey, {this.subtitleKey});
  final String keyName;
  final String labelKey;
  final String? subtitleKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: s.getBool(keyName),
      title: Text(context.tr(labelKey)),
      subtitle: subtitleKey == null ? null : Text(context.tr(subtitleKey!)),
      onChanged: (v) => s.setBool(keyName, v ?? false),
    );
  }
}

class _Choice extends ConsumerWidget {
  const _Choice(this.keyName, this.labelKey, this.options,
      {this.translate = true});
  final String keyName;
  final String labelKey;
  final List<(String, String)> options; // (값, 표시 키)

  /// false 면 표시 문자열을 그대로 쓴다 (언어 이름 등)
  final bool translate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final value = s.get(keyName);
    return ListTile(
      dense: true,
      title: Text(context.tr(labelKey)),
      trailing: DropdownButton<String>(
        value: options.any((o) => o.$1 == value) ? value : options.first.$1,
        underline: const SizedBox.shrink(),
        items: [
          for (final (v, t) in options)
            DropdownMenuItem(
                value: v, child: Text(translate ? context.tr(t) : t)),
        ],
        onChanged: (v) {
          if (v != null) s.set(keyName, v);
        },
      ),
    );
  }
}

class _GeneralTab extends ConsumerWidget {
  const _GeneralTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(children: [
        _Section('settings.language', [
          // 언어셋(JSON)마다 자동으로 항목이 생긴다
          _Choice(
              SettingKeys.language,
              'settings.uiLanguage',
              [
                for (final p in ref.watch(i18nProvider).available)
                  (p.code, p.name)
              ],
              translate: false),
        ]),
        _Section('settings.appearance', [
          // OS 에 있는 글꼴을 순서대로 찾는다 (글꼴 파일 미포함)
          const _Choice(SettingKeys.font, 'settings.font', fontChoices),
          _Choice(SettingKeys.fontSize, 'settings.fontSize',
              [for (final v in fontSizeChoices) (v, '$v%')],
              translate: false),
        ]),
        const _Section('settings.playback',
            [_Check(SettingKeys.savePosition, 'settings.savePosition')]),
      ]);
}

class _AudioTab extends ConsumerWidget {
  const _AudioTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final s = ref.watch(settingsProvider);
    return ListView(children: [
      _Section('settings.equalizer', [
        SwitchListTile(
          dense: true,
          title: Text(context.tr('settings.eqEnabled')),
          value: s.getBool(SettingKeys.eqEnabled),
          onChanged: (v) {
            s.setBool(SettingKeys.eqEnabled, v);
            applySavedEq(ref);
          },
        ),
        ListTile(
          dense: true,
          title: Text(context.tr('settings.preset')),
          trailing: DropdownButton<String>(
            value: eqPresets.containsKey(s.get(SettingKeys.eqPreset))
                ? s.get(SettingKeys.eqPreset)
                : null,
            hint: Text(context.tr('eq.custom')),
            underline: const SizedBox.shrink(),
            items: [
              for (final n in eqPresets.keys)
                DropdownMenuItem(value: n, child: Text(n)),
            ],
            onChanged: (n) {
              if (n == null) return;
              s.set(SettingKeys.eqPreset, n);
              s.set(SettingKeys.eqGains, formatGains(eqPresets[n]!));
              applySavedEq(ref);
            },
          ),
        ),
      ]),
      _Section('settings.output', [
        RadioGroup<String>(
          groupValue: player.device,
          onChanged: (v) {
            if (v == null) return;
            player.setDevice(v);
            s.set(SettingKeys.outputDevice, v);
          },
          child: Column(children: [
            for (final (name, label) in [
              ('auto', context.tr('output.system')),
              for (final d in player.devices.where((d) => !d.isAuto))
                (d.name, d.description),
            ])
              RadioListTile<String>(
                dense: true,
                value: name,
                title: Text(label.isEmpty ? name : label),
              ),
          ]),
        ),
      ]),
    ]);
  }
}

class _ModelsTab extends StatelessWidget {
  const _ModelsTab();
  @override
  Widget build(BuildContext context) => const Column(children: [
        _Check(SettingKeys.wifiOnlyDownload, 'settings.wifiOnly',
            subtitleKey: 'settings.wifiOnlySub'),
        Divider(height: 1),
        Expanded(child: ModelsView()),
      ]);
}

class _TranscribeTab extends StatelessWidget {
  const _TranscribeTab();
  @override
  Widget build(BuildContext context) => ListView(children: [
        _Section('settings.transcription', [
          const _Choice(SettingKeys.sttLanguage, 'settings.sttLanguage', [
            ('', 'lang.auto'),
            ('ko', 'lang.ko'),
            ('en', 'lang.en'),
            ('ja', 'lang.ja'),
            ('zh', 'lang.zh'),
          ]),
          _Choice(SettingKeys.sttSpeed, 'settings.sttSpeed',
              [for (final v in sttSpeedChoices) (v, '$v%')],
              translate: false),
          const _Note('settings.sttSpeedHint'),
        ]),
      ]);
}

/// 항목 아래 짧은 설명
class _Note extends StatelessWidget {
  const _Note(this.textKey);
  final String textKey;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(context.tr(textKey), style: Theme.of(context).textTheme.bodySmall),
      );
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab();
  @override
  Widget build(BuildContext context) => ListView(children: [
        _Section('settings.summary', [
          _Choice(SettingKeys.summaryType, 'settings.defaultSummaryType',
              [for (final t in SummaryType.values) (t.name, t.labelKey)]),
          const _Choice(SettingKeys.summaryLanguage, 'settings.outputLanguage',
              [('ko', 'lang.ko'), ('en', 'lang.en')]),
          const _Choice(SettingKeys.summaryLength, 'settings.length', [
            ('short', 'length.short'),
            ('medium', 'length.medium'),
            ('long', 'length.long')
          ]),
        ]),
      ]);
}

class _CloudTab extends ConsumerStatefulWidget {
  const _CloudTab();
  @override
  ConsumerState<_CloudTab> createState() => _CloudTabState();
}

class _CloudTabState extends ConsumerState<_CloudTab> {
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  /// 외부 전송 고지·동의 (COMPLIANCE: PIPA 제3자 발언 포함 가능)
  Future<bool> _consent() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('cloud.consentTitle')),
          content: Text(context.tr('cloud.consentBody')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.tr('common.cancel'))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.tr('cloud.agree'))),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final keys = ref.watch(cloudKeysProvider);
    final provider =
        CloudProvider.values.asNameMap()[s.get(SettingKeys.cloudProvider)] ??
            CloudProvider.openai;
    final enabled = s.getBool(SettingKeys.cloudEnabled);
    final active = ref.watch(cloudLlmProvider)();
    return ListView(children: [
      _Section('cloud.section', [
        SwitchListTile(
          dense: true,
          title: Text(context.tr('cloud.toggle')),
          subtitle: Text(context.tr('cloud.toggleSub')),
          value: enabled,
          onChanged: (v) async {
            if (v && !await _consent()) return;
            s.setBool(SettingKeys.cloudEnabled, v);
          },
        ),
        const _Choice(SettingKeys.cloudProvider, 'cloud.provider',
            [('openai', 'cloud.openaiCompat'), ('anthropic', 'Anthropic')]),
        if (provider == CloudProvider.openai)
          _TextSetting(SettingKeys.cloudBaseUrl, context.tr('cloud.baseUrl')),
        _TextSetting(
            SettingKeys.cloudModel,
            provider == CloudProvider.anthropic
                ? context
                    .tr('cloud.modelOptional', {'model': anthropicDefaultModel})
                : context.tr('cloud.modelRequired')),
        ListTile(
          dense: true,
          title: TextField(
            controller: _key,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.tr('cloud.apiKey'),
              hintText: context.tr(keys.of(provider) == null
                  ? 'cloud.keyHintEmpty'
                  : 'cloud.keyHintSaved'),
            ),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: context.tr('cloud.saveKey'),
              icon: const Icon(Icons.save),
              onPressed: () async {
                await keys.set(provider, _key.text.trim());
                _key.clear();
              },
            ),
            if (keys.of(provider) != null)
              IconButton(
                tooltip: context.tr('cloud.deleteKey'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => keys.set(provider, null),
              ),
          ]),
        ),
        ListTile(
          dense: true,
          leading: Icon(active == null ? Icons.phone_android : Icons.cloud_done,
              color: active == null ? VoxColors.text : VoxColors.accent),
          title: Text(active == null
              ? context.tr('cloud.engineLocal')
              : context.tr('cloud.engineCloud', {'id': active.id})),
        ),
      ]),
    ]);
  }
}

class _TextSetting extends ConsumerStatefulWidget {
  const _TextSetting(this.keyName, this.label);
  final String keyName;
  final String label;
  @override
  ConsumerState<_TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends ConsumerState<_TextSetting> {
  late final _c = TextEditingController(
      text: ref.read(settingsProvider).get(widget.keyName));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: TextField(
          controller: _c,
          decoration: InputDecoration(labelText: widget.label),
          onChanged: (v) =>
              ref.read(settingsProvider).set(widget.keyName, v.trim()),
        ),
      );
}

class _StorageTab extends ConsumerStatefulWidget {
  const _StorageTab();
  @override
  ConsumerState<_StorageTab> createState() => _StorageTabState();
}

class _StorageTabState extends ConsumerState<_StorageTab> {
  Future<int> _size(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final f in dir.list(recursive: true)) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final root = ref.watch(appDirProvider);
    final log = ref.watch(networkLogProvider);
    Widget usage(String label, String sub) => FutureBuilder<int>(
          future: _size('$root/$sub'),
          builder: (context, snap) => ListTile(
            dense: true,
            title: Text(label),
            trailing: Text(snap.hasData ? formatBytes(snap.data!) : '…'),
          ),
        );
    return ListView(children: [
      _Section('storage.section', [
        usage(context.tr('storage.models'), 'models'),
        usage(context.tr('storage.media'), 'media'),
        usage(context.tr('storage.tmp'), 'tmp'),
        ListTile(
          dense: true,
          title: Text(context.tr('storage.clearTmp')),
          trailing: const Icon(Icons.cleaning_services_outlined),
          onTap: () async {
            final tmp = Directory('$root/tmp');
            if (await tmp.exists()) await tmp.delete(recursive: true);
            setState(() {});
          },
        ),
      ]),
      _Section('storage.netLog', [
        ListTile(
          dense: true,
          title: Text(context.tr('storage.netSummary', {
            'downloads': log.of(NetPurpose.modelDownload).length,
            'cloud': log.of(NetPurpose.cloud).length,
          })),
          subtitle: Text(context.tr('storage.netSub')),
        ),
        for (final r in log.records.reversed.take(20))
          ListTile(
            dense: true,
            leading: Icon(
                r.purpose == NetPurpose.cloud
                    ? Icons.cloud_upload
                    : Icons.download,
                size: 16),
            title: Text(r.host),
            trailing: Text(r.at.toLocal().toString().substring(11, 19)),
          ),
      ]),
    ]);
  }
}
