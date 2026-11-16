import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 设备家族。vivo/iQOO 与 OPPO/一加/realme 各有自己的媒体增强能力，
/// 其余品牌统一走 AOSP 行为。
enum DeviceFamily { vivo, oplus, other }

/// 原生侧只读探测出的设备画像。
class DeviceProfile {
  const DeviceProfile({
    required this.brand,
    required this.manufacturer,
    required this.model,
    required this.family,
    required this.isVivo,
    required this.isOplus,
    this.oplusVersion,
  });

  factory DeviceProfile.fromMap(Map<dynamic, dynamic> map) {
    final family = switch (map['family']) {
      'vivo' => DeviceFamily.vivo,
      'oplus' => DeviceFamily.oplus,
      _ => DeviceFamily.other,
    };
    return DeviceProfile(
      brand: map['brand'] as String? ?? '',
      manufacturer: map['manufacturer'] as String? ?? '',
      model: map['model'] as String? ?? '',
      family: family,
      isVivo: map['isVivo'] as bool? ?? family == DeviceFamily.vivo,
      isOplus: map['isOplus'] as bool? ?? family == DeviceFamily.oplus,
      oplusVersion: map['oplusVersion'] as String?,
    );
  }

  /// 探测失败时的保守值：与改造前的 AOSP 行为完全一致。
  static const fallback = DeviceProfile(
    brand: '',
    manufacturer: '',
    model: '',
    family: DeviceFamily.other,
    isVivo: false,
    isOplus: false,
  );

  /// 这些 ROM 会把持续型媒体通知提升为胶囊 / 实况卡，值得用 ongoing 标记。
  bool get usesOngoingMediaNotification =>
      family == DeviceFamily.vivo || family == DeviceFamily.oplus;
}

/// 对原生 [DeviceProfileBridge] 的薄封装。
///
/// 探测失败一律降级到 [DeviceProfile.fallback]，绝不打断启动流程。
class DeviceProfileService {
  DeviceProfileService({
    MethodChannel? channel,
    Future<Map<dynamic, dynamic>> Function()? probe,
  })  : _channel = channel ?? const MethodChannel('com.music.player/device_profile'),
        _probe = probe ?? _loadFromPlatform;

  static final DeviceProfileService instance = DeviceProfileService();

  final MethodChannel _channel;
  final Future<Map<dynamic, dynamic>> Function() _probe;
  DeviceProfile? _cached;

  Future<DeviceProfile> profile() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final map = await _probe();
      _cached = DeviceProfile.fromMap(map);
    } catch (_) {
      _cached = DeviceProfile.fallback;
    }
    return _cached!;
  }

  Future<void> initialize() async {
    await profile();
  }

  /// 测试用：清掉缓存，让下一次 profile() 重新探测。
  void resetForTesting() => _cached = null;

  Future<Map<dynamic, dynamic>> _loadFromPlatform() async {
    if (kIsWeb) return const <dynamic, dynamic>{};
    try {
      return await _channel.invokeMethod<Map<dynamic, dynamic>>('profile') ??
          const <dynamic, dynamic>{};
    } catch (_) {
      return const <dynamic, dynamic>{};
    }
  }
}
