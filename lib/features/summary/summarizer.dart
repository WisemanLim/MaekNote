// maeknote — 요약 유형별 프롬프트 · 구간별 요약 후 통합(map-reduce) · 시간 링크 연결
import 'dart:convert';

import '../transcribe/stt_engine.dart';

enum SummaryType { meeting, lecture, interview, context, brief }

extension SummaryTypeLabel on SummaryType {
  /// 화면 표시 이름의 언어셋 키
  String get labelKey => 'summary.type.$name';
}

/// 생성 엔진 추상화 — 온디바이스(llama.cpp) 또는 클라우드
abstract class LlmEngine {
  String get id;
  Future<String> complete(String system, String user, {int maxTokens = 1024});
}

class SummaryItem {
  const SummaryItem(this.text, this.startMs, this.endMs);
  final String text;
  final int? startMs;
  final int? endMs;

  Map<String, Object?> toJson() => {'text': text, 'startMs': startMs, 'endMs': endMs};
  factory SummaryItem.fromJson(Map<String, dynamic> j) =>
      SummaryItem(j['text'] as String, j['startMs'] as int?, j['endMs'] as int?);
}

class SummarySection {
  const SummarySection(this.title, this.items);
  final String title;
  final List<SummaryItem> items;

  Map<String, Object?> toJson() =>
      {'title': title, 'items': [for (final i in items) i.toJson()]};
  factory SummarySection.fromJson(Map<String, dynamic> j) => SummarySection(
      j['title'] as String,
      [for (final i in j['items'] as List) SummaryItem.fromJson(i as Map<String, dynamic>)]);
}

String encodeSections(List<SummarySection> s) =>
    jsonEncode([for (final x in s) x.toJson()]);

List<SummarySection> decodeSections(String body) => [
      for (final x in jsonDecode(body) as List)
        SummarySection.fromJson(x as Map<String, dynamic>)
    ];

String formatTranscript(List<Segment> segs, {int offset = 0}) => [
      for (var i = 0; i < segs.length; i++) '[S${offset + i}] ${segs[i].text}'
    ].join('\n');

/// 전사본을 문자 수 기준으로 나눈다 (모델 문맥 길이 보호)
List<List<Segment>> chunkSegments(List<Segment> segs, int maxChars) {
  final chunks = <List<Segment>>[];
  var cur = <Segment>[];
  var size = 0;
  for (final s in segs) {
    if (cur.isNotEmpty && size + s.text.length > maxChars) {
      chunks.add(cur);
      cur = [];
      size = 0;
    }
    cur.add(s);
    size += s.text.length + 8;
  }
  if (cur.isNotEmpty) chunks.add(cur);
  return chunks;
}

final _ref = RegExp(r'\[S(\d+)(?:\s*[-~–]\s*S?(\d+))?\]');

/// 모델 출력(## 섹션 / - 항목 [S1-S2]) → 구조화 + 구간 시간 연결.
/// 근거 번호가 없는 항목은 단어가 가장 많이 겹치는 구간으로 연결한다.
List<SummarySection> parseSummary(String output, List<Segment> segs) {
  final sections = <SummarySection>[];
  var title = '요약';
  var items = <SummaryItem>[];
  void flush() {
    if (items.isNotEmpty) sections.add(SummarySection(title, items));
    items = [];
  }

  for (final raw in const LineSplitter().convert(output)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final heading = RegExp(r'^#{1,4}\s*(.+)$').firstMatch(line);
    if (heading != null) {
      flush();
      title = heading.group(1)!.trim();
      continue;
    }
    final bullet = RegExp(r'^(?:[-*•]|\d+[.)])\s*(.+)$').firstMatch(line);
    if (bullet == null) continue;
    var text = bullet.group(1)!;
    int? start, end;
    final refs = _ref.allMatches(text).toList();
    for (final m in refs) {
      final a = int.parse(m.group(1)!);
      final b = m.group(2) == null ? a : int.parse(m.group(2)!);
      if (a < segs.length) {
        final lastIdx = b.clamp(a, segs.length - 1);
        start = start == null ? segs[a].startMs : (segs[a].startMs < start ? segs[a].startMs : start);
        end = end == null ? segs[lastIdx].endMs : (segs[lastIdx].endMs > end ? segs[lastIdx].endMs : end);
      }
    }
    text = text.replaceAll(_ref, '').replaceAll(RegExp(r'\s+'), ' ').trim();
    // 소형 모델이 같은 항목을 반복하는 경우 제거
    if (text.isEmpty || items.any((i) => i.text == text)) continue;
    if (start == null) {
      final best = _bestMatch(text, segs);
      if (best != null) {
        start = best.startMs;
        end = best.endMs;
      }
    }
    items.add(SummaryItem(text, start, end));
  }
  flush();
  return sections;
}

Segment? _bestMatch(String text, List<Segment> segs) {
  // 한국어는 조사가 붙어 단어 단위 비교가 어려우므로 글자 2-gram 겹침으로 비교
  Set<String> grams(String s) {
    final t = s.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '').toLowerCase();
    return {for (var i = 0; i + 1 < t.length; i++) t.substring(i, i + 2)};
  }

  final target = grams(text);
  Segment? best;
  var bestScore = 1; // 2-gram 2개 이상 겹쳐야 연결
  for (final s in segs) {
    final score = grams(s.text).intersection(target).length;
    if (score > bestScore) {
      bestScore = score;
      best = s;
    }
  }
  return best;
}

