// maeknote — media_kit(libmpv) 재생 엔진
import 'package:media_kit/media_kit.dart';

import 'player_service.dart';

class MediaKitBackend implements AudioBackend {
  MediaKitBackend() : _player = Player() {
    // 영상 파일도 소리만 재생 (화면 출력 없음)
    _native.setProperty('vid', 'no');
  }

  final Player _player;

  NativePlayer get _native => _player.platform! as NativePlayer;

  @override
  Stream<Duration> get position => _player.stream.position;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<bool> get completed => _player.stream.completed;
  @override
  Stream<List<OutputDevice>> get devices => _player.stream.audioDevices.map(
      (list) => [for (final d in list) OutputDevice(d.name, d.description)]);

  @override
  Future<void> open(String path, {bool play = true}) =>
      _player.open(Media(path), play: play);
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration to) => _player.seek(to);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<void> setAudioFilter(String af) => _native.setProperty('af', af);
  /// mpv 가 실제로 받아들인 필터 체인 (잘못된 필터면 빈 값)
  Future<String> currentAudioFilter() => _native.getProperty('af');

  @override
  Future<void> setDevice(String name) async {
    final match = _player.state.audioDevices.where((d) => d.name == name);
    await _player.setAudioDevice(match.isEmpty ? AudioDevice.auto() : match.first);
  }

  @override
  Future<void> dispose() => _player.dispose();
}
