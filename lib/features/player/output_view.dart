// maeknote — 출력 장치 선택 (Image #3)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../settings/settings_repo.dart';

class OutputView extends ConsumerWidget {
  const OutputView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    // "Same as System" 을 항상 맨 위에
    final others = player.devices.where((d) => !d.isAuto);
    final entries = [('auto', context.tr('output.system')), for (final d in others) (d.name, d.description)];
    return ListView(children: [
      for (final (name, label) in entries)
        ListTile(
          dense: true,
          selected: player.device == name,
          selectedColor: VoxColors.accent,
          leading: const Icon(Icons.speaker),
          title: Text(label.isEmpty ? name : label),
          onTap: () {
            player.setDevice(name);
            ref.read(settingsProvider).set(SettingKeys.outputDevice, name);
          },
        ),
    ]);
  }
}
