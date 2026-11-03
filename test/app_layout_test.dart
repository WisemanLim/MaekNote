import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maeknote/app.dart';
import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/providers.dart';
import 'package:maeknote/features/cloud/cloud_llm.dart';
import 'package:maeknote/features/models/model_catalog.dart';

import 'support/fakes.dart';
import 'support/i18n.dart';

class _NoSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String? value) async {}
}

void main() {
  // VOX 창(322×574, 제목줄 28 제외) · 휴대폰(360) · 태블릿(768) · 데스크톱 확장 패널(1200)
  for (final size in const [
    Size(322, 546),
    Size(360, 740),
    Size(768, 1024),
    Size(1200, 800),
  ]) {
    testWidgets('home renders without overflow at ${size.width.toInt()}px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appDirProvider.overrideWithValue(Directory.systemTemp.path),
          dbProvider.overrideWithValue(db),
          audioBackendProvider.overrideWithValue(FakeBackend()),
          secretStoreProvider.overrideWithValue(_NoSecrets()),
          catalogProvider.overrideWithValue(
              ModelCatalog.parse(File('assets/models/manifest.json').readAsStringSync())),
          deviceProvider.overrideWithValue(const DeviceSpec(ramMb: 8192, platform: 'x')),
          languagePacksProvider.overrideWithValue(loadPacks()),
        ],
        child: const App(),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 기본 언어 English
      expect(find.text('Import a file to play'), findsOneWidget);
      // 설정 화면도 같은 폭에서 확인
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('General'), findsOneWidget);
    });
  }
}
