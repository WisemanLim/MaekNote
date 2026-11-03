// maeknote — 재생목록 · 컬렉션 (Image #1 하단)
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import 'library_repo.dart';

Future<void> importMedia(WidgetRef ref) async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: [...audioExtensions, ...videoExtensions],
  );
  final paths = [
    for (final f in files)
      if (f.path != null) f.path!
  ];
  if (paths.isNotEmpty) await ref.read(libraryProvider).import(paths);
}

/// 파일·폴더를 끌어다 놓아 가져오는 영역 (데스크톱).
/// [collectionAt] 이 놓은 위치의 컬렉션 id 를 돌려주면 그 컬렉션에도 넣는다.
class MediaDropZone extends ConsumerStatefulWidget {
  const MediaDropZone(
      {super.key, required this.child, this.collectionAt, this.onHover});

  final Widget child;
  final int? Function(Offset global)? collectionAt;

  /// 끄는 중 위치(전역 좌표), 벗어나면 null — 항목 강조용
  final ValueChanged<Offset?>? onHover;

  @override
  ConsumerState<MediaDropZone> createState() => _MediaDropZoneState();
}

class _MediaDropZoneState extends ConsumerState<MediaDropZone> {
  bool _over = false;

  void _hover(Offset? global) {
    if (_over != (global != null)) setState(() => _over = global != null);
    widget.onHover?.call(global);
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: ref.watch(isDesktopProvider),
      onDragEntered: (d) => _hover(d.globalPosition),
      onDragUpdated: (d) => _hover(d.globalPosition),
      onDragExited: (_) => _hover(null),
      onDragDone: (d) async {
        _hover(null);
        final collection = widget.collectionAt?.call(d.globalPosition);
        // macOS 샌드박스: 끌어온 파일·폴더는 보안 범위 북마크로 접근을 열고 복사한 뒤 닫는다
        final bookmarks = [
          for (final f in d.files)
            if (f.extraAppleBookmark?.isNotEmpty ?? false) f.extraAppleBookmark!,
        ];
        for (final b in bookmarks) {
          await DesktopDrop.instance
              .startAccessingSecurityScopedResource(bookmark: b);
        }
        try {
          final paths = mediaPathsFrom(d.files.map((f) => f.path));
          if (paths.isEmpty) return;
          await ref
              .read(libraryProvider)
              .importTo(paths, collectionId: collection);
        } finally {
          for (final b in bookmarks) {
            await DesktopDrop.instance
                .stopAccessingSecurityScopedResource(bookmark: b);
          }
        }
      },
      child: Stack(children: [
        Positioned.fill(child: widget.child),
        if (_over)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                alignment: Alignment.bottomCenter,
                padding: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: VoxColors.accent.withValues(alpha: 0.08),
                  border: Border.all(color: VoxColors.accent, width: 1.5),
                ),
                child: Text(context.tr('library.dropHere'),
                    style: const TextStyle(color: VoxColors.accent)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// 항목별 추가 메뉴 (전사 등 다른 기능이 덧붙임)
typedef MediaMenuBuilder = List<PopupMenuEntry<VoidCallback>> Function(
    BuildContext context, MediaItem item);

/// 항목 제목 옆 상태 표시 (전사/요약 상태 배지)
typedef MediaBadgeBuilder = Widget? Function(
    BuildContext context, MediaItem item);

class LibraryView extends StatelessWidget {
  const LibraryView({super.key, this.extraMenu, this.badge});

  final MediaMenuBuilder? extraMenu;
  final MediaBadgeBuilder? badge;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Row(children: [
          const Expanded(
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [Tab(text: 'Playlist'), Tab(text: 'Collections')],
            ),
          ),
          Consumer(
            builder: (context, ref, _) => Row(children: [
              IconButton(
                tooltip: context.tr('app.import'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => importMedia(ref),
              ),
              IconButton(
                tooltip: context.tr('library.clear'),
                icon: const Icon(Icons.highlight_off),
                onPressed: () => _confirmClear(context, ref),
              ),
            ]),
          ),
        ]),
        Expanded(
          child: TabBarView(children: [
            PlaylistView(extraMenu: extraMenu, badge: badge),
            CollectionsView(extraMenu: extraMenu, badge: badge),
          ]),
        ),
      ]),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('library.clear')),
        content: Text(context.tr('library.clearConfirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('common.cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('common.delete'))),
        ],
      ),
    );
    if (ok == true) await ref.read(libraryProvider).clear();
  }
}

class PlaylistView extends ConsumerWidget {
  const PlaylistView({super.key, this.extraMenu, this.badge});

  final MediaMenuBuilder? extraMenu;
  final MediaBadgeBuilder? badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final query = ref.watch(librarySearchProvider);
    final items = library.playlist(query: query ?? '');
    return MediaDropZone(
        child: Column(children: [
      if (query != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            autofocus: true,
            decoration: InputDecoration(
                hintText: context.tr('library.searchHint'),
                prefixIcon: const Icon(Icons.search)),
            onChanged: (v) =>
                ref.read(librarySearchProvider.notifier).state = v,
          ),
        ),
      Expanded(
        child: items.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    context.tr(
                        query == null ? 'library.empty' : 'library.noResults'),
                    style: Theme.of(context).textTheme.bodySmall),
                if (query == null && ref.watch(isDesktopProvider))
                  Text(context.tr('library.dropHint'),
                      style: Theme.of(context).textTheme.bodySmall),
              ]))
            : MediaList(items: items, extraMenu: extraMenu, badge: badge),
      ),
    ]));
  }
}

