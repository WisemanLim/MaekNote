// maeknote — 라이브러리 항목의 전사 메뉴 · 상태 배지
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../library/library_repo.dart';
import '../models/models_view.dart';
import 'transcribe_service.dart';
import 'transcript_repo.dart';

/// 전사는 백그라운드로 진행 — 시작해도 재생·화면을 바꾸지 않고 목록 배지로 진행률만 보인다.
/// 끝나면 [showTranscript] 로 결과를 보여준다.
Future<void> startTranscribe(
    BuildContext context, WidgetRef ref, MediaItem item) async {
  final messenger = ScaffoldMessenger.of(context);
  final i18n = ref.read(i18nProvider);
  final service = ref.read(transcribeServiceProvider);
  try {
    await service.transcribe(item);
  } on ModelMissingException catch (e) {
    if (context.mounted) await showModelRequired(context, ref, e.kind);
    return;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('${item.title}: ${i18n.error(e)}')));
    return;
  }
  await showTranscript(ref, messenger, item);
}

/// 전사가 끝난 파일을 노트(전사 탭)에 띄운다. 다른 파일을 재생 중이면 끊지 않고 "보기" 알림만.
Future<void> showTranscript(
    WidgetRef ref, ScaffoldMessengerState messenger, MediaItem item) async {
  final player = ref.read(playerProvider);
  Future<void> open() async {
    if (player.current?.id != item.id) {
      await player.playItem(item, ref.read(libraryProvider).playlist(), autoplay: false);
    }
    ref.read(notePanelProvider.notifier).state = true; // 데스크톱: 오른쪽 패널
    ref.read(showNoteRequestProvider.notifier).state++; // 휴대폰: 노트 탭으로
  }

  final i18n = ref.read(i18nProvider);
  final busy = player.current != null && player.current!.id != item.id && player.playing;
  if (!busy) return open();
  messenger.showSnackBar(SnackBar(
    content: Text(i18n.t('transcribe.doneNotice', {'title': item.title})),
    action: SnackBarAction(label: i18n.t('transcribe.view'), onPressed: open),
  ));
}

List<PopupMenuEntry<VoidCallback>> transcribeMenu(
    BuildContext context, WidgetRef ref, MediaItem item) {
  final info = ref.read(transcriptRepoProvider).info(item.id);
  return [
    if (info.running)
      PopupMenuItem(
        value: () => ref.read(transcribeServiceProvider).cancel(item.id),
        child: Text(context.tr('transcribe.cancel')),
      )
    else
      PopupMenuItem(
        value: () => startTranscribe(context, ref, item),
        child: Text(context.tr(
            info.status == TranscriptStatus.none ? 'transcribe.start' : 'transcribe.again')),
      ),
  ];
}

class TranscriptBadge extends ConsumerWidget {
  const TranscriptBadge({super.key, required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(transcriptRepoProvider).info(item.id);
    final small = Theme.of(context).textTheme.bodySmall;
    return switch (info.status) {
      TranscriptStatus.none => const SizedBox.shrink(),
      // 좁은 플레이어(322px)에 맞게 짧게: 아이콘 + 퍼센트, 전체 문구는 툴팁
      TranscriptStatus.decoding || TranscriptStatus.transcribing => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Tooltip(
            message: context.tr('transcribe.progress', {'percent': (info.progress * 100).round()}),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.hourglass_top, size: 12, color: VoxColors.accent),
              Text('${(info.progress * 100).round()}%',
                  style: small?.copyWith(color: VoxColors.accent)),
            ]),
          ),
        ),
      TranscriptStatus.done => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(Icons.subject, size: 14, color: VoxColors.accent,
              semanticLabel: context.tr('transcribe.done')),
        ),
      TranscriptStatus.error => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Tooltip(
            message: info.error == null ? '' : context.trError(AppError.decode(info.error!)),
            child: Icon(Icons.error_outline, size: 14,
                color: Colors.redAccent, semanticLabel: context.tr('transcribe.failed')),
          ),
        ),
    };
  }
}
