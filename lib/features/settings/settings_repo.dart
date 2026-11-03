// maeknote — 키/값 설정 저장소 (settings 테이블)
import 'package:flutter/foundation.dart';

import '../../core/db.dart';

/// 설정 키. 기본값은 [SettingsRepo.defaults].
class SettingKeys {
  static const language = 'general.language';
  static const savePosition = 'general.savePosition';
  static const font = 'general.font';
  static const fontSize = 'general.fontSize';
  static const windowFrame = 'window.frame';
  static const notePanelOpen = 'window.notePanel';
  static const lastMediaId = 'general.lastMediaId';
  static const lastPositionMs = 'general.lastPositionMs';
  static const eqEnabled = 'audio.eq.enabled';
  static const eqPreset = 'audio.eq.preset';
  static const eqGains = 'audio.eq.gains';
  static const outputDevice = 'audio.output';
  static const wifiOnlyDownload = 'models.wifiOnly';
  static const defaultSttModel = 'models.defaultStt';
  static const defaultLlmModel = 'models.defaultLlm';
  static const sttLanguage = 'transcribe.language';
  static const sttSpeed = 'transcribe.speed';
  static const summaryType = 'summary.type';
  static const summaryLanguage = 'summary.language';
  static const summaryLength = 'summary.length';
  static const cloudEnabled = 'cloud.enabled';
  static const cloudProvider = 'cloud.provider';
  static const cloudBaseUrl = 'cloud.baseUrl';
  static const cloudModel = 'cloud.model';
}

class SettingsRepo extends ChangeNotifier {
  SettingsRepo(this._db);

  final AppDatabase _db;

  static const defaults = <String, String>{
    SettingKeys.language: 'en',
    SettingKeys.savePosition: 'true',
    SettingKeys.font: 'system',
    SettingKeys.fontSize: '100',
    SettingKeys.windowFrame: '',
    SettingKeys.notePanelOpen: 'false',
    SettingKeys.lastMediaId: '',
    SettingKeys.lastPositionMs: '0',
    SettingKeys.eqEnabled: 'false',
    SettingKeys.eqPreset: 'Flat',
    SettingKeys.eqGains: '0,0,0,0,0,0,0,0,0,0,0',
    SettingKeys.outputDevice: 'auto',
    SettingKeys.wifiOnlyDownload: 'true',
    SettingKeys.defaultSttModel: '',
    SettingKeys.defaultLlmModel: '',
    SettingKeys.sttLanguage: '',
    SettingKeys.sttSpeed: '80',
    SettingKeys.summaryType: 'lecture',
    SettingKeys.summaryLanguage: 'ko',
    SettingKeys.summaryLength: 'medium',
    SettingKeys.cloudEnabled: 'false',
    SettingKeys.cloudProvider: 'openai',
    SettingKeys.cloudBaseUrl: 'https://api.openai.com/v1',
    SettingKeys.cloudModel: '',
  };

  String get(String key) {
    final rows =
        _db.db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? (defaults[key] ?? '') : rows.first['value'] as String;
  }

  bool getBool(String key) => get(key) == 'true';

  void set(String key, String value) {
    _db.db.execute(
      'INSERT INTO settings(key, value) VALUES(?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
    notifyListeners();
  }

  void setBool(String key, bool value) => set(key, value.toString());
}
