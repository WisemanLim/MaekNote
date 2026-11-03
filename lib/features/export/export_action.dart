// maeknote — 내보내기 메뉴 (형식 선택 → 저장 위치 선택)
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../library/library_repo.dart';
import '../settings/settings_repo.dart';
import '../summary/summarizer.dart';
import '../summary/summary_service.dart';
import 'exporter.dart';

/// 내보내기 메뉴의 파일 저장 외 항목
enum ExportExtra { copySummary }

class ExportButton extends ConsumerWidget {
  const ExportButton({super.key, required this.item});
  final MediaItem item;

  /// 요약 탭에 보이는 유형(선택하면 설정에 저장됨)의 최신 요약
  StoredSummary? _shownSummary(WidgetRef ref) {
    final type = SummaryType.values
            .asNameMap()[ref.read(settingsProvider).get(SettingKeys.summaryType)] ??
        SummaryType.lecture;
    return ref.read(summaryServiceProvider).latest(item.id, type);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<Object>(
      tooltip: context.tr('export.menu'),
      icon: const Icon(Icons.ios_share, size: 18),
      itemBuilder: (_) => [
        for (final f in ExportFormat.values)
          PopupMenuItem(value: f, child: Text(context.tr('export.${f.name}'))),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: ExportExtra.copySummary,
          enabled: _shownSummary(ref) != null,
          child: Row(children: [
            const Icon(Icons.copy, size: 16),
            const SizedBox(width: 8),
            Text(context.tr('export.copySummary')),
          ]),
        ),
      ],
      onSelected: (action) async {
        final messenger = ScaffoldMessenger.of(context);
        if (action == ExportExtra.copySummary) {
          final summary = _shownSummary(ref);
          if (summary == null) return;
          final copied = context.tr('export.copied');
          await Clipboard.setData(ClipboardData(
              text: exportSummary(item.title, summary, tr: context.tr)));
          messenger.showSnackBar(SnackBar(content: Text(copied)));
          return;
        }
        final format = action as ExportFormat;
        final segs = ref.read(transcriptRepoProvider).segments(item.id);
        final summaries = <StoredSummary>[
          for (final t in SummaryType.values)
            if (ref.read(summaryServiceProvider).latest(item.id, t) case final s?) s,
        ];
        final text = exportTranscript(item.title, segs, format,
            summaries: summaries, tr: context.tr);
        final saved = context.tr('export.saved');
        final uri = await FilePicker.saveFile(
          fileName: '${item.title}.${format.name}',
          bytes: Uint8List.fromList(utf8.encode(text)),
          mimeType: format == ExportFormat.md ? 'text/markdown' : 'text/plain',
        );
        if (uri != null) messenger.showSnackBar(SnackBar(content: Text(saved)));
      },
    );
  }
}
