import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/window_state.dart';
import 'package:maeknote/features/settings/settings_repo.dart';

void main() {
  test('frame format/parse roundtrip and invalid values', () {
    const r = Rect.fromLTWH(1640, 981, 322, 574);
    expect(parseFrame(formatFrame(r)), r);
    expect(parseFrame(''), isNull);
    expect(parseFrame('1,2,3'), isNull);
    expect(parseFrame('a,b,c,d'), isNull);
    expect(parseFrame('0,0,50,50'), isNull); // 너무 작은 창
    expect(parseFrame('-1800,200,737,574'), const Rect.fromLTWH(-1800, 200, 737, 574));
  });

  test('restore only when the title bar is on some screen', () {
    const main = Rect.fromLTWH(0, 0, 1920, 1080);
    const left = Rect.fromLTWH(-1920, 0, 1920, 1080); // 왼쪽 보조 모니터
    expect(frameVisible(const Rect.fromLTWH(100, 100, 322, 574), [main]), isTrue);
    expect(frameVisible(const Rect.fromLTWH(-1500, 100, 737, 574), [main, left]), isTrue);
    // 보조 모니터를 뺀 뒤
    expect(frameVisible(const Rect.fromLTWH(-1500, 100, 737, 574), [main]), isFalse);
    // 제목줄이 화면 위로 벗어남
    expect(frameVisible(const Rect.fromLTWH(100, -200, 322, 574), [main]), isFalse);
    // 오른쪽 끝에 50px 만 걸침 → 잡을 수 없으므로 복원하지 않음
    expect(frameVisible(const Rect.fromLTWH(1870, 100, 322, 574), [main]), isFalse);
  });

  test('window frame and note panel state are stored as settings', () {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final s = SettingsRepo(db);
    expect(s.get(SettingKeys.windowFrame), '');
    expect(s.getBool(SettingKeys.notePanelOpen), isFalse);
    s.set(SettingKeys.windowFrame, formatFrame(const Rect.fromLTWH(10, 20, 737, 574)));
    s.setBool(SettingKeys.notePanelOpen, true);
    final again = SettingsRepo(db);
    expect(parseFrame(again.get(SettingKeys.windowFrame)), const Rect.fromLTWH(10, 20, 737, 574));
    expect(again.getBool(SettingKeys.notePanelOpen), isTrue);
  });
}
