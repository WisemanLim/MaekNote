// maeknote — 모델 목록(manifest) · 기기 사양 · 단계(Tier) 추천
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

enum ModelKind { vad, stt, llm }

class ModelFile {
  const ModelFile(this.name, this.url, this.sha256, this.size);
  final String name;
  final String url;
  final String sha256;
  final int size;
}

class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.kind,
    required this.name,
    required this.tier,
    required this.ramMb,
    required this.license,
    required this.minPerHour,
    required this.files,
  });

  factory ModelSpec.fromJson(Map<String, dynamic> j) => ModelSpec(
        id: j['id'] as String,
        kind: ModelKind.values.byName(j['kind'] as String),
        name: j['name'] as String,
        tier: j['tier'] as int,
        ramMb: j['ramMb'] as int,
        license: j['license'] as String,
        minPerHour: j['minPerHour'] as int,
        files: [
          for (final f in j['files'] as List)
            ModelFile(f['name'] as String, f['url'] as String,
                f['sha256'] as String, f['size'] as int),
        ],
      );

  final String id;
  final ModelKind kind;
  final String name;
  final int tier;

  /// 구동에 필요한 대략적 메모리 (가정값)
  final int ramMb;
  final String license;

  /// 1시간 녹음 처리 예상 시간(분, 표준 기기 기준 가정값)
  final int minPerHour;
  final List<ModelFile> files;

  int get sizeBytes => files.fold(0, (a, f) => a + f.size);
}

class ModelCatalog {
  const ModelCatalog(this.models);

  factory ModelCatalog.parse(String json) {
    final doc = jsonDecode(json) as Map<String, dynamic>;
    return ModelCatalog([
      for (final m in doc['models'] as List)
        ModelSpec.fromJson(m as Map<String, dynamic>),
    ]);
  }

  final List<ModelSpec> models;

  ModelSpec? byId(String id) => models.where((m) => m.id == id).firstOrNull;

  List<ModelSpec> ofKind(ModelKind kind) =>
      models.where((m) => m.kind == kind).toList()
        ..sort((a, b) => a.tier != b.tier
            ? a.tier.compareTo(b.tier)
            : a.ramMb.compareTo(b.ramMb));

  ModelSpec get vad => ofKind(ModelKind.vad).first;

  /// 기기 권장 단계 이하에서 무리 없이 돌아가는 가장 높은 단계 모델
  ModelSpec? recommended(ModelKind kind, DeviceSpec device) {
    final ok = ofKind(kind)
        .where((m) => m.tier <= device.tier && device.fit(m) == Fit.ok)
        .toList();
    if (ok.isEmpty) return ofKind(kind).firstOrNull;
    final top = ok.map((m) => m.tier).reduce((a, b) => a > b ? a : b);
    return ok.firstWhere((m) => m.tier == top);
  }
}

enum Fit { ok, slow, unsupported }

class DeviceSpec {
  const DeviceSpec({required this.ramMb, required this.platform});

  final int ramMb;
  final String platform;

  /// PRD §6 모델 단계: T0 ≤4GB, T1 ≤8GB, T2 ≤16GB, T3 ≤32GB, T4 그 이상
  int get tier => switch (ramMb) {
        <= 4096 => 0,
        <= 8192 => 1,
        <= 16384 => 2,
        <= 32768 => 3,
        _ => 4,
      };

  Fit fit(ModelSpec m) {
    if (m.ramMb > ramMb * 0.75) return Fit.unsupported;
    if (m.ramMb > ramMb * 0.5) return Fit.slow;
    return Fit.ok;
  }
}

Future<DeviceSpec> detectDevice() async {
  final info = DeviceInfoPlugin();
  int mb = 0;
  if (Platform.isAndroid) {
    mb = (await info.androidInfo).physicalRamSize;
  } else if (Platform.isIOS) {
    mb = (await info.iosInfo).physicalRamSize;
  } else if (Platform.isMacOS) {
    mb = (await info.macOsInfo).memorySize ~/ (1024 * 1024);
  } else if (Platform.isWindows) {
    mb = (await info.windowsInfo).systemMemoryInMegabytes;
  } else if (Platform.isLinux) {
    final line = (await File('/proc/meminfo').readAsLines())
        .firstWhere((l) => l.startsWith('MemTotal:'), orElse: () => '');
    mb = (int.tryParse(RegExp(r'\d+').stringMatch(line) ?? '') ?? 0) ~/ 1024;
  }
  // 감지 실패 시 가장 보수적인 단계로
  return DeviceSpec(ramMb: mb > 0 ? mb : 3072, platform: Platform.operatingSystem);
}
