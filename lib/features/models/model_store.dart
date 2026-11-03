// maeknote — 모델 설치 관리 (이어받기 다운로드 · SHA256 검증 · 삭제 · 기본 지정)
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/db.dart';
import '../../core/i18n.dart';
import '../settings/settings_repo.dart';
import 'model_catalog.dart';

class DownloadState {
  DownloadState(this.total);
  final int total;
  int received = 0;

  /// [AppError] 또는 기타 예외
  Object? error;
  bool cancelled = false;

  double get fraction => total == 0 ? 0 : received / total;
}

class ModelDownloadException extends AppError {
  const ModelDownloadException(super.key, [super.args]);
}

class ModelStore extends ChangeNotifier {
  ModelStore({
    required AppDatabase db,
    required this.catalog,
    required this.settings,
    required this.modelsDir,
    required http.Client Function() client,
    required Future<bool> Function() networkAllowed,
  })  : _db = db,
        _client = client,
        _networkAllowed = networkAllowed;

  final AppDatabase _db;
  final ModelCatalog catalog;
  final SettingsRepo settings;
  final String modelsDir;
  final http.Client Function() _client;
  final Future<bool> Function() _networkAllowed;

  /// 진행 중이거나 실패한 다운로드 (id → 상태)
  final downloads = <String, DownloadState>{};

  String dirOf(String id) => p.join(modelsDir, id);

  bool isInstalled(String id) => _db.db
      .select('SELECT 1 FROM installed_models WHERE id = ?', [id]).isNotEmpty;

  List<ModelSpec> installed(ModelKind kind) => [
        for (final r in _db.db.select(
            'SELECT id FROM installed_models WHERE kind = ?', [kind.name]))
          if (catalog.byId(r['id'] as String) case final spec?) spec,
      ];

  /// 파일명 → 로컬 경로
  Map<String, String> filesOf(ModelSpec spec) =>
      {for (final f in spec.files) f.name: p.join(dirOf(spec.id), f.name)};

  String _defaultKey(ModelKind kind) => kind == ModelKind.stt
      ? SettingKeys.defaultSttModel
      : SettingKeys.defaultLlmModel;

  /// 기본 모델: 지정값이 설치돼 있으면 그것, 아니면 설치된 것 중 가장 높은 단계
  ModelSpec? defaultModel(ModelKind kind) {
    final chosen = settings.get(_defaultKey(kind));
    if (chosen.isNotEmpty && isInstalled(chosen)) return catalog.byId(chosen);
    final list = installed(kind)..sort((a, b) => b.tier.compareTo(a.tier));
    return list.firstOrNull;
  }

  void setDefault(ModelSpec spec) {
    settings.set(_defaultKey(spec.kind), spec.id);
    notifyListeners();
  }

  /// 전사 모델은 음성 구간 검출(VAD) 모델을 함께 설치
  Future<void> install(ModelSpec spec) async {
    if (spec.kind == ModelKind.stt && !isInstalled(catalog.vad.id)) {
      await _download(catalog.vad);
    }
    await _download(spec);
  }

  void cancel(String id) => downloads[id]?.cancelled = true;

  Future<void> _download(ModelSpec spec) async {
    if (isInstalled(spec.id)) return;
    final existing = downloads[spec.id];
    if (existing != null && existing.error == null && !existing.cancelled) {
      return; // 이미 진행 중
    }
    final state = DownloadState(spec.sizeBytes);
    downloads[spec.id] = state;
    notifyListeners();
    try {
      if (!await _networkAllowed()) {
        throw const ModelDownloadException('error.wifiOnly');
      }
      await Directory(dirOf(spec.id)).create(recursive: true);
      var done = 0;
      for (final f in spec.files) {
        await _fetchFile(f, p.join(dirOf(spec.id), f.name), state, done);
        done += f.size;
      }
      _db.db.execute(
        'INSERT OR REPLACE INTO installed_models(id, kind, dir, installed_at) VALUES (?, ?, ?, ?)',
        [spec.id, spec.kind.name, dirOf(spec.id), DateTime.now().millisecondsSinceEpoch],
      );
      downloads.remove(spec.id);
    } catch (e) {
      state.error = state.cancelled ? const AppError('error.cancelled') : e;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _fetchFile(
      ModelFile f, String dest, DownloadState state, int before) async {
    final out = File(dest);
    if (await out.exists() && await out.length() == f.size) {
      if (await _sha256(out) == f.sha256) {
        state.received = before + f.size;
        return;
      }
      await out.delete();
    }
    final part = File('$dest.part');
    var offset = await part.exists() ? await part.length() : 0;
    if (offset > f.size) {
      await part.delete();
      offset = 0;
    }
    if (offset < f.size) {
      final req = http.Request('GET', Uri.parse(f.url));
      if (offset > 0) req.headers['Range'] = 'bytes=$offset-';
      final client = _client();
      try {
        final res = await client.send(req);
        if (res.statusCode == 200) {
          offset = 0; // 서버가 이어받기를 지원하지 않음 → 처음부터
        } else if (res.statusCode != 206) {
          throw ModelDownloadException('error.downloadHttp', {'code': res.statusCode});
        }
        final sink = part.openWrite(
            mode: offset == 0 ? FileMode.write : FileMode.append);
        var received = offset;
        var lastNotify = DateTime.now();
        try {
          await for (final chunk in res.stream) {
            if (state.cancelled) throw const ModelDownloadException('error.cancelled');
            sink.add(chunk);
            received += chunk.length;
            state.received = before + received;
            if (DateTime.now().difference(lastNotify) >
                const Duration(milliseconds: 200)) {
              lastNotify = DateTime.now();
              notifyListeners();
            }
          }
        } finally {
          await sink.close();
        }
      } finally {
        client.close();
      }
    }
    if (await part.length() != f.size || await _sha256(part) != f.sha256) {
      await part.delete();
      throw ModelDownloadException('error.hashMismatch', {'file': f.name});
    }
    await part.rename(dest);
  }

  static Future<String> _sha256(File f) async =>
      (await sha256.bind(f.openRead()).first).toString();

  Future<void> delete(ModelSpec spec) async {
    _db.db.execute('DELETE FROM installed_models WHERE id = ?', [spec.id]);
    final dir = Directory(dirOf(spec.id));
    if (await dir.exists()) await dir.delete(recursive: true);
    downloads.remove(spec.id);
    if (settings.get(_defaultKey(spec.kind)) == spec.id) {
      settings.set(_defaultKey(spec.kind), '');
    }
    notifyListeners();
  }
}
