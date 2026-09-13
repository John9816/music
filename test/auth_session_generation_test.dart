import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/auth_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/auth/legacy_auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    ApiClient.instance.bearerToken = null;
    ApiClient.instance.onUnauthorized = null;
  });
  tearDown(() {
    ApiClient.instance.bearerToken = null;
    ApiClient.instance.onUnauthorized = null;
  });

  test('anonymous loads and repeated clears keep the initial generation',
      () async {
    final auth = _auth(_SessionApi());

    await auth.load();
    await auth.load();
    await auth.logout();
    await auth.clearSessionAfterPasswordReset();

    expect(auth.initialized, isTrue);
    expect(auth.isLoggedIn, isFalse);
    expect(auth.sessionGeneration, 0);
  });

  test('each successful login establishes a new generation', () async {
    final auth = _auth(_SessionApi());

    expect(await auth.login('listener', 'test-password'), isTrue);
    expect(auth.sessionGeneration, 1);
    expect(await auth.login('another-listener', 'test-password'), isTrue);
    expect(auth.username, 'another-listener');
    expect(auth.sessionGeneration, 2);
  });

  test('successful registration establishes a new generation', () async {
    final auth = _auth(_SessionApi());

    expect(
      await auth.register(
        'new-listener',
        'new@example.invalid',
        'test-password',
        'test-code',
      ),
      isTrue,
    );
    expect(auth.sessionGeneration, 1);
    await auth.load();
    expect(auth.sessionGeneration, 1);
  });

  test('rejected login preserves the active generation', () async {
    final api = _SessionApi();
    final auth = _auth(api);
    await auth.login('listener', 'test-password');
    final currentToken = auth.token;
    api.loginError = ApiException('登录信息错误', statusCode: 401);

    expect(await auth.login('another-listener', 'wrong-password'), isFalse);

    expect(auth.isLoggedIn, isTrue);
    expect(auth.token, currentToken);
    expect(auth.sessionGeneration, 1);
  });

  test('rejected provisional login never establishes a generation', () async {
    final api = _SessionApi()
      ..loginResponse = {
        'accessToken': 'provisional-test-access',
        'refreshToken': 'provisional-test-refresh',
        'expiresInSeconds': 3600,
      }
      ..profileError = ApiException('会话无效', unauthorized: true)
      ..refreshError = ApiException('刷新被拒绝', unauthorized: true);
    final auth = _auth(api);

    expect(await auth.login('listener', 'test-password'), isFalse);

    expect(auth.isLoggedIn, isFalse);
    expect(auth.sessionGeneration, 0);
  });

  test('rotating credentials keeps the established generation in notifications',
      () async {
    final auth = _auth(_SessionApi());
    await auth.login('listener', 'test-password');
    final previousToken = auth.token;
    final notifications = <int>[];
    auth.addListener(() => notifications.add(auth.sessionGeneration));

    await ApiClient.instance.onUnauthorized!();

    expect(auth.isLoggedIn, isTrue);
    expect(auth.token, isNot(previousToken));
    expect(auth.sessionGeneration, 1);
    expect(notifications, isNotEmpty);
    expect(notifications, everyElement(1));
    await auth.load();
    expect(auth.sessionGeneration, 1);
  });

  test('profile and avatar changes preserve the generation', () async {
    final auth = _auth(_SessionApi());
    await auth.login('listener', 'test-password');

    expect(
      await auth.updateProfile(
        username: 'renamed-listener',
        email: 'renamed@example.invalid',
      ),
      isTrue,
    );
    expect(
      await auth.uploadAvatar(bytes: [1, 2, 3], filename: 'avatar.png'),
      isTrue,
    );

    expect(auth.username, 'renamed-listener');
    expect(auth.email, 'renamed@example.invalid');
    expect(auth.avatarUrl, 'https://example.invalid/new-avatar.png');
    expect(auth.sessionGeneration, 1);
  });

  test('saved session restoration advances once across repeated loads',
      () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'saved-test-access',
      'auth_refresh_token': 'saved-test-refresh',
    });
    final auth = _auth(_SessionApi());

    await auth.load();
    expect(auth.isLoggedIn, isTrue);
    expect(auth.sessionGeneration, 1);
    await auth.load();
    expect(auth.sessionGeneration, 1);
  });

  test('legacy restoration establishes one generation before repeated loads',
      () async {
    final auth = _auth(
      _SessionApi(),
      legacy: _LegacySource(const LegacyAuthSession(
        accessToken: 'legacy-test-access',
        refreshToken: 'legacy-test-refresh',
        expiresAtMs: 4102444800000,
        userId: 'legacy-listener',
      )),
    );

    await auth.load();
    expect(auth.isLoggedIn, isTrue);
    expect(auth.sessionGeneration, 1);
    await auth.load();
    expect(auth.sessionGeneration, 1);
  });

  test('refresh-only restoration establishes a generation once authenticated',
      () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_refresh_token': 'saved-test-refresh',
    });
    final auth = _auth(_SessionApi());

    await auth.load();
    expect(auth.isLoggedIn, isTrue);
    expect(auth.sessionGeneration, 1);
    await auth.load();
    expect(auth.sessionGeneration, 1);
  });

  for (final operation in ['logout', 'password reset', 'rejected refresh']) {
    test('$operation advances once when the established session is cleared',
        () async {
      final api = _SessionApi();
      final auth = _auth(api);
      await auth.login('listener', 'test-password');

      switch (operation) {
        case 'logout':
          await auth.logout();
        case 'password reset':
          await auth.clearSessionAfterPasswordReset();
        case 'rejected refresh':
          api.refreshError = ApiException('刷新被拒绝', statusCode: 403);
          await ApiClient.instance.onUnauthorized!();
      }

      expect(auth.isLoggedIn, isFalse);
      expect(auth.sessionGeneration, 2);
      await auth.logout();
      expect(auth.sessionGeneration, 2);
      expect(await auth.login('listener', 'test-password'), isTrue);
      expect(auth.sessionGeneration, 3);
    });
  }

  test('temporary refresh failure preserves the established generation',
      () async {
    final api = _SessionApi();
    final auth = _auth(api);
    await auth.login('listener', 'test-password');
    api.refreshError = ApiException('暂时无法连接', statusCode: 503);

    await ApiClient.instance.onUnauthorized!();

    expect(auth.isLoggedIn, isTrue);
    expect(auth.sessionGeneration, 1);
  });

  test('loading removed credentials ends the established generation', () async {
    final auth = _auth(_SessionApi());
    await auth.login('listener', 'test-password');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_refresh_token');

    await auth.load();

    expect(auth.isLoggedIn, isFalse);
    expect(auth.sessionGeneration, 2);
    await auth.load();
    expect(auth.sessionGeneration, 2);
  });
}

