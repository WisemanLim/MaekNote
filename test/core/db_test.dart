import 'package:flutter_test/flutter_test.dart';

import 'package:maeknote/core/db.dart';
import 'package:maeknote/features/settings/settings_repo.dart';

void main() {
  test('migration reaches latest schema version', () {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    expect(db.version, schemaVersion);
    final tables = db.db
        .select("SELECT name FROM sqlite_master WHERE type IN ('table')")
        .map((r) => r['name'] as String)
        .toSet();
    expect(
        tables,
        containsAll(<String>[
          'media',
          'collections',
          'collection_items',
          'transcripts',
          'segments',
          'segments_fts',
          'summaries',
          'installed_models',
          'settings',
        ]));
  });

  test('FTS5 trigram index follows segment insert/delete', () {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    db.db.execute(
        "INSERT INTO media(id, path, title, added_at) VALUES (1, '/a.mp3', 'a', 0)");
    db.db.execute(
        "INSERT INTO segments(media_id, idx, start_ms, end_ms, text) VALUES (1, 0, 0, 1000, '오늘 회의 안건은 예산입니다')");
    List<Object?> hits() => db.db
        .select("SELECT rowid FROM segments_fts WHERE segments_fts MATCH '예산입'")
        .map((r) => r['rowid'])
        .toList();
    expect(hits(), hasLength(1));
    db.db.execute('DELETE FROM segments');
    expect(hits(), isEmpty);
  });

  test('settings fall back to defaults and persist overrides', () {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final s = SettingsRepo(db);
    expect(s.getBool(SettingKeys.cloudEnabled), isFalse);
    s.setBool(SettingKeys.cloudEnabled, true);
    expect(SettingsRepo(db).getBool(SettingKeys.cloudEnabled), isTrue);
  });
}
