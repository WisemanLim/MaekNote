// maeknote — 모델 관리자 화면 (선택 · 다운로드 · 삭제 · 기본 지정)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import 'model_catalog.dart';
import 'model_store.dart';

String kindLabel(BuildContext context, ModelKind k) => context.tr('models.kind.${k.name}');

/// 다운로드 전 확인. 기기 메모리에 비해 큰 모델이면 경고 (PRD AC5)
Future<void> confirmAndInstall(
    BuildContext context, WidgetRef ref, ModelSpec spec) async {
  final device = ref.read(deviceProvider);
  final fit = device.fit(spec);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(spec.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fit != Fit.ok)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                fit == Fit.unsupported
                    ? context.tr('models.unsupportedDetail', {
                        'need': formatBytes(spec.ramMb << 20),
                        'have': formatBytes(device.ramMb << 20),
                      })
                    : context.tr('models.slowDetail', {'need': formatBytes(spec.ramMb << 20)}),
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          Text(context.tr('models.downloadSize', {'size': formatBytes(spec.sizeBytes)})),
          Text(context.tr('models.license', {'license': spec.license})),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common.cancel'))),
        TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr(fit == Fit.ok ? 'models.download' : 'models.downloadAnyway'))),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(modelStoreProvider).install(spec);
  } catch (e) {
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(context.trError(e))));
  }
}

/// 필요한 모델이 없을 때 권장 모델 안내 (PRD AC4)
Future<void> showModelRequired(
    BuildContext context, WidgetRef ref, ModelKind kind) {
  final device = ref.read(deviceProvider);
  final spec = ref.read(catalogProvider).recommended(kind, device);
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('models.required', {'kind': kindLabel(context, kind)}),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(context.tr('models.deviceTier',
                {'memory': formatBytes(device.ramMb << 20), 'tier': device.tier})),
            if (spec != null) ...[
              const SizedBox(height: 8),
              Text(context.tr('models.recommendedModel', {'name': spec.name})),
              Text(
                  context.tr('models.sizeTime',
                      {'size': formatBytes(spec.sizeBytes), 'minutes': spec.minPerHour}),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  confirmAndInstall(context, ref, spec);
                },
                child: Text(context.tr('models.downloadRecommended')),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class ModelsView extends ConsumerWidget {
  const ModelsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider);
    final catalog = ref.watch(catalogProvider);
    final stt = catalog.recommended(ModelKind.stt, device);
    final llm = catalog.recommended(ModelKind.llm, device);
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            context.tr('models.header', {
              'memory': formatBytes(device.ramMb << 20),
              'tier': device.tier,
              'stt': stt?.name ?? '-',
              'llm': llm?.name ?? '-',
            }),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TabBar(tabs: [
          Tab(text: kindLabel(context, ModelKind.stt)),
          Tab(text: kindLabel(context, ModelKind.llm)),
        ]),
        const Expanded(
          child: TabBarView(children: [
            _ModelList(kind: ModelKind.stt),
            _ModelList(kind: ModelKind.llm),
          ]),
        ),
      ]),
    );
  }
}

class _ModelList extends ConsumerWidget {
  const _ModelList({required this.kind});
  final ModelKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(modelStoreProvider);
    final device = ref.watch(deviceProvider);
    final recommended = store.catalog.recommended(kind, device);
    final defaultId = store.defaultModel(kind)?.id;
    return ListView(children: [
      for (final spec in store.catalog.ofKind(kind))
        _ModelTile(
          spec: spec,
          fit: device.fit(spec),
          installed: store.isInstalled(spec.id),
          isDefault: spec.id == defaultId,
          isRecommended: spec.id == recommended?.id,
          download: store.downloads[spec.id],
        ),
    ]);
  }
}

class _ModelTile extends ConsumerWidget {
  const _ModelTile({
    required this.spec,
    required this.fit,
    required this.installed,
    required this.isDefault,
    required this.isRecommended,
    required this.download,
  });

  final ModelSpec spec;
  final Fit fit;
  final bool installed;
  final bool isDefault;
  final bool isRecommended;
  final DownloadState? download;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(modelStoreProvider);
    final small = Theme.of(context).textTheme.bodySmall;
    final running = download != null && download!.error == null;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: isDefault ? VoxColors.accent : VoxColors.panel,
        child: Text('T${spec.tier}',
            style: TextStyle(
                fontSize: 11,
                color: isDefault ? Colors.black : VoxColors.text)),
      ),
      title: Row(children: [
        Flexible(child: Text(spec.name, overflow: TextOverflow.ellipsis)),
        if (isRecommended)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(context.tr('models.recommended'),
                style: const TextStyle(color: VoxColors.accent, fontSize: 11)),
          ),
      ]),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              context.tr('models.tileInfo', {
                'size': formatBytes(spec.sizeBytes),
                'memory': formatBytes(spec.ramMb << 20),
                'license': spec.license,
                'minutes': spec.minPerHour,
              }),
              style: small),
          if (fit != Fit.ok)
            Text(context.tr(fit == Fit.unsupported ? 'models.unsupported' : 'models.slow'),
                style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
          if (running)
            LinearProgressIndicator(
              value: download!.fraction,
              semanticsLabel: context.tr('models.downloadOf', {'name': spec.name}),
              semanticsValue: '${(download!.fraction * 100).round()}%',
            ),
          if (download?.error != null)
            Text(context.trError(download!.error!),
                style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
        ],
      ),
      trailing: running
          ? IconButton(
              tooltip: context.tr('models.cancelDownload'),
              icon: const Icon(Icons.close),
              onPressed: () => store.cancel(spec.id))
          : installed
              ? PopupMenuButton<String>(
                  tooltip: context.tr('models.menu'),
                  icon: Icon(isDefault ? Icons.check_circle : Icons.check,
                      color: isDefault ? VoxColors.accent : VoxColors.text),
                  onSelected: (v) =>
                      v == 'default' ? store.setDefault(spec) : store.delete(spec),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'default', child: Text(context.tr('models.setDefault'))),
                    PopupMenuItem(value: 'delete', child: Text(context.tr('common.delete'))),
                  ],
                )
              : IconButton(
                  tooltip: context.tr('models.download'),
                  icon: const Icon(Icons.download),
                  onPressed: () => confirmAndInstall(context, ref, spec),
                ),
    );
  }
}
