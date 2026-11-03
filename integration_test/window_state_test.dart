// 창 위치 기억: 옮기면 저장되고, 저장값으로 복원된다 (실제 macOS 창)
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:maeknote/core/db.dart';
import 'package:maeknote/core/window_state.dart';
import 'package:maeknote/features/settings/settings_repo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('moving the window saves its frame; restore puts it back', (tester) async {
    await tester.runAsync(() async {
      await windowManager.ensureInitialized();
      final db = AppDatabase.memory();
      final settings = SettingsRepo(db);
      final keeper = WindowFrameKeeper(settings)..start();

      await windowManager.setBounds(const Rect.fromLTWH(260, 180, 737, 574));
      await Future<void>.delayed(const Duration(seconds: 1));
      final saved = parseFrame(settings.get(SettingKeys.windowFrame));
      // ignore: avoid_print
      print('SAVED $saved');
      expect(saved, const Rect.fromLTWH(260, 180, 737, 574));

      // 다른 곳으로 옮긴 뒤(=다음 실행의 기본 위치) 저장값으로 복원
      keeper.stop();
      await windowManager.setBounds(const Rect.fromLTWH(600, 300, 322, 574));
      expect(await restoreWindowFrame(settings), isTrue);
      final restored = await windowManager.getBounds();
      // ignore: avoid_print
      print('RESTORED $restored');
      expect(restored, const Rect.fromLTWH(260, 180, 737, 574));

      // 화면 밖 값은 복원하지 않음
      settings.set(SettingKeys.windowFrame, '-9000,-9000,322,574');
      expect(await restoreWindowFrame(settings), isFalse);
      db.close();
    });
  });
}
