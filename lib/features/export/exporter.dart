// maeknote — 전사·요약 내보내기 (TXT · Markdown · SRT · VTT)
import '../summary/summarizer.dart';
import '../summary/summary_service.dart';
import '../transcribe/stt_engine.dart';

enum ExportFormat { txt, md, srt, vtt }

String _clock(int ms, {required String sep}) {
  final d = Duration(milliseconds: ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}'
      '$sep${(ms % 1000).toString().padLeft(3, '0')}';
}

String _short(int ms) {
  final d = Duration(milliseconds: ms);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:$s'
      : '${d.inMinutes}:$s';
}

String exportTranscript(
  String title,
  List<Segment> segs,
  ExportFormat format, {
  List<StoredSummary> summaries = const [],
  required String Function(String key) tr,
}) {
  final b = StringBuffer();
  switch (format) {
    case ExportFormat.txt:
      b.writeln(title);
      b.writeln();
      for (final s in segs) {
        b.writeln('[${_short(s.startMs)}] ${s.text}');
      }
    case ExportFormat.md:
      b.writeln('# $title');
      for (final sum in summaries) {
        b.writeln();
        b.writeln('## ${tr(sum.type.labelKey)}');
        for (final sec in sum.sections) {
          b.writeln();
          b.writeln('### ${sec.title}');
          for (final it in sec.items) {
            final t = it.startMs == null ? '' : ' `[${_short(it.startMs!)}]`';
            b.writeln('- ${it.text}$t');
          }
        }
      }
      b.writeln();
      b.writeln('## ${tr('export.transcriptHeading')}');
      b.writeln();
      for (final s in segs) {
        b.writeln('- `[${_short(s.startMs)}]` ${s.text}');
      }
    case ExportFormat.srt:
      for (var i = 0; i < segs.length; i++) {
        b.writeln(i + 1);
        b.writeln('${_clock(segs[i].startMs, sep: ',')} --> ${_clock(segs[i].endMs, sep: ',')}');
        b.writeln(segs[i].text);
        b.writeln();
      }
    case ExportFormat.vtt:
      b.writeln('WEBVTT');
      b.writeln();
      for (final s in segs) {
        b.writeln('${_clock(s.startMs, sep: '.')} --> ${_clock(s.endMs, sep: '.')}');
        b.writeln(s.text);
        b.writeln();
      }
  }
  return b.toString();
}

/// 요약 한 건을 Markdown 으로 (클립보드 복사용) — 제목 · 유형 · 섹션별 항목 + 원문 시간
String exportSummary(String title, StoredSummary summary,
    {required String Function(String key) tr}) {
  final b = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln('## ${tr(summary.type.labelKey)}');
  for (final sec in summary.sections) {
    b
      ..writeln()
      ..writeln('### ${sec.title}');
    for (final it in sec.items) {
      final t = it.startMs == null ? '' : ' `[${_short(it.startMs!)}]`';
      b.writeln('- ${it.text}$t');
    }
  }
  return b.toString();
}
