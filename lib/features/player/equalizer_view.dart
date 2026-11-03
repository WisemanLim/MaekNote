// maeknote — 이퀄라이저 패널 (Image #2)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../settings/settings_repo.dart';
import 'equalizer.dart';

/// 저장된 EQ 설정을 재생 엔진에 반영
Future<void> applySavedEq(WidgetRef ref) {
  final s = ref.read(settingsProvider);
  return ref.read(playerProvider).setAudioFilter(buildEqFilter(
      enabled: s.getBool(SettingKeys.eqEnabled),
      gains: parseGains(s.get(SettingKeys.eqGains))));
}

class EqualizerView extends ConsumerWidget {
  const EqualizerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final enabled = s.getBool(SettingKeys.eqEnabled);
    final gains = parseGains(s.get(SettingKeys.eqGains));
    final preset = s.get(SettingKeys.eqPreset);

    void save(List<double> g, {String? presetName}) {
      s.set(SettingKeys.eqGains, formatGains(g));
      s.set(SettingKeys.eqPreset, presetName ?? 'Custom');
      applySavedEq(ref);
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          DropdownButton<String>(
            value: eqPresets.containsKey(preset) ? preset : null,
            hint: Text(context.tr('eq.custom')),
            underline: const SizedBox.shrink(),
            items: [
              for (final name in eqPresets.keys)
                DropdownMenuItem(value: name, child: Text(name)),
            ],
            onChanged: (name) {
              if (name != null) save(eqPresets[name]!, presetName: name);
            },
          ),
          const Spacer(),
          Text('EQ', style: Theme.of(context).textTheme.bodySmall),
          Switch(
            value: enabled,
            onChanged: (v) {
              s.setBool(SettingKeys.eqEnabled, v);
              applySavedEq(ref);
            },
          ),
        ]),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 11; i++) ...[
                if (i == 1) const SizedBox(width: 8),
                Expanded(
                  child: _BandSlider(
                    label: i == 0 ? 'PREAMP' : bandLabel(eqBands[i - 1]),
                    value: gains[i],
                    enabled: enabled,
                    onChanged: (v) {
                      final g = [...gains]..[i] = v.roundToDouble();
                      save(g);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: RotatedBox(
          quarterTurns: 3,
          child: Slider(
            value: value,
            min: eqMinDb,
            max: eqMaxDb,
            divisions: 24,
            activeColor: enabled ? VoxColors.accent : VoxColors.muted,
            semanticFormatterCallback: (v) => '$label ${v.round()}dB',
            onChanged: onChanged,
          ),
        ),
      ),
      FittedBox(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    ]);
  }
}
