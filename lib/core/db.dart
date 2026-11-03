// maeknote — 로컬 SQLite 저장소 (sqlite3 직접 사용, FTS5 전문검색 포함)
import 'package:sqlite3/sqlite3.dart';

/// 스키마 버전별 마이그레이션. 인덱스 i 는 user_version i → i+1.
const _migrations = <List<String>>[
  [
    '''CREATE TABLE media(
      id INTEGER PRIMARY KEY,
      path TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      source TEXT NOT NULL DEFAULT '',
      kind TEXT NOT NULL DEFAULT 'audio',
      duration_ms INTEGER NOT NULL DEFAULT 0,
      position INTEGER NOT NULL DEFAULT 0,
      added_at INTEGER NOT NULL)''',
    '''CREATE TABLE collections(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL UNIQUE)''',
    '''CREATE TABLE collection_items(
      collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
      media_id INTEGER NOT NULL REFERENCES media(id) ON DELETE CASCADE,
      position INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(collection_id, media_id))''',
    '''CREATE TABLE transcripts(
      media_id INTEGER PRIMARY KEY REFERENCES media(id) ON DELETE CASCADE,
      model_id TEXT NOT NULL,
      language TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL,
      progress REAL NOT NULL DEFAULT 0,
      error TEXT,
      updated_at INTEGER NOT NULL)''',
    '''CREATE TABLE segments(
      id INTEGER PRIMARY KEY,
      media_id INTEGER NOT NULL REFERENCES media(id) ON DELETE CASCADE,
      idx INTEGER NOT NULL,
      start_ms INTEGER NOT NULL,
      end_ms INTEGER NOT NULL,
      text TEXT NOT NULL)''',
    'CREATE INDEX segments_media ON segments(media_id, start_ms)',
    '''CREATE VIRTUAL TABLE segments_fts USING fts5(
      text, content='segments', content_rowid='id', tokenize='trigram')''',
    '''CREATE TRIGGER segments_ai AFTER INSERT ON segments BEGIN
      INSERT INTO segments_fts(rowid, text) VALUES (new.id, new.text); END''',
    '''CREATE TRIGGER segments_ad AFTER DELETE ON segments BEGIN
      INSERT INTO segments_fts(segments_fts, rowid, text) VALUES ('delete', old.id, old.text); END''',
    '''CREATE TABLE summaries(
      id INTEGER PRIMARY KEY,
      media_id INTEGER NOT NULL REFERENCES media(id) ON DELETE CASCADE,
      type TEXT NOT NULL,
      model_id TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at INTEGER NOT NULL)''',
    '''CREATE TABLE installed_models(
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      dir TEXT NOT NULL,
      installed_at INTEGER NOT NULL)''',
    '''CREATE TABLE settings(
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL)''',
  ],
];

int get schemaVersion => _migrations.length;

class AppDatabase {
  AppDatabase._(this.db) {
    db.execute('PRAGMA foreign_keys = ON');
    _migrate();
  }

  factory AppDatabase.open(String path) => AppDatabase._(sqlite3.open(path));
  factory AppDatabase.memory() => AppDatabase._(sqlite3.openInMemory());

  final Database db;

  int get version => db.userVersion;

  void _migrate() {
    for (var v = db.userVersion; v < _migrations.length; v++) {
      db.execute('BEGIN');
      try {
        for (final sql in _migrations[v]) {
          db.execute(sql);
        }
        db.userVersion = v + 1;
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  void close() => db.close();
}
