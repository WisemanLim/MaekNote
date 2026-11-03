// maeknote — 요약 생성 · 저장 (엔진 선택: 클라우드 옵션 ON 이면 클라우드, 아니면 온디바이스)
import 'package:flutter/foundation.dart';

import '../../core/db.dart';
import '../../core/i18n.dart';
import '../models/model_catalog.dart';
import '../models/model_store.dart';
import '../settings/settings_repo.dart';
import '../transcribe/transcribe_service.dart';
import '../transcribe/transcript_repo.dart';
import 'summarizer.dart';

class StoredSummary {
  const StoredSummary(this.type, this.modelId, this.sections, this.createdAt);
  final SummaryType type;
  final String modelId;
  final List<SummarySection> sections;
  final DateTime createdAt;
}

class SummaryService extends ChangeNotifier {
  SummaryService({
    required AppDatabase db,
    required this.transcripts,
    required this.models,
    required this.settings,
    required this.templates,
    required this.localEngine,
    required this.cloudEngine,
  }) : _db = db;

  final AppDatabase _db;
  final TranscriptRepo transcripts;
  final ModelStore models;
  final SettingsRepo settings;
  final SummaryTemplates templates;

  /// 설치된 GGUF 모델로 엔진 생성 (모델별 캐시는 호출 측 책임)
  final LlmEngine Function(ModelSpec spec, String path) localEngine;

  /// 클라우드 옵션이 켜지고 설정이 완료됐을 때만 엔진 반환
  final LlmEngine? Function() cloudEngine;

  /// 진행 중 작업: mediaId → (완료, 전체)
  final running = <int, (int, int)>{};

  StoredSummary? latest(int mediaId, SummaryType type) {
    final rows = _db.db.select(
        'SELECT model_id, body, created_at FROM summaries WHERE media_id = ? AND type = ? '
        'ORDER BY id DESC LIMIT 1',
        [mediaId, type.name]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return StoredSummary(type, r['model_id'] as String, decodeSections(r['body'] as String),
        DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int));
  }

  LlmEngine _engine() {
    final cloud = cloudEngine();
    if (cloud != null) return cloud;
    final spec = models.defaultModel(ModelKind.llm);
    if (spec == null) throw ModelMissingException(ModelKind.llm);
    return localEngine(spec, models.filesOf(spec)['model.gguf']!);
  }

  Future<StoredSummary> summarize(int mediaId, SummaryType type) async {
    final segs = transcripts.segments(mediaId);
    if (segs.isEmpty) throw const AppError('error.transcribeFirst');
    final engine = _engine();
    running[mediaId] = (0, 1);
    notifyListeners();
    try {
      final sections = await Summarizer(engine, templates).summarize(
        segs,
        type: type,
        language: settings.get(SettingKeys.summaryLanguage),
        length: settings.get(SettingKeys.summaryLength),
        onProgress: (d, t) {
          running[mediaId] = (d, t);
          notifyListeners();
        },
      );
      if (sections.isEmpty) throw const AppError('error.summaryEmpty');
      _db.db.execute(
        'INSERT INTO summaries(media_id, type, model_id, body, created_at) VALUES (?, ?, ?, ?, ?)',
        [mediaId, type.name, engine.id, encodeSections(sections), DateTime.now().millisecondsSinceEpoch],
      );
      return latest(mediaId, type)!;
    } finally {
      running.remove(mediaId);
      notifyListeners();
    }
  }
}
