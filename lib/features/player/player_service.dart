// maeknote — 재생 상태 관리 (큐 · 반복/셔플 · 볼륨 · EQ · 출력 장치)
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../library/library_repo.dart';

class OutputDevice {
  const OutputDevice(this.name, this.description);
  final String name;
  final String description;

  /// 시스템 기본 장치 ("Same as System")
  bool get isAuto => name == 'auto';
}

/// 실제 재생 엔진 추상화 — 앱은 media_kit, 시험은 가짜 구현.
abstract class AudioBackend {
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<bool> get completed;
  Stream<List<OutputDevice>> get devices;
  Future<void> open(String path, {bool play = true});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> setVolume(double volume); // 0~100
  Future<void> setAudioFilter(String af);
  Future<void> setDevice(String name);
  Future<void> dispose();
}

enum LoopMode { off, all, one }

class PlayerService extends ChangeNotifier {
  PlayerService(this._backend, this._library, {Random? random})
      : _random = random ?? Random() {
    _subs = [
      _backend.position.listen((d) => position.value = d),
      _backend.duration.listen(_onDuration),
      _backend.playing.listen((v) {
        playing = v;
        notifyListeners();
      }),
      _backend.completed.listen((done) {
        if (done) _onCompleted();
      }),
      _backend.devices.listen((d) {
        devices = d;
        notifyListeners();
      }),
    ];
  }

  final AudioBackend _backend;
  final LibraryRepo _library;
  final Random _random;
  late final List<StreamSubscription<Object?>> _subs;

  /// 재생 위치는 자주 바뀌므로 별도 알림
  final position = ValueNotifier<Duration>(Duration.zero);
  Duration duration = Duration.zero;
  bool playing = false;
  double volume = 100;
  bool shuffle = false;
  LoopMode repeat = LoopMode.off;
  List<OutputDevice> devices = const [];
  String device = 'auto';
  List<MediaItem> _queue = const [];
  int _index = -1;

  MediaItem? get current =>
      _index >= 0 && _index < _queue.length ? _queue[_index] : null;

  Future<void> playItem(MediaItem item, List<MediaItem> queue,
      {Duration? startAt, bool autoplay = true}) async {
    _queue = List.unmodifiable(queue);
    _index = _queue.indexWhere((m) => m.id == item.id);
    if (_index < 0) {
      _queue = [..._queue, item];
      _index = _queue.length - 1;
    }
    duration = Duration(milliseconds: item.durationMs);
    position.value = Duration.zero;
    notifyListeners();
    await _backend.open(item.path, play: autoplay);
    if (startAt != null && startAt > Duration.zero) await _backend.seek(startAt);
  }

  Future<void> togglePlay() async {
    if (current == null) return;
    playing ? await _backend.pause() : await _backend.play();
  }

  Future<void> seek(Duration to) async {
    position.value = to;
    await _backend.seek(to);
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    final i = _nextIndex(manual: true);
    if (i != null) await playItem(_queue[i], _queue);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    // 3초 이상 재생했으면 처음으로, 아니면 이전 곡
    if (position.value > const Duration(seconds: 3) || _index == 0) {
      await seek(Duration.zero);
      return;
    }
    await playItem(_queue[_index - 1], _queue);
  }

  int? _nextIndex({required bool manual}) {
    if (!manual && repeat == LoopMode.one) return _index;
    if (shuffle && _queue.length > 1) {
      int i;
      do {
        i = _random.nextInt(_queue.length);
      } while (i == _index);
      return i;
    }
    if (_index + 1 < _queue.length) return _index + 1;
    return repeat == LoopMode.all || manual ? 0 : null;
  }

  Future<void> _onCompleted() async {
    final i = _nextIndex(manual: false);
    if (i != null) await playItem(_queue[i], _queue);
  }

  void _onDuration(Duration d) {
    duration = d;
    final item = current;
    if (item != null && d > Duration.zero) {
      _library.setDuration(item.id, d.inMilliseconds);
    }
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0, 100);
    notifyListeners();
    await _backend.setVolume(volume);
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = LoopMode.values[(repeat.index + 1) % LoopMode.values.length];
    notifyListeners();
  }

  Future<void> setAudioFilter(String af) => _backend.setAudioFilter(af);

  Future<void> setDevice(String name) async {
    device = name;
    notifyListeners();
    await _backend.setDevice(name);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _backend.dispose();
    position.dispose();
    super.dispose();
  }
}
