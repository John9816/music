import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/auth_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/auth/legacy_auth_session.dart';
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

  test('complete Android legacy session migrates before profile restore',
      () async {
    SharedPreferences.setMockInitialValues(const {});
    final source = _FakeLegacyAuthSessionSource(
      session: const LegacyAuthSession(
        accessToken: 'legacy-access',
        refreshToken: 'legacy-refresh',
        expiresAtMs: 4102444800000,
        userId: '42',
      ),
    );
    final api = _FakeAuthApi(
      onGetMe: (token) async {
        expect(token, 'legacy-access');
        return {'username': '迁移用户'};
      },
    );
    final auth = AuthController(
      api: api,
      legacySessionSource: source,
    );

    await auth.load();

    final prefs = await SharedPreferences.getInstance();
    expect(auth.isLoggedIn, isTrue);
    expect(auth.token, 'legacy-access');
    expect(auth.username, '迁移用户');
    expect(prefs.getString('auth_token'), 'legacy-access');
    expect(prefs.getString('auth_refresh_token'), 'legacy-refresh');
    expect(prefs.getInt('auth_expires_at_ms'), 4102444800000);
    expect(prefs.getString('auth_user_id'), '42');
    expect(source.readCalls, 1);
    expect(source.clearCalls, 1);
  });

  test('existing Flutter credentials take priority over legacy storage',
      () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'flutter-access',
      'auth_refresh_token': 'flutter-refresh',
    });
    final source = _FakeLegacyAuthSessionSource(
      session: const LegacyAuthSession(
        accessToken: 'legacy-access',
        refreshToken: 'legacy-refresh',
      ),
    );
    final auth = AuthController(
      api: _FakeAuthApi(),
      legacySessionSource: source,
    );

    await auth.load();

    expect(auth.token, 'flutter-access');
    expect(source.readCalls, 0);
    expect(source.clearCalls, 0);
  });

  test('legacy source failure leaves first launch initialized and logged out',
      () async {
    SharedPreferences.setMockInitialValues(const {});
    final source = _FakeLegacyAuthSessionSource(
      readError: StateError('legacy storage unavailable'),
    );
    final auth = AuthController(
      api: _FakeAuthApi(),
      legacySessionSource: source,
    );

    await auth.load();

    expect(auth.initialized, isTrue);
    expect(auth.isLoggedIn, isFalse);
    expect(source.readCalls, 1);
    expect(source.clearCalls, 0);
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
    expect(auth.email, isNull);
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

  test('profile and avatar updates replace and persist account details',
      () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'saved-access',
      'auth_username': '旧用户名',
      'auth_email': 'old@751152.xyz',
    });
    final api = _FakeAuthApi(
      onGetMe: (_) async => {
        'username': '旧用户名',
        'email': 'old@751152.xyz',
      },
      onUpdateProfile: (username, email, token) async {
        expect(token, 'saved-access');
        return {
          'username': username,
          'email': email,
        };
      },
      onUploadAvatar: (bytes, filename, token) async {
        expect(bytes, [1, 2, 3]);
        expect(filename, 'avatar.png');
        expect(token, 'saved-access');
        return {'avatarUrl': '/api/v1/user/avatar/2-new.png'};
      },
    );
    final auth = AuthController(api: api);
    await auth.load();

    expect(
      await auth.updateProfile(
        username: '新用户名',
        email: 'new@751152.xyz',
      ),
      isTrue,
    );
    expect(
      await auth.uploadAvatar(bytes: [1, 2, 3], filename: 'avatar.png'),
      isTrue,
    );

    expect(auth.username, '新用户名');
    expect(auth.email, 'new@751152.xyz');
    expect(
      auth.avatarUrl,
      'https://hi.751152.xyz/api/v1/user/avatar/2-new.png',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_username'), '新用户名');
    expect(prefs.getString('auth_email'), 'new@751152.xyz');
    expect(
      prefs.getString('auth_avatar_url'),
      'https://hi.751152.xyz/api/v1/user/avatar/2-new.png',
    );
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

  test('refresh response accepts refresh alias and persists expiry', () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'expired-access',
      'auth_refresh_token': 'old-refresh',
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
      onRefresh: (_) async => {
        'token': 'new-access',
        'refresh': 'new-refresh',
        'expiresInMinutes': 120,
      },
    );
    final auth = AuthController(
      api: api,
      now: () => DateTime.fromMillisecondsSinceEpoch(1000),
    );

    await auth.load();

    final prefs = await SharedPreferences.getInstance();
    expect(auth.token, 'new-access');
    expect(prefs.getString('auth_refresh_token'), 'new-refresh');
    expect(prefs.getInt('auth_expires_at_ms'), 7201000);
  });

  test('login response accepts refresh token value alias', () async {
    SharedPreferences.setMockInitialValues(const {});
    final api = _FakeAuthApi(
      onLogin: (_, __) async => {
        'token': 'login-access',
        'refresh_token_value': 'login-refresh',
        'expires_in': 120,
        'username': '用户',
      },
    );
    final auth = AuthController(
      api: api,
      now: () => DateTime.fromMillisecondsSinceEpoch(1000),
    );

    expect(await auth.login('用户', 'password'), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_refresh_token'), 'login-refresh');
    expect(prefs.getInt('auth_expires_at_ms'), 121000);
  });

  test('near-expiry token refreshes before profile restoration', () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'near-expiry-access',
      'auth_refresh_token': 'valid-refresh',
      'auth_expires_at_ms': 1030000,
    });
    final calls = <String>[];
    final api = _FakeAuthApi(
      onRefresh: (_) async {
        calls.add('refresh');
        return {
          'token': 'new-access',
          'refreshToken': 'new-refresh',
          'expiresInMinutes': 120,
        };
      },
      onGetMe: (token) async {
        calls.add('getMe:$token');
        return {'username': '用户'};
      },
    );
    final auth = AuthController(
      api: api,
      now: () => DateTime.fromMillisecondsSinceEpoch(1000000),
    );

    await auth.load();

    expect(calls, ['refresh', 'getMe:new-access']);
  });

  test('login returns false when profile restoration clears the session',
      () async {
    SharedPreferences.setMockInitialValues(const {});
    final api = _FakeAuthApi(
      onLogin: (_, __) async => {
        'token': 'rejected-access',
        'refreshToken': 'rejected-refresh',
      },
      onGetMe: (_) async => throw ApiException(
        '登录已失效',
        unauthorized: true,
        statusCode: 401,
      ),
      onRefresh: (_) async => throw ApiException(
        'Invalid refresh token',
        unauthorized: true,
        statusCode: 401,
      ),
    );
    final auth = AuthController(api: api);

    final loggedIn = await auth.login('用户', 'password');

    expect(loggedIn, isFalse);
    expect(auth.isLoggedIn, isFalse);
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

  test('rejected refresh token clears the stale local session', () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'expired-access',
      'auth_refresh_token': 'rejected-refresh',
      'auth_username': '过期用户',
    });
    final api = _FakeAuthApi(
      onGetMe: (_) async => throw ApiException(
        '登录已失效',
        unauthorized: true,
        statusCode: 401,
      ),
      onRefresh: (_) async => throw ApiException(
        'Invalid refresh token',
        unauthorized: true,
        statusCode: 401,
      ),
    );
    final auth = AuthController(api: api);

    await auth.load();

    final prefs = await SharedPreferences.getInstance();
    expect(auth.isLoggedIn, isFalse);
    expect(auth.error, '登录已失效，请重新登录');
    expect(prefs.containsKey('auth_token'), isFalse);
    expect(prefs.containsKey('auth_refresh_token'), isFalse);
    expect(prefs.containsKey('auth_username'), isFalse);
  });

  test('forbidden refresh token also clears the stale local session', () async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'expired-access',
      'auth_refresh_token': 'forbidden-refresh',
      'auth_username': '过期用户',
    });
    final api = _FakeAuthApi(
      onGetMe: (_) async => throw ApiException(
        '登录已失效',
        unauthorized: true,
        statusCode: 401,
      ),
      onRefresh: (_) async => throw ApiException(
        'Refresh token is forbidden',
        statusCode: 403,
      ),
    );
    final auth = AuthController(api: api);

    await auth.load();

    final prefs = await SharedPreferences.getInstance();
    expect(auth.isLoggedIn, isFalse);
    expect(auth.error, '登录已失效，请重新登录');
    expect(prefs.containsKey('auth_token'), isFalse);
    expect(prefs.containsKey('auth_refresh_token'), isFalse);
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
    final source = _FakeLegacyAuthSessionSource();
    var sessionCleared = 0;
    final auth = AuthController(
      api: api,
      legacySessionSource: source,
      onSessionCleared: () async => sessionCleared++,
    );
    await auth.load();

    await auth.logout();

    final prefs = await SharedPreferences.getInstance();
    expect(auth.isLoggedIn, isFalse);
    expect(sessionCleared, 1);
    expect(api.logoutCalls, 1);
    expect(api.logoutRefreshToken, 'saved-refresh');
    expect(api.logoutAccessToken, 'saved-access');
    expect(source.clearCalls, 1);
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
  _FakeAuthApi({
    this.onLogin,
    this.onGetMe,
    this.onRefresh,
    this.onUpdateProfile,
    this.onUploadAvatar,
  });

  final Future<Map<String, dynamic>> Function(
    String username,
    String password,
  )? onLogin;
  final Future<Map<String, dynamic>> Function(String token)? onGetMe;
  final Future<Map<String, dynamic>> Function(String refresh)? onRefresh;
  final Future<Map<String, dynamic>> Function(
    String username,
    String email,
    String token,
  )? onUpdateProfile;
  final Future<Map<String, dynamic>> Function(
    List<int> bytes,
    String filename,
    String token,
  )? onUploadAvatar;
  int getMeCalls = 0;
  int logoutCalls = 0;
  String? logoutRefreshToken;
  String? logoutAccessToken;

  @override
  Future<Map<String, dynamic>> login(String username, String password) {
    return onLogin?.call(username, password) ??
        Future.value({
          'token': 'login-access',
          'refreshToken': 'login-refresh',
          'username': username,
        });
  }

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
  Future<void> logout(
    String refreshToken, {
    String? accessToken,
  }) async {
    logoutCalls++;
    logoutRefreshToken = refreshToken;
    logoutAccessToken = accessToken;
  }

  @override
  Future<Map<String, dynamic>> updateProfile(
    String username,
    String email,
    String token,
  ) {
    return onUpdateProfile?.call(username, email, token) ??
        Future.value({
          'username': username,
          'email': email,
        });
  }

  @override
  Future<Map<String, dynamic>> uploadAvatar(
    List<int> bytes,
    String filename,
    String token,
  ) {
    return onUploadAvatar?.call(bytes, filename, token) ?? Future.value({});
  }
}

class _FakeLegacyAuthSessionSource implements LegacyAuthSessionSource {
  _FakeLegacyAuthSessionSource({this.session, this.readError});

  final LegacyAuthSession? session;
  final Object? readError;
  int readCalls = 0;
  int clearCalls = 0;

  @override
  Future<LegacyAuthSession?> read() async {
    readCalls++;
    if (readError != null) throw readError!;
    return session;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
  }
}
