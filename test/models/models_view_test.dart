import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/providers.dart';
import 'package:maeknote/core/theme.dart';
import 'package:maeknote/features/models/model_catalog.dart';
import 'package:maeknote/features/models/models_view.dart';
import '../support/i18n.dart';

void main() {
  final catalog =
      ModelCatalog.parse(File('assets/models/manifest.json').readAsStringSync());

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDirProvider.overrideWithValue(Directory.systemTemp.path),
        dbProvider.overrideWithValue(db),
        catalogProvider.overrideWithValue(catalog),
        deviceProvider.overrideWithValue(
            const DeviceSpec(ramMb: 6144, platform: 'android')),
      ],
      child: withI18n(MaterialApp(theme: buildVoxTheme(), home: Scaffold(body: child))),
    ));
  }

  testWidgets('lists models with recommendation and unsupported warning',
      (tester) async {
    await pump(tester, const ModelsView());
    expect(find.textContaining('권장 T1'), findsOneWidget);
    expect(find.text('Whisper small (int8)'), findsOneWidget);
    expect(find.text('권장'), findsOneWidget);
    expect(find.text('이 기기에서 실행 불가'), findsWidgets);
  });

  testWidgets('AC5: unsupported model asks confirmation before download',
      (tester) async {
    await pump(tester, const ModelsView());
    await tester.tap(find.text('요약(LLM)'));
    await tester.pumpAndSettle();
    final tile = find.ancestor(
        of: find.text('Qwen2.5 14B Instruct (Q4_K_M)'),
        matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: tile, matching: find.byTooltip('다운로드')));
    await tester.pumpAndSettle();
    expect(find.textContaining('이 기기에서 실행 불가: 필요 메모리'), findsOneWidget);
    expect(find.text('그래도 다운로드'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
  });

  testWidgets('AC4: missing model sheet shows recommended model, size, time',
      (tester) async {
    await pump(
      tester,
      Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () => showModelRequired(context, ref, ModelKind.stt),
          child: const Text('go'),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('전사(STT) 모델이 필요합니다'), findsOneWidget);
    expect(find.text('권장: Whisper small (int8)'), findsOneWidget);
    expect(find.textContaining('1시간 녹음 처리 약 20분'), findsOneWidget);
    expect(find.text('권장 모델 다운로드'), findsOneWidget);
  });
}
