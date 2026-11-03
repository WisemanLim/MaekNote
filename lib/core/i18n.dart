// maeknote — UI 다국어: 언어셋 JSON(assets/i18n/<code>.json, 앱 데이터 폴더 i18n/<code>.json)
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const defaultLanguage = 'en';
const _assetDir = 'assets/i18n/';

class LanguagePack {
  const LanguagePack(this.code, this.name, this.strings);
  final String code;

  /// 언어 자신의 이름 (JSON 의 "_name")
  final String name;
  final Map<String, String> strings;
}

class LanguagePacks {
  const LanguagePacks(this.packs);

  final Map<String, LanguagePack> packs;

  /// 파일명(확장자 제외)이 언어 코드. 같은 코드가 여러 번 오면 뒤의 것이 키 단위로 덮어쓴다.
  factory LanguagePacks.fromJson(Map<String, String> jsonByCode) {
    final packs = <String, LanguagePack>{};
    jsonByCode.forEach((code, raw) => _merge(packs, code, raw));
    return LanguagePacks(packs);
  }

  static void _merge(Map<String, LanguagePack> packs, String code, String raw) {
    final map = (jsonDecode(raw) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v.toString()));
    final prev = packs[code];
    final strings = {...?prev?.strings, ...map}..remove('_name');
    packs[code] = LanguagePack(code, map['_name'] ?? prev?.name ?? code, strings);
  }

  /// 번들 언어셋 + (선택) 앱 데이터 폴더의 추가 언어셋
  static Future<LanguagePacks> load(AssetBundle bundle, {String? extraDir}) async {
    final packs = <String, LanguagePack>{};
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    for (final path in manifest.listAssets()) {
      if (path.startsWith(_assetDir) && path.endsWith('.json')) {
        _merge(packs, _codeOf(path), await bundle.loadString(path));
      }
    }
    if (extraDir != null && await Directory(extraDir).exists()) {
      await for (final f in Directory(extraDir).list()) {
        if (f is File && f.path.endsWith('.json')) {
          try {
            _merge(packs, _codeOf(f.path), await f.readAsString());
          } on FormatException {
            // 잘못된 사용자 언어셋은 건너뛴다
          }
        }
      }
    }
    return LanguagePacks(packs);
  }

  static String _codeOf(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    return name.substring(0, name.length - '.json'.length);
  }
}

class I18n {
  I18n(this.packs, String code)
      : code = packs.packs.containsKey(code) ? code : defaultLanguage;

  final LanguagePacks packs;
  final String code;

  List<LanguagePack> get available =>
      packs.packs.values.toList()..sort((a, b) => a.code.compareTo(b.code));

  Locale get locale => Locale(code);

  /// 현재 언어 → English → 키 순으로 찾고 {name} 자리표시자를 채운다
  String t(String key, [Map<String, Object?> args = const {}]) {
    var s = packs.packs[code]?.strings[key] ??
        packs.packs[defaultLanguage]?.strings[key] ??
        key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  /// 오류를 화면용 문장으로 ([AppError] 는 번역, 그 외는 원문)
  String error(Object e) => e is AppError ? t(e.key, e.args) : e.toString();
}

/// 사용자에게 보이는 오류: 문장 대신 언어셋 키를 담는다
class AppError implements Exception {
  const AppError(this.key, [this.args = const {}]);
  final String key;
  final Map<String, Object?> args;

  /// DB 등 문자열로 보관할 때
  String encode() => '@${jsonEncode({'k': key, 'a': args})}';

  static Object decode(String stored) {
    if (!stored.startsWith('@')) return stored;
    try {
      final j = jsonDecode(stored.substring(1)) as Map<String, dynamic>;
      return AppError(j['k'] as String, (j['a'] as Map).cast<String, Object?>());
    } on FormatException {
      return stored;
    }
  }

  @override
  String toString() => key;
}

class I18nScope extends InheritedWidget {
  const I18nScope({super.key, required this.i18n, required super.child});
  final I18n i18n;

  static I18n of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<I18nScope>()!.i18n;

  @override
  bool updateShouldNotify(I18nScope old) => old.i18n != i18n;
}

extension I18nContext on BuildContext {
  String tr(String key, [Map<String, Object?> args = const {}]) =>
      I18nScope.of(this).t(key, args);
  String trError(Object e) => I18nScope.of(this).error(e);
}
