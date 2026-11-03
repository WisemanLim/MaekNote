// maeknote — VOX 스타일 다크 테마 (오렌지 강조색, VOX 수준의 작은 글씨·촘촘한 행)
import 'package:flutter/material.dart';

class VoxColors {
  static const background = Color(0xFF2B2B2B);
  static const panel = Color(0xFF1F1F1F);
  static const divider = Color(0xFF3A3A3A);
  static const accent = Color(0xFFF28C28);
  static const text = Color(0xFFE6E6E6);
  // #2B2B2B 위 대비 약 5:1 (WCAG AA 4.5:1 충족)
  static const muted = Color(0xFF9A9A9A);
}

/// 설정 > 일반 > 글꼴. (값, 언어셋 키). 글꼴 파일을 넣지 않고 OS 에 있는 글꼴을 순서대로 찾는다.
const fontChoices = [
  ('system', 'settings.font.system'),
  ('sans', 'settings.font.sans'),
  ('serif', 'settings.font.serif'),
  ('mono', 'settings.font.mono'),
];

/// 설정 > 일반 > 글자 크기 (%) — 100 = VOX 수준 기본 크기
const fontSizeChoices = ['85', '100', '115', '130'];

const _fontFamilies = <String, List<String>>{
  'sans': [
    'Helvetica Neue',
    'Segoe UI',
    'Noto Sans',
    'Arial',
    'Apple SD Gothic Neo',
    'Malgun Gothic',
    'Noto Sans CJK KR'
  ],
  'serif': [
    'Times New Roman',
    'Georgia',
    'Noto Serif',
    'AppleMyungjo',
    'Batang',
    'Noto Serif CJK KR'
  ],
  'mono': [
    'Menlo',
    'Consolas',
    'DejaVu Sans Mono',
    'Courier New',
    'D2Coding',
    'Noto Sans Mono CJK KR'
  ],
};

/// 글자 크기 설정값(%) → 배율. 잘못된 값은 1.0
double fontScaleOf(String percent) =>
    (int.tryParse(percent) ?? 100).clamp(70, 160) / 100;

/// [compact]: 데스크톱(마우스)용 촘촘한 간격. 휴대폰·태블릿은 44pt 터치 영역 유지를 위해 false.
ThemeData buildVoxTheme({String font = 'system', bool compact = true}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: VoxColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: VoxColors.accent,
    surface: VoxColors.background,
    onSurface: VoxColors.text,
  );
  final families = _fontFamilies[font];
  const text = VoxColors.text;
  const muted = VoxColors.muted;
  return ThemeData(
    colorScheme: scheme,
    fontFamily: families?.first,
    fontFamilyFallback: families?.skip(1).toList(),
    visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    materialTapTargetSize:
        compact ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded,
    scaffoldBackgroundColor: VoxColors.background,
    dividerColor: VoxColors.divider,
    iconTheme: const IconThemeData(color: text, size: 18),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
          iconSize: 18,
          visualDensity: compact ? VisualDensity.compact : VisualDensity.standard),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: text,
      inactiveTrackColor: VoxColors.divider,
      thumbColor: text,
      trackHeight: 2,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: VoxColors.accent,
      unselectedLabelColor: muted,
      indicatorColor: VoxColors.accent,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 13),
      labelPadding: EdgeInsets.symmetric(horizontal: 12),
    ),
    // VOX 목록: 제목 13, 보조 11, 한 행 약 36px
    listTileTheme: ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity(vertical: compact ? -3 : 0),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      horizontalTitleGap: 8,
      minLeadingWidth: 20,
      minVerticalPadding: 2,
      iconColor: text,
      titleTextStyle: const TextStyle(color: text, fontSize: 13),
      subtitleTextStyle: const TextStyle(color: muted, fontSize: 11),
      leadingAndTrailingTextStyle: const TextStyle(color: muted, fontSize: 11),
    ),
    popupMenuTheme: const PopupMenuThemeData(
        textStyle: TextStyle(color: text, fontSize: 13)),
    dialogTheme: const DialogThemeData(
      backgroundColor: VoxColors.background,
      titleTextStyle:
          TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w600),
      contentTextStyle: TextStyle(color: text, fontSize: 13),
    ),
    inputDecorationTheme: const InputDecorationTheme(isDense: true),
    textTheme: const TextTheme(
      titleLarge:
          TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: text, fontSize: 13),
      titleSmall: TextStyle(color: text, fontSize: 12),
      bodyLarge: TextStyle(color: text, fontSize: 13),
      bodyMedium: TextStyle(color: text, fontSize: 12),
      bodySmall: TextStyle(color: muted, fontSize: 11),
      labelLarge: TextStyle(color: text, fontSize: 12),
      labelMedium: TextStyle(color: text, fontSize: 11),
      labelSmall: TextStyle(color: muted, fontSize: 10),
    ),
  );
}
