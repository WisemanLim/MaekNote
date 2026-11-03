// maeknote — 요약 탭: 유형 선택 · 생성 · 시간 링크 (PRD F3, AC3)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../library/library_repo.dart';
import '../models/models_view.dart';
import '../settings/settings_repo.dart';
import '../transcribe/transcribe_service.dart';
import '../transcribe/transcript_view.dart';
import 'summarizer.dart';

class SummaryView extends ConsumerStatefulWidget {
  const SummaryView({super.key, required this.item});
  final MediaItem item;

  @override
  ConsumerState<SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends ConsumerState<SummaryView> {
  late SummaryType _type = SummaryType.values.asNameMap()[
          ref.read(settingsProvider).get(SettingKeys.summaryType)] ??
      SummaryType.lecture;

  Future<void> _generate() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(summaryServiceProvider).summarize(widget.item.id, _type);
    } on ModelMissingException catch (e) {
      if (mounted) await showModelRequired(context, ref, e.kind);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text(context.tr('summary.failed', {'error': context.trError(e)}))));
      }
    }
  }

  /// 요약 항목 → 원문 구간으로 이동 후 전사 탭에서 강조 (AC3)
  void _jump(SummaryItem item) {
    seekMedia(ref, widget.item, item.startMs!);
    DefaultTabController.maybeOf(context)?.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(summaryServiceProvider);
    final summary = service.latest(widget.item.id, _type);
    final progress = service.running[widget.item.id];
    final hasTranscript =
        ref.watch(transcriptRepoProvider).segments(widget.item.id).isNotEmpty;
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          for (final t in SummaryType.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(context.tr(t.labelKey)),
                selected: t == _type,
                selectedColor: VoxColors.accent,
                labelStyle: TextStyle(color: t == _type ? Colors.black : VoxColors.text),
                onSelected: (_) {
                  setState(() => _type = t);
                  ref.read(settingsProvider).set(SettingKeys.summaryType, t.name);
                },
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Expanded(
            child: Text(
              summary == null
                  ? (hasTranscript
                      ? context.tr('summary.none', {'type': context.tr(_type.labelKey)})
                      : context.tr('error.transcribeFirst'))
                  : '${summary.modelId} · ${summary.createdAt.toLocal().toString().substring(0, 16)}',
              style: small,
            ),
          ),
          FilledButton.tonal(
            onPressed: progress != null || !hasTranscript ? null : _generate,
            child: Text(context.tr(summary == null ? 'summary.generate' : 'summary.regenerate')),
          ),
        ]),
      ),
      if (progress != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            LinearProgressIndicator(
              value: progress.$2 == 0 ? null : progress.$1 / progress.$2,
              semanticsLabel: context.tr('summary.progressLabel'),
            ),
            Text(context.tr('summary.running', {'done': progress.$1, 'total': progress.$2}),
                style: small),
          ]),
        ),
      if (summary != null)
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            for (final section in summary.sections) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(section.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: VoxColors.accent)),
              ),
              for (final it in section.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('• '),
                    Expanded(child: Text(it.text)),
                    if (it.startMs != null)
                      TextButton(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(44, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 6)),
                        onPressed: () => _jump(it),
                        child: Text(
                          '[${formatClock(Duration(milliseconds: it.startMs!))}]',
                          semanticsLabel: context.tr('summary.jump',
                              {'time': formatClock(Duration(milliseconds: it.startMs!))}),
                        ),
                      ),
                  ]),
                ),
            ],
          ]),
        ),
    ]);
  }
}
