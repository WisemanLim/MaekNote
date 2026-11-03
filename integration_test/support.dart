import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'fixtures.g.dart';

/// 내장 샘플을 앱 임시 폴더에 풀어 경로를 돌려준다.
Future<({String mp3, String mp4})> writeFixtures(String dir) async {
  await Directory(dir).create(recursive: true);
  final mp3 = File(p.join(dir, 'meeting_ko.mp3'));
  final mp4 = File(p.join(dir, 'meeting_ko.mp4'));
  await mp3.writeAsBytes(base64Decode(meetingMp3B64));
  await mp4.writeAsBytes(base64Decode(meetingMp4B64));
  return (mp3: mp3.path, mp4: mp4.path);
}

Future<void> waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw StateError('timeout');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
