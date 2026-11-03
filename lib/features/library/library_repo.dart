// maeknote — 미디어 라이브러리 (재생목록 · 컬렉션)
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/db.dart';

const audioExtensions = ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus'];
const videoExtensions = ['mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v'];

/// 끌어다 놓은 경로에서 재생 가능한 파일만 고른다. 폴더는 하위 폴더까지 펼친다.
List<String> mediaPathsFrom(Iterable<String> paths) {
  bool media(String f) => [...audioExtensions, ...videoExtensions]
      .contains(p.extension(f).replaceFirst('.', '').toLowerCase());
  final out = <String>[];
  for (final path in paths) {
    if (FileSystemEntity.isDirectorySync(path)) {
      final files = Directory(path)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .where(media)
          .toList()
        ..sort();
      out.addAll(files);
    } else if (media(path)) {
      out.add(path);
    }
  }
  return out;
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.path,
    required this.title,
    required this.source,
    required this.kind,
    required this.durationMs,
  });

  final int id;
  final String path;
  final String title;
  final String source;
  final String kind; // audio | video
  final int durationMs;

  bool get isVideo => kind == 'video';
}

class Collection {
  const Collection({required this.id, required this.name, required this.count});
  final int id;
  final String name;
  final int count;
}

class LibraryRepo extends ChangeNotifier {
  LibraryRepo(this._db, {required this.mediaDir});

  final AppDatabase _db;

  /// 가져온 파일의 사본 저장 위치 (샌드박스 앱이 재시작 후에도 읽을 수 있도록)
  final String mediaDir;

  static String kindOf(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return videoExtensions.contains(ext) ? 'video' : 'audio';
  }

  MediaItem _row(Map<String, Object?> r) => MediaItem(
        id: r['id']! as int,
        path: r['path']! as String,
        title: r['title']! as String,
        source: r['source']! as String,
        kind: r['kind']! as String,
        durationMs: r['duration_ms']! as int,
      );

  List<MediaItem> playlist({String query = ''}) {
    final rows = _db.db.select(
      'SELECT * FROM media WHERE title LIKE ? ORDER BY position, id',
      ['%$query%'],
    );
    return rows.map(_row).toList();
  }

  MediaItem? byId(int id) {
    final rows = _db.db.select('SELECT * FROM media WHERE id = ?', [id]);
    return rows.isEmpty ? null : _row(rows.first);
  }

  /// 파일을 mediaDir 로 복사해 재생목록 끝에 추가. 이미 있는 원본 이름은 건너뜀.
  Future<List<MediaItem>> import(List<String> paths) async {
    await Directory(mediaDir).create(recursive: true);
    final added = <MediaItem>[];
    for (final src in paths) {
      final dest = p.join(mediaDir, p.basename(src));
      if (_db.db
          .select('SELECT 1 FROM media WHERE path = ?', [dest]).isNotEmpty) {
        continue;
      }
      if (p.normalize(src) != p.normalize(dest)) {
        await File(src).copy(dest);
      }
      final next = _db.db
          .select('SELECT COALESCE(MAX(position), -1) + 1 AS n FROM media')
          .first['n'] as int;
      _db.db.execute(
        'INSERT INTO media(path, title, source, kind, position, added_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          dest,
          p.basenameWithoutExtension(src),
          p.basename(p.dirname(src)),
          kindOf(src),
          next,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      added.add(byId(_db.db.lastInsertRowId)!);
    }
    if (added.isNotEmpty) notifyListeners();
    return added;
  }

  void setDuration(int id, int durationMs) {
    _db.db.execute(
        'UPDATE media SET duration_ms = ? WHERE id = ? AND duration_ms != ?',
        [durationMs, id, durationMs]);
    if (_db.db.updatedRows > 0) notifyListeners();
  }

  Future<void> remove(int id) async {
    final item = byId(id);
    _db.db.execute('DELETE FROM media WHERE id = ?', [id]);
    if (item != null && p.isWithin(mediaDir, item.path)) {
      final f = File(item.path);
      if (await f.exists()) await f.delete();
    }
    notifyListeners();
  }

  Future<void> clear() async {
    for (final m in playlist()) {
      await remove(m.id);
    }
  }

  // --- 컬렉션 ---

  List<Collection> collections() => _db.db
      .select('SELECT c.id, c.name, COUNT(i.media_id) AS n FROM collections c '
          'LEFT JOIN collection_items i ON i.collection_id = c.id '
          'GROUP BY c.id ORDER BY c.name')
      .map((r) => Collection(
          id: r['id'] as int, name: r['name'] as String, count: r['n'] as int))
      .toList();

  int createCollection(String name) {
    _db.db.execute('INSERT INTO collections(name) VALUES (?)', [name]);
    notifyListeners();
    return _db.db.lastInsertRowId;
  }

  void deleteCollection(int id) {
    _db.db.execute('DELETE FROM collections WHERE id = ?', [id]);
    notifyListeners();
  }

  /// 가져오기 + (지정 시) 컬렉션에 추가. 이미 재생목록에 있던 파일도 컬렉션에는 넣는다.
  Future<void> importTo(List<String> paths, {int? collectionId}) async {
    await import(paths);
    if (collectionId == null) return;
    for (final src in paths) {
      final rows = _db.db.select('SELECT id FROM media WHERE path = ?',
          [p.join(mediaDir, p.basename(src))]);
      if (rows.isNotEmpty) {
        addToCollection(collectionId, rows.first['id'] as int);
      }
    }
  }

  void addToCollection(int collectionId, int mediaId) {
    _db.db.execute(
      'INSERT OR IGNORE INTO collection_items(collection_id, media_id, position) '
      'VALUES (?, ?, (SELECT COALESCE(MAX(position), -1) + 1 FROM collection_items WHERE collection_id = ?))',
      [collectionId, mediaId, collectionId],
    );
    notifyListeners();
  }

  List<MediaItem> collectionItems(int collectionId) => _db.db
      .select(
          'SELECT m.* FROM media m JOIN collection_items i ON i.media_id = m.id '
          'WHERE i.collection_id = ? ORDER BY i.position',
          [collectionId])
      .map(_row)
      .toList();
}
