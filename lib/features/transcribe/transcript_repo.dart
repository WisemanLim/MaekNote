// maeknote — 전사 상태 · 시간 구간 저장/검색
import 'package:flutter/foundation.dart';

import '../../core/db.dart';
import 'stt_engine.dart';

enum TranscriptStatus { none, decoding, transcribing, done, error }

class TranscriptInfo {
  const TranscriptInfo(this.status, this.progress, this.modelId, this.error);
  final TranscriptStatus status;
  final double progress;
  final String modelId;
  final String? error;

  bool get running =>
      status == TranscriptStatus.decoding || status == TranscriptStatus.transcribing;
}

class StoredSegment extends Segment {
  const StoredSegment(this.id, this.idx, super.startMs, super.endMs, super.text);
  final int id;
  final int idx;
}

class TranscriptRepo extends ChangeNotifier {
  TranscriptRepo(this._db);

  final AppDatabase _db;

  TranscriptInfo info(int mediaId) {
    final rows = _db.db.select(
        'SELECT status, progress, model_id, error FROM transcripts WHERE media_id = ?',
        [mediaId]);
    if (rows.isEmpty) return const TranscriptInfo(TranscriptStatus.none, 0, '', null);
    final r = rows.first;
    return TranscriptInfo(TranscriptStatus.values.byName(r['status'] as String),
        r['progress'] as double, r['model_id'] as String, r['error'] as String?);
  }

  void start(int mediaId, String modelId, String language) {
    _db.db.execute('DELETE FROM segments WHERE media_id = ?', [mediaId]);
    _db.db.execute(
      'INSERT OR REPLACE INTO transcripts(media_id, model_id, language, status, progress, error, updated_at) '
      'VALUES (?, ?, ?, ?, 0, NULL, ?)',
      [mediaId, modelId, language, TranscriptStatus.decoding.name, _now()],
    );
    notifyListeners();
  }

  void update(int mediaId, TranscriptStatus status, double progress, {String? error}) {
    _db.db.execute(
      'UPDATE transcripts SET status = ?, progress = ?, error = ?, updated_at = ? WHERE media_id = ?',
      [status.name, progress, error, _now(), mediaId],
    );
    notifyListeners();
  }

  void addSegment(int mediaId, Segment s) {
    final idx = _db.db
        .select('SELECT COUNT(*) AS n FROM segments WHERE media_id = ?', [mediaId])
        .first['n'] as int;
    _db.db.execute(
      'INSERT INTO segments(media_id, idx, start_ms, end_ms, text) VALUES (?, ?, ?, ?, ?)',
      [mediaId, idx, s.startMs, s.endMs, s.text],
    );
    notifyListeners();
  }

  List<StoredSegment> segments(int mediaId) => _db.db
      .select('SELECT id, idx, start_ms, end_ms, text FROM segments '
          'WHERE media_id = ? ORDER BY start_ms', [mediaId])
      .map((r) => StoredSegment(r['id'] as int, r['idx'] as int,
          r['start_ms'] as int, r['end_ms'] as int, r['text'] as String))
      .toList();

  /// 구간 id 목록. 3글자 이상은 FTS5(trigram), 짧은 검색어는 LIKE.
  Set<int> search(int mediaId, String query) {
    final q = query.trim();
    if (q.isEmpty) return {};
    final rows = q.length >= 3
        ? _db.db.select(
            'SELECT s.id FROM segments_fts f JOIN segments s ON s.id = f.rowid '
            'WHERE segments_fts MATCH ? AND s.media_id = ?',
            ['"${q.replaceAll('"', '""')}"', mediaId])
        : _db.db.select(
            'SELECT id FROM segments WHERE media_id = ? AND text LIKE ?',
            [mediaId, '%$q%']);
    return {for (final r in rows) r['id'] as int};
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}

/// 재생 위치에 해당하는 구간 인덱스 (구간 사이 무음이면 직전 구간). 이진 탐색.
int segmentIndexAt(List<Segment> segs, int positionMs) {
  var lo = 0, hi = segs.length - 1, ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (segs[mid].startMs <= positionMs) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}
