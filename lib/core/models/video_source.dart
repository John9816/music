/// A source exposed by the ECS TVBox provider catalog.
///
/// The app only consumes the normalized capability. It never evaluates the
/// remote `api`, `ext`, `jar`, or `spider` values from a source configuration.
enum VideoSourceCapability {
  cmsHttp,
  tvboxJs,
  drpyJs,
  drpyPy,
  androidDex,
  unsupported,
  unknown;

  static VideoSourceCapability fromJson(Object? value) {
    final normalized = value?.toString().trim().toUpperCase();
    switch (normalized) {
      case 'CMS_HTTP':
        return VideoSourceCapability.cmsHttp;
      case 'TVBOX_JS':
        return VideoSourceCapability.tvboxJs;
      case 'DRPY_JS':
        return VideoSourceCapability.drpyJs;
      case 'DRPY_PY':
        return VideoSourceCapability.drpyPy;
      case 'ANDROID_DEX':
        return VideoSourceCapability.androidDex;
      case 'UNSUPPORTED':
        return VideoSourceCapability.unsupported;
      default:
        return VideoSourceCapability.unknown;
    }
  }

  String get wireValue => switch (this) {
        VideoSourceCapability.cmsHttp => 'CMS_HTTP',
        VideoSourceCapability.tvboxJs => 'TVBOX_JS',
        VideoSourceCapability.drpyJs => 'DRPY_JS',
        VideoSourceCapability.drpyPy => 'DRPY_PY',
        VideoSourceCapability.androidDex => 'ANDROID_DEX',
        VideoSourceCapability.unsupported => 'UNSUPPORTED',
        VideoSourceCapability.unknown => 'UNKNOWN',
      };

  String get label => switch (this) {
        VideoSourceCapability.cmsHttp => 'CMS',
        VideoSourceCapability.tvboxJs => 'TVBox JS',
        VideoSourceCapability.drpyJs => 'dr_py JS',
        VideoSourceCapability.drpyPy => 'dr_py Python',
        VideoSourceCapability.androidDex => 'Android Provider',
        VideoSourceCapability.unsupported => '暂不支持',
        VideoSourceCapability.unknown => '未知能力',
      };

  bool get executable => switch (this) {
        VideoSourceCapability.cmsHttp ||
        VideoSourceCapability.tvboxJs ||
        VideoSourceCapability.drpyJs ||
        VideoSourceCapability.drpyPy => true,
        VideoSourceCapability.androidDex ||
        VideoSourceCapability.unsupported ||
        VideoSourceCapability.unknown => false,
      };
}

class VideoSource {
  const VideoSource({
    required this.id,
    required this.name,
    this.warehouseId,
    this.warehouseName,
    this.siteKey,
    this.capability = VideoSourceCapability.unknown,
    this.enabled = true,
    this.defaultSource = false,
    this.status = '',
    this.reason = '',
    this.sortOrder = 0,
  });

  factory VideoSource.fromJson(Map<String, dynamic> json) {
    final capability = VideoSourceCapability.fromJson(json['capability']);
    final enabled = _boolValue(json['enabled'], fallback: true);
    final reason = _textValue(json['reason']);
    final status = _textValue(json['status']);
    return VideoSource(
      id: _textValue(json['id'] ?? json['sourceId']),
      name: _textValue(json['name'] ?? json['sourceName'] ?? json['title']),
      warehouseId: _stringValue(json['warehouseId']),
      warehouseName: _stringValue(json['warehouseName']),
      siteKey: _stringValue(json['siteKey']),
      capability: capability,
      enabled: enabled,
      defaultSource: _boolValue(json['defaultSource']),
      status: status,
      reason: reason,
      sortOrder: _intValue(json['sortOrder']),
    );
  }

  final String id;
  final String name;
  final String? warehouseId;
  final String? warehouseName;
  final String? siteKey;
  final VideoSourceCapability capability;
  final bool enabled;
  final bool defaultSource;
  final String status;
  final String reason;
  final int sortOrder;

  bool get isExecutable => enabled && capability.executable;

  bool get isUnsupported => !isExecutable;

  String get statusLabel {
    if (!enabled) return '已停用';
    if (status.isNotEmpty && status.toLowerCase() != 'ready') return status;
    if (!capability.executable) return capability.label;
    return '可用';
  }

  String get unavailableMessage {
    if (reason.isNotEmpty) return reason;
    if (!enabled) return '该影视源已停用';
    if (capability == VideoSourceCapability.androidDex) {
      return '该源使用 Android Provider，当前设备无法执行';
    }
    if (!capability.executable) return '该源暂不支持当前播放能力';
    return '';
  }
}

bool _boolValue(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == 'yes' || normalized == '1') {
    return true;
  }
  if (normalized == 'false' || normalized == 'no' || normalized == '0') {
    return false;
  }
  return fallback;
}

int _intValue(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

String? _stringValue(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _textValue(Object? value) => _stringValue(value) ?? '';