AuthController _auth(_SessionApi api, {LegacyAuthSessionSource? legacy}) {
  final auth = AuthController(
    api: api,
    legacySessionSource: legacy ?? _LegacySource(null),
  );
  addTearDown(auth.dispose);
  return auth;
}

class _SessionApi extends AuthApi {
  Object? loginError;
  Object? profileError;
  Object? refreshError;
  Map<String, dynamic>? loginResponse;
  int _refreshCount = 0;

  Map<String, dynamic> _session(String username, String email) => {
        'accessToken': 'test-access-$username',
        'refreshToken': 'test-refresh-$username',
        'expiresInSeconds': 3600,
        'username': username,
        'email': email,
        'avatarUrl': 'https://example.invalid/avatar.png',
      };

  @override
  Future<Map<String, dynamic>> login(String account, String password) async {
    if (loginError != null) throw loginError!;
    return loginResponse ?? _session(account, 'listener@example.invalid');
  }

  @override
  Future<Map<String, dynamic>> register(
    String username,
    String email,
    String password,
    String verificationCode,
  ) async =>
      _session(username, email);

  @override
  Future<Map<String, dynamic>> getMe(String token) async {
    if (profileError != null) throw profileError!;
    return {
      'username': 'listener',
      'email': 'listener@example.invalid',
      'avatarUrl': 'https://example.invalid/avatar.png',
    };
  }

  @override
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    if (refreshError != null) throw refreshError!;
    _refreshCount++;
    return {
      'accessToken': 'rotated-test-access-$_refreshCount',
      'refreshToken': 'rotated-test-refresh-$_refreshCount',
      'expiresInSeconds': 3600,
    };
  }

  @override
  Future<Map<String, dynamic>> updateProfile(
    String username,
    String email,
    String token,
  ) async =>
      {'username': username, 'email': email};

  @override
  Future<Map<String, dynamic>> uploadAvatar(
    List<int> bytes,
    String filename,
    String token,
  ) async =>
      {'avatarUrl': 'https://example.invalid/new-avatar.png'};

  @override
  Future<void> logout(String refreshToken, {String? accessToken}) async {}
}

class _LegacySource implements LegacyAuthSessionSource {
  _LegacySource(this.session);

  LegacyAuthSession? session;

  @override
  Future<LegacyAuthSession?> read() async => session;

  @override
  Future<void> clear() async => session = null;
}
