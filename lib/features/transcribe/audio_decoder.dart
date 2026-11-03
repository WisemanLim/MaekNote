// maeknote — 음성·영상 파일 → 16kHz 모노 PCM (libmpv 의 pcm 출력을 이용해 FFmpeg 디코딩 재사용)
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

import '../../core/i18n.dart';

const sttSampleRate = 16000;

abstract class AudioDecoder {
  /// [onProgress] 0~1. [tempo] < 1 이면 음높이는 그대로 두고 느리게 늘린 음성을 돌려준다
  /// (전사 인식률 향상, 결과 시간은 호출 측이 × tempo 로 원래 시간에 맞춘다).
  Future<Float32List> decode(String path, String tmpDir,
      {void Function(double)? onProgress, double tempo = 1});
}

class MpvPcmDecoder implements AudioDecoder {
  @override
  Future<Float32List> decode(String path, String tmpDir,
      {void Function(double)? onProgress, double tempo = 1}) async {
    await Directory(tmpDir).create(recursive: true);
    final wav = File('$tmpDir/decode_${DateTime.now().microsecondsSinceEpoch}.wav');
    final player = Player();
    final native = player.platform! as NativePlayer;
    try {
      for (final (k, v) in [
        ('vid', 'no'),
        ('ao', 'pcm'),
        ('ao-pcm-file', wav.path),
        ('ao-pcm-waveheader', 'yes'),
        ('audio-samplerate', '$sttSampleRate'),
        ('audio-channels', 'mono'),
        ('audio-format', 's16'),
        ('untimed', 'yes'), // 실시간이 아니라 최대 속도로 디코딩
        // 재생 속도를 늦추면 mpv 내장 scaletempo2 가 음높이를 유지한 채 늘린다
        // (media_kit 의 FFmpeg 에는 atempo 필터가 없음)
        if (tempo != 1) ...[
          ('audio-pitch-correction', 'yes'),
          ('speed', tempo.toStringAsFixed(2)),
        ],
      ]) {
        await native.setProperty(k, v);
      }
      var duration = Duration.zero;
      final subs = <StreamSubscription<Object>>[
        player.stream.duration.listen((d) => duration = d),
        player.stream.position.listen((pos) {
          if (duration > Duration.zero) {
            onProgress?.call((pos.inMilliseconds / duration.inMilliseconds).clamp(0, 1));
          }
        }),
      ];
      final done = Completer<void>();
      subs.add(player.stream.completed.listen((c) {
        if (c && !done.isCompleted) done.complete();
      }));
      // mpv 오류 로그는 대부분 치명적이지 않다(예: 깨진 프레임 하나 "Error decoding audio." 후 계속 재생).
      // 파일을 열지 못한 경우(1초가 지나도 길이를 모름)만 실패로 본다.
      Timer? openCheck;
      subs.add(player.stream.error.listen((e) {
        if (done.isCompleted || duration > Duration.zero) return;
        openCheck?.cancel();
        openCheck = Timer(const Duration(seconds: 1), () {
          if (!done.isCompleted && duration == Duration.zero) {
            done.completeError(AppError('error.decodeFailed', {'detail': e}));
          }
        });
      }));
      await player.open(Media(path));
      try {
        await done.future;
      } finally {
        openCheck?.cancel();
      }
      for (final s in subs) {
        await s.cancel();
      }
    } finally {
      await player.dispose(); // ao 종료 시 WAV 파일이 닫힌다
    }
    try {
      return parseWavS16(await wav.readAsBytes());
    } finally {
      if (await wav.exists()) await wav.delete();
    }
  }
}

/// RIFF/WAVE 16bit PCM → [-1, 1] float. data 청크 크기가 비어 있으면 파일 끝까지 읽는다.
Float32List parseWavS16(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('not a WAV file');
  }
  var off = 12;
  while (off + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(off, off + 4));
    var size = bd.getUint32(off + 4, Endian.little);
    final start = off + 8;
    if (id == 'data') {
      if (size == 0 || size == 0xFFFFFFFF || start + size > bytes.length) {
        size = bytes.length - start;
      }
      final n = size ~/ 2;
      final out = Float32List(n);
      for (var i = 0; i < n; i++) {
        out[i] = bd.getInt16(start + i * 2, Endian.little) / 32768.0;
      }
      return out;
    }
    off = start + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('WAV data chunk missing');
}