class MediaList extends ConsumerWidget {
  const MediaList({super.key, required this.items, this.extraMenu, this.badge});

  final List<MediaItem> items;
  final MediaMenuBuilder? extraMenu;
  final MediaBadgeBuilder? badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final isCurrent = player.current?.id == item.id;
        final b = badge?.call(context, item);
        return ListTile(
          dense: true,
          selected: isCurrent,
          selectedColor: VoxColors.accent,
          leading: SizedBox(
            width: 24,
            child: isCurrent
                ? const Icon(Icons.equalizer, color: VoxColors.accent, size: 18)
                : Text('${i + 1}',
                    style: Theme.of(context).textTheme.bodySmall),
          ),
          title: Row(children: [
            if (item.isVideo)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.movie_outlined, size: 14),
              ),
            // VOX 처럼 한 줄: 제목 + 흐린 출처
            Flexible(
              flex: 3,
              child: Text(item.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: Text(item.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            if (b != null) b,
          ]),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(formatMs(item.durationMs),
                style: Theme.of(context).textTheme.bodySmall),
            PopupMenuButton<VoidCallback>(
              tooltip: context.tr('library.itemMenu'),
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                ...?extraMenu?.call(context, item),
                PopupMenuItem(
                  value: () => _addToCollection(context, ref, item),
                  child: Text(context.tr('library.addToCollection')),
                ),
                PopupMenuItem(
                  value: () => ref.read(libraryProvider).remove(item.id),
                  child: Text(context.tr('common.delete')),
                ),
              ],
            ),
          ]),
          onTap: () => player.playItem(item, items),
        );
      },
    );
  }

  Future<void> _addToCollection(
      BuildContext context, WidgetRef ref, MediaItem item) async {
    final library = ref.read(libraryProvider);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('library.addToCollection')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final c in library.collections())
            ListTile(
              title: Text(c.name),
              onTap: () => Navigator.pop(context, c.name),
            ),
          TextField(
            controller: controller,
            decoration:
                InputDecoration(hintText: context.tr('library.newCollection')),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ]),
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final existing = library.collections().where((c) => c.name == name.trim());
    final id = existing.isEmpty
        ? library.createCollection(name.trim())
        : existing.first.id;
    library.addToCollection(id, item.id);
  }
}

class CollectionsView extends ConsumerStatefulWidget {
  const CollectionsView({super.key, this.extraMenu, this.badge});

  final MediaMenuBuilder? extraMenu;
  final MediaBadgeBuilder? badge;

  @override
  ConsumerState<CollectionsView> createState() => _CollectionsViewState();
}

class _CollectionsViewState extends ConsumerState<CollectionsView> {
  int? _open;
  int? _dropOn;
  final _tileKeys = <int, GlobalKey>{};

  /// 전역 좌표 아래 컬렉션 항목
  int? _collectionAt(Offset global) {
    for (final e in _tileKeys.entries) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      if (box != null &&
          (box.localToGlobal(Offset.zero) & box.size).contains(global)) {
        return e.key;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final open = _open;
    if (open != null) {
      return MediaDropZone(
          collectionAt: (_) => open,
          child: Column(children: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.arrow_back),
              title: Text(library
                      .collections()
                      .where((c) => c.id == open)
                      .firstOrNull
                      ?.name ??
                  ''),
              onTap: () => setState(() => _open = null),
            ),
            Expanded(
              child: MediaList(
                  items: library.collectionItems(open),
                  extraMenu: widget.extraMenu,
                  badge: widget.badge),
            ),
          ]));
    }
    final collections = library.collections();
    _tileKeys.removeWhere((id, _) => !collections.any((c) => c.id == id));
    return MediaDropZone(
      collectionAt: _collectionAt,
      onHover: (g) {
        final id = g == null ? null : _collectionAt(g);
        if (id != _dropOn) setState(() => _dropOn = id);
      },
      child: collections.isEmpty
          ? Center(
              child: Text(context.tr('library.collectionsEmpty'),
                  style: Theme.of(context).textTheme.bodySmall))
          : ListView(children: [
              for (final c in collections)
                ListTile(
                  key: _tileKeys.putIfAbsent(c.id, GlobalKey.new),
                  dense: true,
                  selected: _dropOn == c.id,
                  selectedTileColor: VoxColors.accent.withValues(alpha: 0.15),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(c.name),
                  subtitle:
                      Text(context.tr('library.count', {'count': c.count})),
                  trailing: IconButton(
                    tooltip: context.tr('library.deleteCollection'),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => library.deleteCollection(c.id),
                  ),
                  onTap: () => setState(() => _open = c.id),
                ),
            ]),
    );
  }
}
