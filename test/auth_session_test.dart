import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/auth_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiClient.instance.bearerToken = null;
  });

  test('first launch without a token remains logged out', () async {
    SharedPreferences.setMockInitialValues(const {});
    final api = _FakeAuthApi();
    final auth = AuthController(api: api);

    await auth.load();

    expect(auth.initialized, isTrue);
    expect(auth.isLoggedIn, isFalse);
    expect(api.getMeCalls, 0);
  });

  test('saved token restores the session without another login', () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'saved-access',
      'auth_refresh_token': 'saved-refresh',
      'auth_username': '本地用户',
      'auth_avatar_url': 'https://example.com/local-avatar.jpg',
    });
    final api = _FakeAuthApi(
      onGetMe: (_) async => {
        'username': '云端用户',
        'avatarUrl': '/api/v1/user/avatar/2-test.png',
      },
    );
    final auth = AuthController(api: api);

    await auth.load();

    expect(auth.isLoggedIn, isTrue);
    expect(auth.token, 'saved-access');
    expect(auth.username, '云端用户');
    expect(
      auth.avatarUrl,
      'https://hi.751152.xyz/api/v1/user/avatar/2-test.png',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('auth_avatar_url'),
      'https://hi.751152.xyz/api/v1/user/avatar/2-test.png',
    );
    expect(api.getMeCalls, 1);
  });

  test('expired access token refreshes and remains logged in', () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'expired-access',
      'auth_refresh_token': 'valid-refresh',
      'auth_username': '用户',
    });
    var profileAttempts = 0;
    final api = _FakeAuthApi(
      onGetMe: (_) async {
        profileAttempts++;
        if (profileAttempts == 1) {
          throw ApiException(
            '登录已失效',
            unauthorized: true,
            statusCode: 401,
          );
        }
        return {'username': '用户'};
      },
      onRefresh: (refresh) async {
        expect(refresh, 'valid-refresh');
        return {
          'accessToken': 'new-access',
          'refreshToken': 'new-refresh',
        };
      },
    );
    final auth = AuthController(api: api);

    await auth.load();

    final prefs = await SharedPreferences.getInstance();
    expect(auth.isLoggedIn, isTrue);
    expect(auth.token, 'new-access');
    expect(profileAttempts, 2);
    expect(prefs.getString('auth_token'), 'new-access');
    expect(prefs.getString('auth_refresh_token'), 'new-refresh');
  });

  test('failed validation never removes a saved session', () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'offline-access',
      'auth_refresh_token': 'offline-refresh',
      'auth_username': '离线用户',
      'auth_avatar_url':
          'https://api.751152.xyz/api/v1/user/avatar/2-offline.png',
    });
    final api = _FakeAuthApi(
      onGetMe: (_) async => throw ApiException(
        '登录已失效',
        unauthorized: true,
        statusCode: 401,
      ),
      onRefresh: (_) async => throw ApiException('网络连接失败'),
    );
    final auth = AuthController(api: api);

    await auth.load();

    final prefs = await SharedPreferences.getInstance();
    expect(auth.isLoggedIn, isTrue);
    expect(auth.token, 'offline-access');
    expect(auth.username, '离线用户');
    expect(
      auth.avatarUrl,
      'https://hi.751152.xyz/api/v1/user/avatar/2-offline.png',
    );
    expect(prefs.getString('auth_token'), 'offline-access');
    expect(prefs.getString('auth_refresh_token'), 'offline-refresh');
    expect(
      prefs.getString('auth_avatar_url'),
      'https://hi.751152.xyz/api/v1/user/avatar/2-offline.png',
    );
  });

  test('explicit logout is the only operation that clears credentials',
      () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'saved-access',
      'auth_refresh_token': 'saved-refresh',
      'auth_username': '用户',
      'auth_avatar_url': 'https://example.com/avatar.jpg',
    });
    final api = _FakeAuthApi();
    var sessionCleared = 0;
    final auth = AuthController(
      api: api,
      onSessionCleared: () async => sessionCleared++,
    );
    await auth.load();

    await auth.logout();

    final prefs = await SharedPreferences.getInstance();
    expect(auth.isLoggedIn, isFalse);
    expect(sessionCleared, 1);
    expect(api.logoutCalls, 1);
    expect(prefs.containsKey('auth_token'), isFalse);
    expect(prefs.containsKey('auth_refresh_token'), isFalse);
    expect(prefs.containsKey('auth_username'), isFalse);
    expect(prefs.containsKey('auth_avatar_url'), isFalse);
  });

  test('password reset clears local credentials without calling logout',
      () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'invalidated-access',
      'auth_refresh_token': 'invalidated-refresh',
      'auth_username': '用户',
    });
    final api = _FakeAuthApi();
    final auth = AuthController(api: api);
    await auth.load();

    await auth.clearSessionAfterPasswordReset();

    final prefs = await SharedPreferences.getInstance();
    expect(auth.isLoggedIn, isFalse);
    expect(api.logoutCalls, 0);
    expect(prefs.containsKey('auth_token'), isFalse);
    expect(prefs.containsKey('auth_refresh_token'), isFalse);
    expect(prefs.containsKey('auth_username'), isFalse);
  });
}

class _FakeAuthApi extends AuthApi {
  _FakeAuthApi({this.onGetMe, this.onRefresh});

  final Future<Map<String, dynamic>> Function(String token)? onGetMe;
  final Future<Map<String, dynamic>> Function(String refresh)? onRefresh;
  int getMeCalls = 0;
  int logoutCalls = 0;

  @override
  Future<Map<String, dynamic>> getMe(String token) {
    getMeCalls++;
    return onGetMe?.call(token) ?? Future.value({'username': '用户'});
  }

  @override
  Future<Map<String, dynamic>> refreshToken(String refreshToken) {
    return onRefresh?.call(refreshToken) ??
        Future.value({
          'accessToken': 'refreshed-access',
          'refreshToken': refreshToken,
        });
  }

  @override
  Future<void> logout(String token) async {
    logoutCalls++;
  }
}
