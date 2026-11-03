// maeknote — 온디바이스 전사 엔진 (sherpa-onnx: Silero VAD 로 구간 분할 → Whisper 인식)
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/i18n.dart';
import 'audio_decoder.dart';

class Segment {
  const Segment(this.startMs, this.endMs, this.text);
  final int startMs;
  final int endMs;
  final String text;
}

class SttModelPaths {
  const SttModelPaths({
    required this.vad,
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });
  final String vad;
  final String encoder;
  final String decoder;
  final String tokens;
}

abstract class SttEngine {
  /// 구간이 인식될 때마다 [onSegment], 처리 비율(0~1)은 [onProgress].
  /// [cancel] 을 완료하면 중단한다.
  Future<void> transcribe(
    Float32List samples, {
    required SttModelPaths model,
    required String language,
    required void Function(Segment) onSegment,
    required void Function(double) onProgress,
    Completer<void>? cancel,
  });
}

class SherpaSttEngine implements SttEngine {
  @override
  Future<void> transcribe(
    Float32List samples, {
    required SttModelPaths model,
    required String language,
    required void Function(Segment) onSegment,
    required void Function(double) onProgress,
    Completer<void>? cancel,
  }) async {
    final port = ReceivePort();
    final errors = ReceivePort();
    final exit = ReceivePort();
    final isolate = await Isolate.spawn(
      _run,
      // 대용량 PCM 은 복사 없이 넘긴다
      (port.sendPort, TransferableTypedData.fromList([samples]), model, language),
      onError: errors.sendPort,
      onExit: exit.sendPort,
    );
    final done = Completer<void>();
    port.listen((msg) {
      if (msg is Segment) onSegment(msg);
      if (msg is double) onProgress(msg);
    });
    errors.listen((e) {
      if (!done.isCompleted) done.completeError(AppError('error.transcribeFailed', {'detail': (e as List).first}));
    });
    exit.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    unawaited(cancel?.future.then((_) {
      isolate.kill(priority: Isolate.immediate);
      if (!done.isCompleted) done.completeError(const AppError('error.cancelled'));
    }));
    try {
      await done.future;
    } finally {
      port.close();
      errors.close();
      exit.close();
    }
  }

  static void _run(
      (SendPort, TransferableTypedData, SttModelPaths, String) args) {
    final (out, data, model, language) = args;
    final samples = data.materialize().asFloat32List();
    sherpa.initBindings();
    final vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: model.vad,
          minSilenceDuration: 0.4,
          minSpeechDuration: 0.25,
          maxSpeechDuration: 20,
        ),
        sampleRate: sttSampleRate,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 60,
    );
    final recognizer = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: model.encoder,
          decoder: model.decoder,
          language: language,
          task: 'transcribe',
        ),
        tokens: model.tokens,
        numThreads: 4,
        debug: false,
      ),
    ));

    void drain() {
      while (!vad.isEmpty()) {
        final seg = vad.front();
        vad.pop();
        final stream = recognizer.createStream();
        stream.acceptWaveform(samples: seg.samples, sampleRate: sttSampleRate);
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text.trim();
        stream.free();
        if (text.isNotEmpty) {
          out.send(Segment(
            seg.start * 1000 ~/ sttSampleRate,
            (seg.start + seg.samples.length) * 1000 ~/ sttSampleRate,
            text,
          ));
        }
      }
    }

    const window = 512;
    for (var i = 0; i + window <= samples.length; i += window) {
      vad.acceptWaveform(Float32List.sublistView(samples, i, i + window));
      if (!vad.isEmpty()) {
        drain();
        out.send(i / samples.length);
      }
    }
    vad.flush();
    drain();
    out.send(1.0);
    recognizer.free();
    vad.free();
  }
}
