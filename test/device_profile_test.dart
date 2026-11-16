import 'package:duck_music/core/services/device_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('识别 vivo / iQOO 家族', () async {
    final service = DeviceProfileService(probe: () async => {
      'brand': 'vivo',
      'manufacturer': 'vivo',
      'model': 'X200',
      'family': 'vivo',
      'isVivo': true,
      'isOplus': false,
    });
    final profile = await service.profile();

    expect(profile.family, DeviceFamily.vivo);
    expect(profile.isVivo, isTrue);
    expect(profile.usesOngoingMediaNotification, isTrue);
  });

  test('识别一加 / OPPO / realme 家族', () async {
    for (final brand in ['OnePlus', 'OPPO', 'realme']) {
      final service = DeviceProfileService(probe: () async => {
        'brand': brand,
        'manufacturer': 'OPPO',
        'family': 'oplus',
        'isVivo': false,
        'isOplus': true,
        'oplusVersion': '15.0',
      });
      final profile = await service.profile();

      expect(profile.family, DeviceFamily.oplus, reason: brand);
      expect(profile.isOplus, isTrue, reason: brand);
      expect(profile.oplusVersion, '15.0');
      expect(profile.usesOngoingMediaNotification, isTrue);
    }
  });

  test('未知家族保持 AOSP 行为', () async {
    final service = DeviceProfileService(probe: () async => {
      'brand': 'samsung',
      'family': 'other',
      'isVivo': false,
      'isOplus': false,
    });
    final profile = await service.profile();

    expect(profile.family, DeviceFamily.other);
    expect(profile.usesOngoingMediaNotification, isFalse);
  });

  test('原生探测失败时降级到保守值且不重复探测', () async {
    var calls = 0;
    final service = DeviceProfileService(probe: () async {
      calls++;
      throw StateError('plugin missing');
    });

    final first = await service.profile();
    final second = await service.profile();

    expect(first, DeviceProfile.fallback);
    expect(second, same(first));
    expect(calls, 1);
  });

  test('缺失 family 字段按 other 处理', () async {
    final service = DeviceProfileService(probe: () async => {'brand': 'unknown'});
    final profile = await service.profile();

    expect(profile.family, DeviceFamily.other);
    expect(profile.usesOngoingMediaNotification, isFalse);
  });
}
