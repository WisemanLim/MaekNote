// maeknote — 데스크톱 창 크기 조절 (노트 패널을 열면 오른쪽으로 넓어짐)
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// VOX 미니 플레이어 창 너비 (제목줄 포함 322×574pt)
const playerWindowWidth = 322.0;

/// 노트 패널을 펼친 창 너비 (참고 화면 Image #8: 플레이어 322 + 노트 415)
const expandedWindowWidth = 737.0;

abstract class WindowSizer {
  Future<Size> size();
  Future<void> setSize(Size size);
}

class DesktopWindowSizer implements WindowSizer {
  @override
  Future<Size> size() => windowManager.getSize();
  @override
  Future<void> setSize(Size size) => windowManager.setSize(size, animate: true);
}

/// 패널을 열면 오른쪽으로 펼치고, 닫으면 플레이어 너비로 되돌린다.
/// 사용자가 이미 더 넓게 만든 창은 줄이지 않고 그대로 둔다(열 때).
Future<void> applyNotePanel(WindowSizer sizer, bool open) async {
  final s = await sizer.size();
  if (open && s.width < expandedWindowWidth) {
    await sizer.setSize(Size(expandedWindowWidth, s.height));
  } else if (!open && s.width > playerWindowWidth) {
    await sizer.setSize(Size(playerWindowWidth, s.height));
  }
}
