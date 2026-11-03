import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maeknote/core/theme.dart';
import 'package:maeknote/features/shell/main_screen.dart';
import 'support/i18n.dart';

Widget _shell() => withI18n(MaterialApp(
      theme: buildVoxTheme(),
      home: MainScreen(
        header: const Text('header'),
        controls: (panel, toggle) => Row(children: [
          TextButton(
              onPressed: () => toggle(OverlayPanel.equalizer),
              child: const Text('eq')),
          TextButton(
              onPressed: () => toggle(OverlayPanel.output),
              child: const Text('out')),
        ]),
        transport: const SizedBox.shrink(),
        library: const Text('LIBRARY'),
        note: const Text('NOTE'),
        models: const Text('MODELS'),
        equalizer: const Text('EQ PANEL'),
        output: const Text('OUTPUT PANEL'),
      ),
    ));

void main() {
  desktopTests();
  testWidgets('narrow: icon tabs switch body', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_shell());

    expect(find.text('LIBRARY'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('노트'));
    await tester.pump();
    expect(find.text('NOTE'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('모델'));
    await tester.pump();
    expect(find.text('MODELS'), findsOneWidget);
  });

  testWidgets('control toggles replace body with EQ / output panel',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_shell());

    // 제어줄은 헤더를 누르거나 가리켜야 펼쳐진다
    await tester.tap(find.text('header'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('eq'));
    await tester.pump();
    expect(find.text('EQ PANEL'), findsOneWidget);
    await tester.tap(find.text('out'));
    await tester.pump();
    expect(find.text('OUTPUT PANEL'), findsOneWidget);
    await tester.tap(find.text('out'));
    await tester.pump();
    expect(find.text('LIBRARY'), findsOneWidget);
  });

  testWidgets('controls slide open on header hover and close after leaving',
      (tester) async {
    tester.view.physicalSize = const Size(322, 546);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_shell());
    double revealedHeight() => tester
        .getSize(find.ancestor(of: find.text('eq'), matching: find.byType(ClipRect)).first)
        .height;
    expect(revealedHeight(), 0);
    // 닫혀 있으면 눌러지지 않는다
    expect(find.text('eq').hitTestable(), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(300, 500));
    await mouse.moveTo(tester.getCenter(find.text('header')));
    await tester.pumpAndSettle();
    expect(revealedHeight(), greaterThan(0));
    expect(find.text('eq').hitTestable(), findsOneWidget);

    // 헤더 → 펼친 제어줄로 옮겨도 열린 채
    await mouse.moveTo(tester.getCenter(find.text('eq')));
    await tester.pumpAndSettle();
    expect(find.text('eq').hitTestable(), findsOneWidget);

    await mouse.moveTo(const Offset(300, 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(revealedHeight(), 0);
  });

  testWidgets('controls stay open while the EQ panel is shown', (tester) async {
    tester.view.physicalSize = const Size(322, 546);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_shell());
    await tester.tap(find.text('header'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('eq'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('header')); // 고정 해제
    await tester.pumpAndSettle();
    expect(find.text('eq').hitTestable(), findsOneWidget);
  });

  testWidgets('wide: note panel shown beside player', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_shell());

    expect(find.text('LIBRARY'), findsOneWidget);
    expect(find.text('NOTE'), findsOneWidget);
    expect(find.bySemanticsLabel('노트'), findsNothing);
  });
}

// ---- 데스크톱: 노트를 오른쪽 패널로 펼치기 (Image #8) ----

Widget _desktopShell({required bool open, required VoidCallback onToggle}) =>
    withI18n(MaterialApp(
      theme: buildVoxTheme(),
      home: MainScreen(
        header: const Text('header'),
        controls: (panel, toggle) => const SizedBox.shrink(),
        transport: const SizedBox.shrink(),
        library: const Text('LIBRARY'),
        note: const Text('NOTE'),
        models: const Text('MODELS'),
        equalizer: const Text('EQ PANEL'),
        output: const Text('OUTPUT PANEL'),
        notePanelOpen: open,
        onToggleNotePanel: onToggle,
      ),
    ));

void desktopTests() {
  testWidgets('desktop: closed panel shows player only at VOX width', (tester) async {
    tester.view.physicalSize = const Size(322, 546);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var toggled = 0;
    await tester.pumpWidget(_desktopShell(open: false, onToggle: () => toggled++));
    expect(find.text('LIBRARY'), findsOneWidget);
    expect(find.text('NOTE'), findsNothing);
    await tester.tap(find.bySemanticsLabel('노트'));
    expect(toggled, 1);
  });

  testWidgets('desktop: open panel sits right of a 322px player', (tester) async {
    tester.view.physicalSize = const Size(737, 546);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_desktopShell(open: true, onToggle: () {}));
    expect(find.text('LIBRARY'), findsOneWidget);
    expect(find.text('NOTE'), findsOneWidget);
    expect(tester.getTopLeft(find.text('NOTE')).dx, greaterThan(322));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop: open panel but window too narrow → note in body', (tester) async {
    tester.view.physicalSize = const Size(400, 546);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_desktopShell(open: true, onToggle: () {}));
    expect(find.text('NOTE'), findsOneWidget);
    expect(find.text('LIBRARY'), findsNothing);
  });
}
