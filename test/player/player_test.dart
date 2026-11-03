import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:maeknote/core/db.dart';
import 'package:maeknote/features/library/library_repo.dart';
import 'package:maeknote/features/player/equalizer.dart';
import 'package:maeknote/features/player/player_service.dart';

import '../support/fakes.dart';

void main() {
  late Directory tmp;
  late AppDatabase db;
  late LibraryRepo library;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('maeknote_test');
    db = AppDatabase.memory();
    library = LibraryRepo(db, mediaDir: p.join(tmp.path, 'media'));
  });

  tearDown(() async {
    db.close();
    await tmp.delete(recursive: true);
  });

  Future<List<MediaItem>> importN(int n) async {
    final src = Directory(p.join(tmp.path, 'src', '해커스'))..createSync(recursive: true);
    final paths = <String>[];
    for (var i = 1; i <= n; i++) {
      final f = File(p.join(src.path, 'day0$i.${i == n ? 'mp4' : 'mp3'}'))
        ..writeAsStringSync('x');
      paths.add(f.path);
    }
    return library.import(paths);
  }

  group('library', () {
    test('import copies files, keeps order, infers kind and source', () async {
      final items = await importN(3);
      expect(items.map((m) => m.title), ['day01', 'day02', 'day03']);
      expect(items.last.kind, 'video');
      expect(items.first.source, '해커스');
      expect(File(items.first.path).existsSync(), isTrue);
      expect(p.isWithin(library.mediaDir, items.first.path), isTrue);
      // 재가져오기는 중복 추가 안 함
      await importN(3);
      expect(library.playlist(), hasLength(3));
    });

    test('drag & drop: folders expand to media files, others ignored', () {
      final d = Directory(p.join(tmp.path, 'drop', 'sub'))..createSync(recursive: true);
      final a = File(p.join(tmp.path, 'drop', 'b.MP3'))..writeAsStringSync('x');
      File(p.join(d.path, 'a.mp4')).writeAsStringSync('x');
      File(p.join(d.path, 'notes.txt')).writeAsStringSync('x');
      final txt = File(p.join(tmp.path, 'readme.txt'))..writeAsStringSync('x');
      final got = mediaPathsFrom([p.join(tmp.path, 'drop'), txt.path]);
      expect(got.map(p.basename), unorderedEquals(['b.MP3', 'a.mp4']));
      expect(mediaPathsFrom([a.path]), [a.path]);
    });

    test('drop onto a collection imports and adds, even if already in playlist', () async {
      final items = await importN(2);
      final c = library.createCollection('토익');
      final src = Directory(p.join(tmp.path, 'src', '해커스'));
      final newFile = File(p.join(src.path, 'day09.mp3'))..writeAsStringSync('x');
      await library.importTo([File(p.join(src.path, 'day01.mp3')).path, newFile.path],
          collectionId: c);
      expect(library.playlist(), hasLength(3));
      expect(library.collectionItems(c).map((m) => m.title), ['day01', 'day09']);
      expect(items.first.title, 'day01');
      // 컬렉션 없이 놓으면 재생목록에만
      await library.importTo([File(p.join(src.path, 'day02.mp4')).path]);
      expect(library.collectionItems(c), hasLength(2));
    });

    test('search filters by title', () async {
      await importN(3);
      expect(library.playlist(query: 'day02').single.title, 'day02');
    });

    test('remove deletes copy; collections track membership', () async {
      final items = await importN(2);
      final c = library.createCollection('강의');
      library.addToCollection(c, items[1].id);
      library.addToCollection(c, items[1].id);
      expect(library.collections().single.count, 1);
      await library.remove(items[1].id);
      expect(File(items[1].path).existsSync(), isFalse);
      expect(library.collectionItems(c), isEmpty);
    });
  });

  group('equalizer', () {
    test('disabled or flat → no filter', () {
      expect(buildEqFilter(enabled: false, gains: eqPresets['More Bass']!), '');
      expect(buildEqFilter(enabled: true, gains: eqPresets['Flat']!), '');
    });

    test('bands map to lavfi equalizer, preamp to volume', () {
      final g = List<double>.filled(11, 0)
        ..[0] = -3
        ..[1] = 6
        ..[10] = -2;
      expect(
        buildEqFilter(enabled: true, gains: g),
        'lavfi=[equalizer=f=32:t=o:w=1:g=6.0,equalizer=f=16000:t=o:w=1:g=-2.0,volume=-3.0dB]',
      );
    });

    test('gains parse/format roundtrip with clamping', () {
      final g = parseGains('1,20,-30,x');
      expect(g, hasLength(11));
      expect(g.sublist(0, 4), [1, 12, -12, 0]);
      expect(parseGains(formatGains(g)), g);
    });
  });

  group('player', () {
    late FakeBackend backend;
    late PlayerService player;
    late List<MediaItem> items;

    setUp(() async {
      items = await importN(3);
      backend = FakeBackend();
      player = PlayerService(backend, library, random: Random(1));
    });

    test('next / previous / completion respect loop modes', () async {
      await player.playItem(items[0], items);
      expect(player.current!.id, items[0].id);
      expect(player.playing, isTrue);

      await player.next();
      expect(player.current!.id, items[1].id);
      await player.previous();
      expect(player.current!.id, items[0].id);

      // 끝 곡 완료: 반복 끔 → 정지 유지, 전체 반복 → 처음으로
      await player.playItem(items[2], items);
      backend.completedC.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(player.current!.id, items[2].id);
      player.cycleRepeat(); // all
      backend.completedC.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(player.current!.id, items[0].id);

      player.cycleRepeat(); // one
      backend.completedC.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(player.current!.id, items[0].id);
    });

    test('shuffle never repeats current track', () async {
      await player.playItem(items[0], items);
      player.toggleShuffle();
      for (var i = 0; i < 10; i++) {
        final before = player.current!.id;
        await player.next();
        expect(player.current!.id, isNot(before));
      }
    });

    test('duration reported by engine is saved to library', () async {
      await player.playItem(items[0], items);
      backend.durationC.add(const Duration(minutes: 9, seconds: 29));
      expect(library.byId(items[0].id)!.durationMs, 569000);
    });

    test('playItem with startAt seeks; volume clamps; device forwarded', () async {
      await player.playItem(items[1], items,
          startAt: const Duration(seconds: 42));
      expect(backend.seeks.last, const Duration(seconds: 42));
      await player.setVolume(150);
      expect(backend.volume, 100);
      await player.setDevice('coreaudio/BlackHole');
      expect(backend.device, 'coreaudio/BlackHole');
    });
  });
}
