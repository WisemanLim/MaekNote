// maeknote — 데스크톱 창을 마지막으로 닫은 위치·크기에서 다시 연다
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../features/settings/settings_repo.dart';

String formatFrame(Rect r) => [r.left, r.top, r.width, r.height]
    .map((v) => v.round().toString())
    .join(',');

Rect? parseFrame(String s) {
  final v = s.split(',').map(double.tryParse).toList();
  if (v.length != 4 || v.any((x) => x == null)) return null;
  final r = Rect.fromLTWH(v[0]!, v[1]!, v[2]!, v[3]!);
  return r.width >= 200 && r.height >= 200 ? r : null;
}

/// 제목줄 일부(가로 100, 세로 20 이상)가 어느 화면 안에 보여야 복원한다
/// (모니터를 뺀 뒤 창이 화면 밖에 열리는 것을 방지)
bool frameVisible(Rect frame, List<Rect> screens) {
  final titleBar = Rect.fromLTWH(frame.left, frame.top, frame.width, 28);
  return screens.any((s) {
    final i = s.intersect(titleBar);
    return i.width >= 100 && i.height >= 20;
  });
}

/// 시작 시 저장된 창 위치·크기 복원. 복원했으면 true.
Future<bool> restoreWindowFrame(SettingsRepo settings) async {
  final frame = parseFrame(settings.get(SettingKeys.windowFrame));
  if (frame == null) return false;
  final displays = await screenRetriever.getAllDisplays();
  final screens = [
    for (final d in displays)
      (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size),
  ];
  if (!frameVisible(frame, screens)) return false;
  await windowManager.setBounds(frame);
  return true;
}

/// 창을 옮기거나 크기를 바꾸면(멈춘 뒤) 위치·크기를 저장
class WindowFrameKeeper with WindowListener {
  WindowFrameKeeper(this.settings);

  final SettingsRepo settings;
  Timer? _debounce;

  void start() => windowManager.addListener(this);

  void stop() {
    _debounce?.cancel();
    windowManager.removeListener(this);
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), save);
  }

  Future<void> save() async =>
      settings.set(SettingKeys.windowFrame, formatFrame(await windowManager.getBounds()));

  @override
  void onWindowMoved() => _schedule();
  @override
  void onWindowResized() => _schedule();
  @override
  void onWindowMove() => _schedule();
  @override
  void onWindowResize() => _schedule();
}
