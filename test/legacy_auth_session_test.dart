import 'package:duck_music/core/auth/legacy_auth_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses a complete legacy session', () {
    final session = LegacyAuthSession.fromMap(const {
      'accessToken': 'legacy-access',
      'refreshToken': 'legacy-refresh',
      'expiresAtMs': 123456,
      'userId': '42',
    });

    expect(session?.accessToken, 'legacy-access');
    expect(session?.refreshToken, 'legacy-refresh');
    expect(session?.expiresAtMs, 123456);
    expect(session?.userId, '42');
  });

  test('parses a string expiry from the legacy channel', () {
    final session = LegacyAuthSession.fromMap(const {
      'accessToken': 'legacy-access',
      'refreshToken': 'legacy-refresh',
      'expiresAtMs': '987654',
    });

    expect(session?.expiresAtMs, 987654);
  });

  test('rejects a partial legacy session', () {
    expect(
      LegacyAuthSession.fromMap(const {'accessToken': 'legacy-access'}),
      isNull,
    );
    expect(
      LegacyAuthSession.fromMap(const {'refreshToken': 'legacy-refresh'}),
      isNull,
    );
  });

  test('reads and explicitly clears through the legacy channel', () async {
    const channel = MethodChannel('test.duckmusic/legacy-auth');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'readLegacyAuthSession') {
        return <String, Object?>{
          'accessToken': 'legacy-access',
          'refreshToken': 'legacy-refresh',
          'expiresAtMs': 123456,
          'userId': '42',
        };
      }
      if (call.method == 'clearLegacyAuthSession') return null;
      throw MissingPluginException();
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const source = MethodChannelLegacyAuthSessionSource(channel: channel);

    final session = await source.read();

    expect(session?.accessToken, 'legacy-access');
    expect(calls, ['readLegacyAuthSession']);

    await source.clear();

    expect(calls, ['readLegacyAuthSession', 'clearLegacyAuthSession']);
  });

  test('treats a platform read failure as no legacy session', () async {
    const channel = MethodChannel('test.duckmusic/legacy-auth-error');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const source = MethodChannelLegacyAuthSessionSource(channel: channel);

    expect(await source.read(), isNull);
  });
}
