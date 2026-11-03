import 'dart:async';

import 'package:maeknote/features/player/player_service.dart';

/// 호출 기록만 남기는 가짜 재생 엔진
class FakeBackend implements AudioBackend {
  final positionC = StreamController<Duration>.broadcast(sync: true);
  final durationC = StreamController<Duration>.broadcast(sync: true);
  final playingC = StreamController<bool>.broadcast(sync: true);
  final completedC = StreamController<bool>.broadcast(sync: true);
  final devicesC = StreamController<List<OutputDevice>>.broadcast(sync: true);

  final opened = <String>[];
  final seeks = <Duration>[];
  String filter = '';
  String device = 'auto';
  double volume = 100;

  @override
  Stream<Duration> get position => positionC.stream;
  @override
  Stream<Duration> get duration => durationC.stream;
  @override
  Stream<bool> get playing => playingC.stream;
  @override
  Stream<bool> get completed => completedC.stream;
  @override
  Stream<List<OutputDevice>> get devices => devicesC.stream;

  @override
  Future<void> open(String path, {bool play = true}) async {
    opened.add(path);
    if (play) playingC.add(true);
  }

  @override
  Future<void> play() async => playingC.add(true);
  @override
  Future<void> pause() async => playingC.add(false);
  @override
  Future<void> seek(Duration to) async => seeks.add(to);
  @override
  Future<void> setVolume(double v) async => volume = v;
  @override
  Future<void> setAudioFilter(String af) async => filter = af;
  @override
  Future<void> setDevice(String name) async => device = name;
  @override
  Future<void> dispose() async {}
}