/// 템플릿 한 부분 (assets/summary/templates.json)
class TemplateSection {
  const TemplateSection(this.id, this.title, this.guide, this.max);
  final String id;
  final Map<String, String> title;
  final Map<String, String> guide;
  final int max;
}

class SummaryTemplate {
  const SummaryTemplate(this.purpose, this.sections);
  final Map<String, String> purpose;
  final List<TemplateSection> sections;
}

/// 요약 유형별 구성 요소와 언어별 프롬프트
class SummaryTemplates {
  const SummaryTemplates(this.templates, this.prompts);

  factory SummaryTemplates.parse(String json) {
    final doc = jsonDecode(json) as Map<String, dynamic>;
    Map<String, String> m(Object? o) =>
        (o as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
    final templates = <SummaryType, SummaryTemplate>{};
    (doc['templates'] as Map<String, dynamic>).forEach((id, t) {
      final type = SummaryType.values.asNameMap()[id];
      if (type == null) return;
      templates[type] = SummaryTemplate(m(t['purpose']), [
        for (final sec in t['sections'] as List)
          TemplateSection(sec['id'] as String, m(sec['title']), m(sec['guide']),
              sec['max'] as int),
      ]);
    });
    return SummaryTemplates(templates, {
      for (final e in (doc['prompts'] as Map<String, dynamic>).entries) e.key: m(e.value),
    });
  }

  final Map<SummaryType, SummaryTemplate> templates;

  /// 언어 → (system, refine, section, none)
  final Map<String, Map<String, String>> prompts;

  /// 출력 언어가 없으면 English
  String lang(String language) => prompts.containsKey(language) ? language : 'en';
}

String _fill(String template, Map<String, Object> values) {
  var s = template;
  values.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// 길이 설정에 따른 섹션별 최대 항목 수
int _maxItems(int base, String length) => switch (length) {
      'short' => (base / 2).ceil(),
      'long' => (base * 1.5).round(),
      _ => base,
    };

class Summarizer {
  Summarizer(this.engine, this.templates, {this.maxChunkChars = 2400});

  final LlmEngine engine;
  final SummaryTemplates templates;
  final int maxChunkChars;

  /// 1) 긴 전사본은 구간별로 정제 노트(오인식 교정·군더더기 제거, [S번호] 유지)를 만든다.
  /// 2) 템플릿의 각 섹션을 따로 작성한다 (작은 모델도 구조를 지키도록 한 번에 한 섹션).
  /// [onProgress] (완료 단계, 전체 단계)
  Future<List<SummarySection>> summarize(
    List<Segment> segs, {
    required SummaryType type,
    String language = 'ko',
    String length = 'medium',
    void Function(int done, int total)? onProgress,
  }) async {
    final lang = templates.lang(language);
    final p = templates.prompts[lang]!;
    final template = templates.templates[type]!;
    final chunks = chunkSegments(segs, maxChunkChars);
    final refine = chunks.length > 1;
    final total = (refine ? chunks.length : 0) + template.sections.length;
    var done = 0;

    String material;
    if (refine) {
      final notes = <String>[];
      var offset = 0;
      for (final c in chunks) {
        notes.add(await engine.complete(
          p['system']!,
          _fill(p['refine']!, {'material': formatTranscript(c, offset: offset)}),
          maxTokens: 768,
        ));
        offset += c.length;
        onProgress?.call(++done, total);
      }
      material = notes.join('\n');
    } else {
      material = formatTranscript(segs);
    }

    final none = p['none']!;
    final result = <SummarySection>[];
    for (final sec in template.sections) {
      final max = _maxItems(sec.max, length);
      final out = await engine.complete(
        p['system']!,
        _fill(p['section']!, {
          'material': material,
          'purpose': template.purpose[lang] ?? template.purpose.values.first,
          'title': sec.title[lang] ?? sec.id,
          'guide': sec.guide[lang] ?? '',
          'max': max,
          'none': none,
        }),
        maxTokens: 160 * max,
      );
      onProgress?.call(++done, total);
      // 소형 모델이 프롬프트·지침·예시를 그대로 베낀 항목은 버린다
      final echo = _norm([
        p['system']!, p['example'] ?? '', template.purpose[lang] ?? '',
        sec.title[lang] ?? '', sec.guide[lang] ?? '',
      ].join(' '));
      final items = [
        for (final s in parseSummary(out, segs)) ...s.items,
      ].where((i) => !_isNone(i.text, none) && !_isEcho(i.text, echo, sec.guide[lang] ?? '')).take(max).toList();
      if (items.isNotEmpty) {
        result.add(SummarySection(sec.title[lang] ?? sec.id, items));
      }
    }
    return result;
  }

  static String _norm(String s) =>
      s.replaceAll(RegExp(r"""[\s.,。·:;!?"'()\-—]"""), '').toLowerCase();

  /// 내용이 없다는 뜻이거나 자리표시 단어뿐인 항목
  static bool _isNone(String text, String none) {
    final t = _norm(text);
    return t.isEmpty ||
        {_norm(none), 'none', 'n/a', 'na', 'tbd', '없음', '미정', '해당없음'}.contains(t);
  }

  /// 프롬프트 문구를 그대로 옮긴 항목: 짧은 항목이 프롬프트의 일부이거나, 항목이 섹션 지침을 통째로 포함
  static bool _isEcho(String text, String promptText, String guide) {
    final t = _norm(text);
    final g = _norm(guide);
    return (t.length >= 2 && t.length <= 40 && promptText.contains(t)) ||
        (g.length >= 10 && t.contains(g));
  }
}
