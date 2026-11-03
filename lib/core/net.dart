// maeknote — 앱의 모든 외부 HTTP 요청이 지나가는 단일 관문 (전송 내역 기록)
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'i18n.dart';

/// 외부 요청 목적. 모델 다운로드 외의 전송은 클라우드 옵션이 켜졌을 때만 허용된다.
enum NetPurpose { modelDownload, cloud }

class NetRecord {
  const NetRecord(this.purpose, this.host, this.at);
  final NetPurpose purpose;
  final String host;
  final DateTime at;
}

/// 전송 기록 (PRD AC6: 클라우드 OFF 시 오디오·텍스트 외부 전송 0건 검증용)
class NetworkLog extends ChangeNotifier {
  final List<NetRecord> records = [];

  void add(NetRecord r) {
    records.add(r);
    notifyListeners();
  }

  Iterable<NetRecord> of(NetPurpose p) => records.where((r) => r.purpose == p);
}

class NetBlockedException extends AppError {
  const NetBlockedException() : super('error.netBlocked');
}

class GuardedClient extends http.BaseClient {
  GuardedClient(this.purpose, this.log, {http.Client? inner, this.allowed})
      : _inner = inner ?? http.Client();

  final NetPurpose purpose;
  final NetworkLog log;
  final http.Client _inner;

  /// 전송 직전 정책 확인 (예: 클라우드 옵션이 꺼졌으면 차단)
  final bool Function()? allowed;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (allowed != null && !allowed!()) throw const NetBlockedException();
    log.add(NetRecord(purpose, request.url.host, DateTime.now()));
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
