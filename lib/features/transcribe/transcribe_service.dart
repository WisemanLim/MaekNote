// maeknote — 전사 작업 실행 (디코딩 → 전사, 진행률·부분 결과 저장, 취소)
import 'dart:async';

import '../../core/i18n.dart';
import '../library/library_repo.dart';
import '../models/model_catalog.dart';
import '../models/model_store.dart';
import '../settings/settings_repo.dart';
import 'audio_decoder.dart';
import 'stt_engine.dart';
import 'transcript_repo.dart';

class ModelMissingException implements Exception {
  ModelMissingException(this.kind);
  final ModelKind kind;
}

/// 설정 > 전사 > 전사 속도 (%) → 디코딩 tempo. 기본 80%, 허용 50~100%
double sttTempoOf(String percent) => (int.tryParse(percent) ?? 80).clamp(50, 100) / 100;

/// 설정 화면 선택지 (%)
const sttSpeedChoices = ['50', '60', '70', '80', '90', '100'];

class TranscribeService {
  TranscribeService({
    required this.repo,
    required this.models,
    required this.settings,
    required this.library,
    required this.decoder,
    required this.engine,
    required this.tmpDir,
  });

  final TranscriptRepo repo;
  final ModelStore models;
  final SettingsRepo settings;
  final LibraryRepo library;
  final AudioDecoder decoder;
  final SttEngine engine;
  final String tmpDir;

  final _cancels = <int, Completer<void>>{};

  bool isRunning(int mediaId) => _cancels.containsKey(mediaId);

  /// 필요한 모델이 없으면 [ModelMissingException] (호출 측이 권장 모델 안내)
  Future<void> transcribe(MediaItem item) async {
    final spec = models.defaultModel(ModelKind.stt);
    final vad = models.catalog.vad;
    if (spec == null || !models.isInstalled(vad.id)) {
      throw ModelMissingException(ModelKind.stt);
    }
    if (isRunning(item.id)) return;
    final cancel = Completer<void>();
    _cancels[item.id] = cancel;
    final language = settings.get(SettingKeys.sttLanguage);
    final tempo = sttTempoOf(settings.get(SettingKeys.sttSpeed));
    repo.start(item.id, spec.id, language);
    try {
      // 진행률: 디코딩 0~20%, 전사 20~100%
      final samples = await decoder.decode(item.path, tmpDir,
          tempo: tempo,
          onProgress: (v) => repo.update(item.id, TranscriptStatus.decoding, v * 0.2));
      if (cancel.isCompleted) throw const AppError('error.cancelled');
      // 늘린 음성의 시간 × tempo = 원래 시간
      library.setDuration(item.id, (samples.length * 1000 / sttSampleRate * tempo).round());
      repo.update(item.id, TranscriptStatus.transcribing, 0.2);
      final files = models.filesOf(spec);
      await engine.transcribe(
        samples,
        model: SttModelPaths(
          vad: models.filesOf(vad).values.first,
          encoder: files['encoder.onnx']!,
          decoder: files['decoder.onnx']!,
          tokens: files['tokens.txt']!,
        ),
        language: language,
        onSegment: (s) => repo.addSegment(item.id,
            Segment((s.startMs * tempo).round(), (s.endMs * tempo).round(), s.text)),
        onProgress: (v) =>
            repo.update(item.id, TranscriptStatus.transcribing, 0.2 + v * 0.8),
        cancel: cancel,
      );
      repo.update(item.id, TranscriptStatus.done, 1);
    } catch (e) {
      repo.update(item.id, TranscriptStatus.error, 0,
          error: e is AppError ? e.encode() : e is StateError ? e.message : e.toString());
      rethrow;
    } finally {
      _cancels.remove(item.id);
    }
  }

  void cancel(int mediaId) {
    final c = _cancels[mediaId];
    if (c != null && !c.isCompleted) c.complete();
  }
}
