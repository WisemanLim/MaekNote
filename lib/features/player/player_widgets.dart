// maeknote — 플레이어 헤더 · 제어줄 · 재생 버튼줄 (Image #1)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../shell/main_screen.dart';
import 'player_service.dart';

/// 소스 · 제목 + 전체 재생 시간 (VOX 처럼 제목 옆). 재생 위치는 얇은 진행선으로만 표시하고,
/// 시크바·볼륨·반복·EQ 는 헤더를 가리키면 열리는 [PlayerControls] 에 둔다.
class PlayerHeader extends ConsumerWidget {
  const PlayerHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final item = player.current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item?.source ?? 'MaekNote',
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(children: [
            Expanded(
              child: Text(item?.title ?? context.tr('player.empty'),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: VoxColors.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if (item != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(formatClock(player.duration),
                    style:
                        const TextStyle(fontSize: 13, color: VoxColors.text)),
              ),
          ]),
          if (item != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ValueListenableBuilder<Duration>(
                valueListenable: player.position,
                builder: (context, pos, _) {
                  final total = player.duration.inMilliseconds;
                  return LinearProgressIndicator(
                    value: total <= 0
                        ? 0
                        : (pos.inMilliseconds / total).clamp(0.0, 1.0),
                    minHeight: 2,
                    backgroundColor: VoxColors.divider,
                    color: VoxColors.accent,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SeekBar extends ConsumerWidget {
  const _SeekBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    return ValueListenableBuilder<Duration>(
      valueListenable: player.position,
      builder: (context, pos, _) {
        final total = player.duration.inMilliseconds;
        final value =
            total <= 0 ? 0.0 : (pos.inMilliseconds / total).clamp(0.0, 1.0);
        return Row(children: [
          Text(formatClock(pos), style: Theme.of(context).textTheme.bodySmall),
          Expanded(
            child: Slider(
              value: value,
              semanticFormatterCallback: (_) => formatClock(pos),
              onChanged: total <= 0
                  ? null
                  : (v) =>
                      player.seek(Duration(milliseconds: (v * total).round())),
            ),
          ),
          Text(formatClock(player.duration),
              style: Theme.of(context).textTheme.bodySmall),
        ]);
      },
    );
  }
}

class PlayerControls extends ConsumerWidget {
  const PlayerControls({super.key, required this.panel, required this.toggle});

  final OverlayPanel panel;
  final ValueChanged<OverlayPanel> toggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    Color on(bool v) => v ? VoxColors.accent : VoxColors.text;
    // 휴대폰 폭에서는 볼륨 −/+ 버튼을 숨기고 슬라이더만 둔다 (터치 영역 유지)
    return LayoutBuilder(builder: (context, c) {
      // 플레이어 칸이 좁으면(VOX 322px) 볼륨 −/+ 를 숨긴다 — 노트 패널을 펼쳐도 같은 기준
      final compact = c.maxWidth < 420;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (player.current != null)
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: _SeekBar()),
          Row(children: [
            IconButton(
              tooltip: switch (player.repeat) {
                LoopMode.off => context.tr('player.repeatOff'),
                LoopMode.all => context.tr('player.repeatAll'),
                LoopMode.one => context.tr('player.repeatOne'),
              },
              icon: Icon(
                  player.repeat == LoopMode.one
                      ? Icons.repeat_one
                      : Icons.repeat,
                  color: on(player.repeat != LoopMode.off)),
              onPressed: player.cycleRepeat,
            ),
            IconButton(
              tooltip: context.tr('player.shuffle'),
              icon: Icon(Icons.shuffle, color: on(player.shuffle)),
              onPressed: player.toggleShuffle,
            ),
            if (!compact)
              IconButton(
                tooltip: context.tr('player.volumeDown'),
                icon: const Icon(Icons.remove, size: 16),
                onPressed: () => player.setVolume(player.volume - 10),
              ),
            Expanded(
              child: Slider(
                value: player.volume,
                max: 100,
                semanticFormatterCallback: (v) =>
                    context.tr('player.volume', {'value': v.round()}),
                onChanged: player.setVolume,
              ),
            ),
            if (!compact)
              IconButton(
                tooltip: context.tr('player.volumeUp'),
                icon: const Icon(Icons.add, size: 16),
                onPressed: () => player.setVolume(player.volume + 10),
              ),
            IconButton(
              tooltip: context.tr('player.equalizer'),
              icon:
                  Icon(Icons.tune, color: on(panel == OverlayPanel.equalizer)),
              onPressed: () => toggle(OverlayPanel.equalizer),
            ),
            IconButton(
              tooltip: context.tr('player.output'),
              icon:
                  Icon(Icons.speaker, color: on(panel == OverlayPanel.output)),
              onPressed: () => toggle(OverlayPanel.output),
            ),
          ]),
        ]),
      );
    });
  }
}

class TransportBar extends ConsumerWidget {
  const TransportBar({super.key, required this.onMore});

  final void Function(BuildContext context) onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    return Row(children: [
      Expanded(
        child: IconButton(
          tooltip: context.tr('player.more'),
          icon: const Icon(Icons.more_horiz),
          onPressed: () => onMore(context),
        ),
      ),
      Expanded(
        child: IconButton(
          tooltip: context.tr('player.previous'),
          icon: const Icon(Icons.fast_rewind),
          onPressed: player.previous,
        ),
      ),
      Expanded(
        child: IconButton(
          tooltip: context.tr(player.playing ? 'player.pause' : 'player.play'),
          iconSize: 28,
          icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
          onPressed: player.togglePlay,
        ),
      ),
      Expanded(
        child: IconButton(
          tooltip: context.tr('player.next'),
          icon: const Icon(Icons.fast_forward),
          onPressed: player.next,
        ),
      ),
      Expanded(
        child: IconButton(
          tooltip: context.tr('player.search'),
          icon: const Icon(Icons.search),
          onPressed: () {
            final search = ref.read(librarySearchProvider.notifier);
            search.state = search.state == null ? '' : null;
          },
        ),
      ),
    ]);
  }
}
