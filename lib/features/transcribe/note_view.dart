// maeknote — 노트: 현재 재생 파일의 전사 · 요약 서브 탭
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../export/export_action.dart';
import '../library/library_repo.dart';
import 'transcribe_actions.dart';
import 'transcript_repo.dart';
import 'transcript_view.dart';

class NoteView extends ConsumerWidget {
  const NoteView({super.key, required this.summary, this.onClose});

  /// 요약 탭 내용 (미디어별)
  final Widget Function(MediaItem item) summary;

  /// 데스크톱 오른쪽 패널 닫기
  final VoidCallback? onClose;

  Widget _close(BuildContext context) => IconButton(
        tooltip: context.tr('note.closePanel'),
        icon: const Icon(Icons.chevron_left),
        onPressed: onClose,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(playerProvider.select((p) => p.current));
    if (item == null) {
      return Column(children: [
        if (onClose != null) Align(alignment: Alignment.centerLeft, child: _close(context)),
        Expanded(
          child: Center(
            child: Text(context.tr('note.empty'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      ]);
    }
    final info = ref.watch(transcriptRepoProvider).info(item.id);
    return DefaultTabController(
      key: ValueKey(item.id),
      length: 2,
      child: Column(children: [
        Row(children: [
          if (onClose != null) _close(context),
          Expanded(
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: context.tr('note.transcript')),
                Tab(text: context.tr('note.summary')),
              ],
            ),
          ),
          if (info.status == TranscriptStatus.none ||
              info.status == TranscriptStatus.error)
            IconButton(
              tooltip: context.tr('transcribe.start'),
              icon: const Icon(Icons.subject),
              onPressed: () => startTranscribe(context, ref, item),
            ),
          if (info.status == TranscriptStatus.done) ExportButton(item: item),
          if (info.running)
            IconButton(
              tooltip: context.tr('transcribe.cancel'),
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () => ref.read(transcribeServiceProvider).cancel(item.id),
            ),
        ]),
        if (info.status == TranscriptStatus.error && info.error != null)
          Text(context.trError(AppError.decode(info.error!)),
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        Expanded(
          child: TabBarView(children: [
            TranscriptView(key: ValueKey('t${item.id}'), item: item),
            summary(item),
          ]),
        ),
      ]),
    );
  }
}
