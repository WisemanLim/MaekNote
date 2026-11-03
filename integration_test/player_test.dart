import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:maeknote/features/player/equalizer.dart';
import 'package:maeknote/features/player/media_kit_backend.dart';

import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('media_kit plays audio + video files with EQ filter applied',
      (tester) async {
    final tmp = (await getTemporaryDirectory()).path;
    final files = await writeFixtures(p.join(tmp, 'it_player'));
    final backend = MediaKitBackend();
    var position = Duration.zero;
    var duration = Duration.zero;
    var devices = 0;
    backend.position.listen((d) => position = d);
    backend.duration.listen((d) => duration = d);
    backend.devices.listen((d) => devices = d.length);

    await backend.setVolume(0);
    await backend.setAudioFilter(buildEqFilter(
        enabled: true, gains: eqPresets['Voice Boost']!));

    for (final path in [files.mp3, files.mp4]) {
      position = Duration.zero;
      await backend.open(path);
      await tester.runAsync(() => waitFor(
          () => position > const Duration(milliseconds: 1500)));
      expect(duration.inSeconds, inInclusiveRange(18, 21), reason: path);
    }
    expect(await backend.currentAudioFilter(), contains('equalizer'));
    expect(devices, greaterThan(0));
    await backend.dispose();
  });
}
