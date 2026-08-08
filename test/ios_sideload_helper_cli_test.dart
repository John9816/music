import '../tool/duckmusic_ios_helper.dart' as helper;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses only non-secret helper command options', () {
    expect(
      helper.parseHelperOptions([
        'install',
        '--json',
        '--ipa',
        '/tmp/DuckMusic.ipa',
        '--bundle-id',
        'com.751152.duckMusic',
        '--version',
        '1.2.0',
        '--build-number',
        '12',
      ]),
      {
        'command': 'install',
        'ipa': '/tmp/DuckMusic.ipa',
        'bundleId': 'com.751152.duckMusic',
        'version': '1.2.0',
        'buildNumber': '12',
      },
    );
  });

  test('builds stable JSON for an available diagnostic helper', () {
    final response = helper.buildStatusResponse(
      platform: 'macOS',
      runtimeAvailable: true,
      runtimeMessage: '已检测到 xcrun devicectl',
      devices: const [
        {
          'name': '测试 iPhone',
          'identifier': 'device-1',
          'connected': true,
          'trusted': true,
          'developerModeEnabled': true,
        },
      ],
    );

    expect(response, {
      'ok': true,
      'platform': 'macOS',
      'helperVersion': '0.1.0',
      'message': '已检测到 xcrun devicectl',
      'devices': [
        {
          'name': '测试 iPhone',
          'identifier': 'device-1',
          'connected': true,
          'trusted': true,
          'developerModeEnabled': true,
        },
      ],
    });
  });

  test('returns an explicit missing-backend response for install and refresh',
      () {
    expect(
      helper.buildUnsupportedResponse('install'),
      {
        'ok': false,
        'code': 'helperMissing',
        'message': '本地签名引擎尚未配置，当前只能执行设备诊断',
      },
    );
    expect(
      helper.buildUnsupportedResponse('refresh'),
      helper.buildUnsupportedResponse('install'),
    );
  });
}
