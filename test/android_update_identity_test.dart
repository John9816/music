import 'dart:convert';
import 'package:duck_music/core/services/app_update_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('development package cannot download production as an in-place update',
      () async {
    var requests = 0;
    final service = AppUpdateService(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
        androidIdentityLoader: () async => const AppInstallIdentity(
            packageName: 'com.music.player.debug',
            version: '1.1.54-debug',
            buildNumber: 65,
            production: false));
    final result = await service.checkLatest(target: UpdateTarget.android);
    expect(result.status, UpdateCheckStatus.failed);
    expect(result.message, contains('开发版'));
    expect(requests, 0);
  });
  test('native installed version overrides a stale compile-time display',
      () async {
    final service = AppUpdateService(
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'version': '1.1.55',
              'downloadUrl': 'https://example.com/universal.apk'
            }),
            200)),
        androidIdentityLoader: () async => const AppInstallIdentity(
            packageName: 'com.music.player',
            version: '1.1.56',
            buildNumber: 2067,
            production: true));
    final result = await service.checkLatest(
        target: UpdateTarget.android, currentVersion: '1.1.40');
    expect(result.status, UpdateCheckStatus.upToDate);
  });
  test(
      'installer rejection is preserved for the user instead of generic failure',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('duckmusic/update'),
        (call) async {
      throw PlatformException(code: 'WRONG_PACKAGE', message: '不是当前应用的更新包');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('duckmusic/update'), null));
    final service = AppUpdateService();
    expect(
        await service.installUpdate('/tmp/update.apk',
            target: UpdateTarget.android),
        false);
    expect(service.installError, '不是当前应用的更新包');
  });
}
