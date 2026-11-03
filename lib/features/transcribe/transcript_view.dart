// maeknote — 전사 탭: 재생 위치 추적 · 하이라이트 · 클릭 이동 · 검색 (PRD F4, AC1·AC2)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../library/library_repo.dart';
import 'transcript_repo.dart';

/// 해당 미디어의 [ms] 위치로 이동 (다른 파일이면 그 파일을 열고 이동)
Future<void> seekMedia(WidgetRef ref, MediaItem item, int ms) {
  final player = ref.read(playerProvider);
  final to = Duration(milliseconds: ms);
  if (player.current?.id == item.id) return player.seek(to);
  return player.playItem(item, ref.read(libraryProvider).playlist(), startAt: to);
}

class TranscriptView extends ConsumerStatefulWidget {
  const TranscriptView({super.key, required this.item});
  final MediaItem item;

  @override
  ConsumerState<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends ConsumerState<TranscriptView> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  final _search = TextEditingController();
  int _current = -1;
  DateTime _userScrolledAt = DateTime(0);
  Set<int> _matches = {};
  int _matchCursor = -1;
  late final ValueNotifier<Duration> _position;

  @override
  void initState() {
    super.initState();
    _position = ref.read(playerProvider).position..addListener(_onPosition);
    // 탭 전환 직후(일시정지 상태 포함)에도 현재 위치 구간을 바로 강조
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onPosition();
    });
  }

  @override
  void dispose() {
    _position.removeListener(_onPosition);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  List<StoredSegment> get _segments =>
      ref.read(transcriptRepoProvider).segments(widget.item.id);

  void _onPosition() {
    final player = ref.read(playerProvider);
    if (player.current?.id != widget.item.id) return;
    final segs = _segments;
    final i = segmentIndexAt(segs, player.position.value.inMilliseconds);
    if (i == _current) return;
    setState(() => _current = i);
    // 사용자가 직접 스크롤한 직후 3초간은 자동 스크롤하지 않음
    if (i >= 0 &&
        DateTime.now().difference(_userScrolledAt) > const Duration(seconds: 3)) {
      _reveal(segs[i].id);
    }
  }

  void _reveal(int segmentId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[segmentId]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.3, duration: const Duration(milliseconds: 200));
      }
    });
  }

  void _runSearch(String q) {
    setState(() {
      _matches = ref.read(transcriptRepoProvider).search(widget.item.id, q);
      _matchCursor = -1;
    });
  }

  void _nextMatch(List<StoredSegment> segs, int dir) {
    final ordered = [for (final s in segs) if (_matches.contains(s.id)) s.id];
    if (ordered.isEmpty) return;
    setState(() => _matchCursor = (_matchCursor + dir) % ordered.length);
    _userScrolledAt = DateTime.now();
    _reveal(ordered[_matchCursor]);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(transcriptRepoProvider);
    final segs = repo.segments(widget.item.id);
    final info = repo.info(widget.item.id);
    final small = Theme.of(context).textTheme.bodySmall;
    // 전사는 백그라운드 작업 — 끝날 때까지 부분 결과 대신 진행률만, 완료되면 전체를 표시
    if (info.running) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(
              value: info.progress,
              minHeight: 3,
              backgroundColor: VoxColors.divider,
              color: VoxColors.accent,
            ),
            const SizedBox(height: 8),
            Text(context.tr('transcript.running', {'percent': (info.progress * 100).round()}),
                textAlign: TextAlign.center, style: small),
          ]),
        ),
      );
    }
    if (segs.isEmpty) {
      return Center(child: Text(context.tr('transcript.empty'), style: small));
    }
    final ordered = [for (final s in segs) if (_matches.contains(s.id)) s.id];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                  hintText: context.tr('transcript.searchHint'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true),
              onChanged: _runSearch,
            ),
          ),
          if (_search.text.isNotEmpty) ...[
            Text(' ${ordered.isEmpty ? 0 : _matchCursor + 1}/${ordered.length}', style: small),
            IconButton(
                tooltip: context.tr('transcript.prevMatch'),
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: () => _nextMatch(segs, -1)),
            IconButton(
                tooltip: context.tr('transcript.nextMatch'),
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: () => _nextMatch(segs, 1)),
          ],
        ]),
      ),
      if (info.running)
        LinearProgressIndicator(
            value: info.progress, semanticsLabel: context.tr('transcript.progress')),
      Expanded(
        child: NotificationListener<UserScrollNotification>(
          onNotification: (_) {
            _userScrolledAt = DateTime.now();
            return false;
          },
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              for (var i = 0; i < segs.length; i++)
                _SegmentRow(
                  key: _keys.putIfAbsent(segs[i].id, GlobalKey.new),
                  segment: segs[i],
                  active: i == _current,
                  matched: _matches.contains(segs[i].id),
                  onTap: () => seekMedia(ref, widget.item, segs[i].startMs),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    super.key,
    required this.segment,
    required this.active,
    required this.matched,
    required this.onTap,
  });

  final StoredSegment segment;
  final bool active;
  final bool matched;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = formatClock(Duration(milliseconds: segment.startMs));
    return Semantics(
      button: true,
      selected: active,
      label: '$time ${segment.text}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? VoxColors.panel : null,
            // 색 외에 왼쪽 막대로도 현재 구간 표시
            border: Border(
              left: BorderSide(
                  color: active ? VoxColors.accent : Colors.transparent, width: 3),
            ),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 56,
              child: Text('[$time]',
                  style: TextStyle(
                      color: active ? VoxColors.accent : VoxColors.muted,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            Expanded(
              child: Text(
                segment.text,
                style: TextStyle(
                  color: VoxColors.text,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  decoration: matched ? TextDecoration.underline : null,
                  decorationColor: VoxColors.accent,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
