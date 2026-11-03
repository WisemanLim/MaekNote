// maeknote — 클라우드 요약 엔진 (선택 기능, 사용자 API 키). 기본은 꺼짐.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../core/i18n.dart';
import '../summary/summarizer.dart';

enum CloudProvider { openai, anthropic }

const anthropicDefaultModel = 'claude-opus-5-5';
const openaiDefaultBaseUrl = 'https://api.openai.com/v1';

class CloudException extends AppError {
  const CloudException(super.key, [super.args]);
}

/// OpenAI 호환 Chat Completions (OpenAI · 사내 게이트웨이 · 로컬 서버 등)
class OpenAiCompatibleEngine implements LlmEngine {
  OpenAiCompatibleEngine(
      {required this.baseUrl, required this.apiKey, required this.model, required this.client});

  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client client;

  @override
  String get id => 'cloud:openai:$model';

  @override
  Future<String> complete(String system, String user, {int maxTokens = 1024}) async {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final res = await client.post(
      Uri.parse('$base/chat/completions'),
      headers: {'content-type': 'application/json', 'authorization': 'Bearer $apiKey'},
      body: jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
      }),
    );
    if (res.statusCode != 200) {
      throw CloudException('error.cloudHttp', {'code': res.statusCode});
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return ((j['choices'] as List).first['message']['content'] as String?) ?? '';
  }
}

/// Anthropic Messages API (Dart 공식 SDK 가 없어 HTTP 직접 호출)
class AnthropicEngine implements LlmEngine {
  AnthropicEngine({required this.apiKey, required this.model, required this.client});

  final String apiKey;
  final String model;
  final http.Client client;

  /// 안전 분류기 거절 시 서버가 권장 모델로 재시도하는 기능을 지원하는 모델
  static const _fallbackModels = {
    'claude-opus-5-5', 'claude-opus-5', 'claude-fable-5-1', 'claude-sonnet-5-5'
  };

  @override
  String get id => 'cloud:anthropic:$model';

  @override
  Future<String> complete(String system, String user, {int maxTokens = 1024}) async {
    final fallback = _fallbackModels.contains(model);
    final res = await client.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2026-10-21',
        if (fallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'system': system,
        'messages': [
          {'role': 'user', 'content': user},
        ],
        if (fallback) 'fallbacks': 'default',
      }),
    );
    if (res.statusCode != 200) {
      throw CloudException('error.cloudHttp', {'code': res.statusCode});
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (j['stop_reason'] == 'refusal') {
      throw const CloudException('error.cloudRefusal');
    }
    return [
      for (final b in j['content'] as List)
        if (b['type'] == 'text') b['text'] as String
    ].join();
  }
}

/// API 키 저장소 추상화 — 앱은 OS 보안 저장소(Keychain/Keystore/DPAPI/libsecret)
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class OsSecretStore implements SecretStore {
  final _s = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String? value) =>
      value == null || value.isEmpty ? _s.delete(key: key) : _s.write(key: key, value: value);
}

/// 제공자별 API 키를 메모리에 보관 (시작 시 1회 로드)
class CloudKeys extends ChangeNotifier {
  CloudKeys(this._store);
  final SecretStore _store;
  final _keys = <CloudProvider, String>{};

  static String _name(CloudProvider p) => 'cloud.apiKey.${p.name}';

  Future<void> load() async {
    for (final p in CloudProvider.values) {
      try {
        final v = await _store.read(_name(p));
        if (v != null && v.isNotEmpty) _keys[p] = v;
      } catch (_) {
        // 보안 저장소 없음(예: 키링 없는 Linux) → 저장된 키 없이 시작 (온디바이스 기능은 그대로)
        break;
      }
    }
    notifyListeners();
  }

  String? of(CloudProvider p) => _keys[p];

  Future<void> set(CloudProvider p, String? value) async {
    await _store.write(_name(p), value);
    if (value == null || value.isEmpty) {
      _keys.remove(p);
    } else {
      _keys[p] = value;
    }
    notifyListeners();
  }
}
