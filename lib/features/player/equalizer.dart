// maeknote — 10밴드 EQ (PREAMP + 32Hz~16kHz, ±12dB) → mpv 오디오 필터
const eqBands = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
const eqMinDb = -12.0;
const eqMaxDb = 12.0;

/// 프리셋: [preamp, 32 … 16k] 11개 값
const eqPresets = <String, List<double>>{
  'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'More Bass': [0, 5, 6, 6, 4, 0, 0, 0, 0, 0, 0],
  'Less Bass': [0, -5, -5, -4, -2, 0, 0, 0, 0, 0, 0],
  'More Treble': [0, 0, 0, 0, 0, 0, 1, 3, 5, 6, 6],
  // 음성 명료도: 저역 감쇄 + 1~4kHz 강조
  'Voice Boost': [0, -6, -4, -2, 0, 2, 4, 5, 4, 1, 0],
};

String bandLabel(int hz) => hz >= 1000 ? '${hz ~/ 1000}K' : '$hz';

List<double> parseGains(String csv) {
  final v = csv.split(',').map((s) => double.tryParse(s.trim()) ?? 0).toList();
  return List<double>.generate(11, (i) => i < v.length ? v[i].clamp(eqMinDb, eqMaxDb) : 0);
}

String formatGains(List<double> gains) =>
    gains.map((g) => g.toStringAsFixed(1)).join(',');

/// mpv `af` 속성 값. 비활성 또는 전부 0 이면 빈 문자열(필터 제거).
String buildEqFilter({required bool enabled, required List<double> gains}) {
  if (!enabled || gains.every((g) => g == 0)) return '';
  final parts = <String>[];
  for (var i = 0; i < eqBands.length; i++) {
    final g = gains[i + 1];
    if (g == 0) continue;
    // 옥타브 폭 1 의 피킹 필터
    parts.add('equalizer=f=${eqBands[i]}:t=o:w=1:g=${g.toStringAsFixed(1)}');
  }
  if (gains[0] != 0) parts.add('volume=${gains[0].toStringAsFixed(1)}dB');
  return 'lavfi=[${parts.join(',')}]';
}
