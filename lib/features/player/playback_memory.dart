// maeknote — 마지막 재생 파일·위치 기억 (설정: 재생 위치 저장)
import '../library/library_repo.dart';
import '../settings/settings_repo.dart';
import 'player_service.dart';

class PlaybackMemory {
  PlaybackMemory(this.player, this.settings, this.library);

  final PlayerService player;
  final SettingsRepo settings;
  final LibraryRepo library;
  int _lastSavedMs = -1;

  /// 마지막 파일을 일시정지 상태로 열고 위치를 복원한 뒤 저장을 시작
  Future<void> start() async {
    if (settings.getBool(SettingKeys.savePosition)) {
      final id = int.tryParse(settings.get(SettingKeys.lastMediaId));
      final item = id == null ? null : library.byId(id);
      if (item != null) {
        await player.playItem(item, library.playlist(),
            startAt: Duration(
                milliseconds: int.tryParse(settings.get(SettingKeys.lastPositionMs)) ?? 0),
            autoplay: false);
      }
    }
    player.position.addListener(_save);
  }

  void _save() {
    final item = player.current;
    if (item == null || !settings.getBool(SettingKeys.savePosition)) return;
    final ms = player.position.value.inMilliseconds;
    // 5초 단위로만 기록 (DB 쓰기 최소화)
    if ((ms - _lastSavedMs).abs() < 5000 &&
        settings.get(SettingKeys.lastMediaId) == '${item.id}') {
      return;
    }
    _lastSavedMs = ms;
    settings.set(SettingKeys.lastMediaId, '${item.id}');
    settings.set(SettingKeys.lastPositionMs, '$ms');
  }

  void stop() => player.position.removeListener(_save);
}
