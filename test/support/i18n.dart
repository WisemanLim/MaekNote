import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:maeknote/core/i18n.dart';
import 'package:maeknote/features/summary/summarizer.dart';

/// 디스크의 assets/i18n/*.json 을 그대로 읽는다 (시험용)
LanguagePacks loadPacks() => LanguagePacks.fromJson({
      for (final f in Directory('assets/i18n').listSync().whereType<File>())
        if (f.path.endsWith('.json'))
          f.uri.pathSegments.last.replaceAll('.json', ''): f.readAsStringSync(),
    });

/// 기존 시험의 한국어 기대값을 유지하기 위해 기본은 ko
Widget withI18n(Widget child, {String lang = 'ko'}) =>
    I18nScope(i18n: I18n(loadPacks(), lang), child: child);

/// assets/summary/templates.json (시험용)
SummaryTemplates loadTemplates() =>
    SummaryTemplates.parse(File('assets/summary/templates.json').readAsStringSync());
