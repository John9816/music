import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/auth_api.dart';
import '../api/api_client.dart';
import '../config/app_config.dart';
import 'legacy_auth_session.dart';

/// 登录状态管理 + token 持久化（对应 macOS 版 AuthService + ViewModel）。
class AuthController extends ChangeNotifier {
  static const _tokenKey = 'auth_token';
  static const _refreshKey = 'auth_refresh_token';
  static const _usernameKey = 'auth_username';
  static const _emailKey = 'auth_email';
  static const _avatarUrlKey = 'auth_avatar_url';
  static const _expiresAtMsKey = 'auth_expires_at_ms';
  static const _userIdKey = 'auth_user_id';
  static const _expirySafetyWindowMs = 60000;

  AuthController({
    AuthApi? api,
    LegacyAuthSessionSource? legacySessionSource,
    DateTime Function()? now,
    this.onSessionCleared,
  })  : _api = api ?? AuthApi(),
        _legacySessionSource =
            legacySessionSource ?? const MethodChannelLegacyAuthSessionSource(),
        _now = now ?? DateTime.now {
    ApiClient.instance.onUnauthorized = _handleUnauthorized;
  }

  final AuthApi _api;
  final LegacyAuthSessionSource _legacySessionSource;
  final DateTime Function() _now;
  final Future<void> Function()? onSessionCleared;

  String? _token;
  String? _refresh;
  String? _username;
  String? _email;
  String? _avatarUrl;
  int? _expiresAtMs;
  String? _userId;
  bool _loading = false;
  bool _initialized = false;
  String? _error;
  Future<bool>? _refreshFuture;
  bool _refreshRejected = false;
  bool _restoring = false;

  String? get token => _token;
  String? get username => _username;
  String? get email => _email;
  String? get avatarUrl => _avatarUrl;
  bool get isLoggedIn => _token != null;
  bool get loading => _loading;
  bool get initialized => _initialized;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _restoring = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = _normalizedString(prefs.getString(_tokenKey));
      _refresh = _normalizedString(prefs.getString(_refreshKey));
      _expiresAtMs = prefs.getInt(_expiresAtMsKey);
      _userId = prefs.getString(_userIdKey);
      _username = prefs.getString(_usernameKey);
      _email = prefs.getString(_emailKey);
      final storedAvatarUrl = prefs.getString(_avatarUrlKey);
      _avatarUrl = _normalizeAvatarUrl(storedAvatarUrl);
      if (_avatarUrl != storedAvatarUrl) {
        await _writeOrRemove(prefs, _avatarUrlKey, _avatarUrl);
      }
      if (_token == null && _refresh == null) {
        await _migrateLegacySession(prefs);
      }
      ApiClient.instance.bearerToken = _token;

      if (_token == null && _refresh != null) {
        final refreshed = await _refreshSession();
        if (!refreshed && _refreshRejected) {
          await _clearSession(error: '登录已失效，请重新登录');
        }
      } else if (_token != null && _hasRefreshToken && _accessTokenNearExpiry) {
        final refreshed = await _refreshSession();
        if (!refreshed && _refreshRejected) {
          await _clearSession(error: '登录已失效，请重新登录');
        }
      }
      if (_token != null) {
        await _restoreProfile();
      }
    } finally {
      _restoring = false;
      _loading = false;
      _initialized = true;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final d = await _api.login(username, password);
      final accessToken = _pickAny(
        d,
        const ['accessToken', 'access_token', 'token'],
      );
      if (accessToken == null) throw Exception('登录响应缺少 accessToken');
      _token = accessToken;
      _refresh = _pickRefreshToken(d);
      _expiresAtMs = _resolveExpiresAtMs(d, accessToken);
      _applyProfile(d, clearMissing: true);
      _username ??= username;
      ApiClient.instance.bearerToken = _token;
      await _persist();
      if (_email == null || _avatarUrl == null) await _restoreProfile();
      if (_token == null) return false;
      await _persist();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> register(String username, String email, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final d = await _api.register(username, email, password);
      final accessToken = _pickAny(
        d,
        const ['accessToken', 'access_token', 'token'],
      );
      if (accessToken == null) throw Exception('注册响应缺少 accessToken');
      _token = accessToken;
      _refresh = _pickRefreshToken(d);
      _expiresAtMs = _resolveExpiresAtMs(d, accessToken);
      _applyProfile(d, clearMissing: true);
      _username ??= username;
      _email ??= email;
      ApiClient.instance.bearerToken = _token;
      await _persist();
      if (_avatarUrl == null) await _restoreProfile();
      if (_token == null) return false;
      await _persist();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final accessToken = _token;
    final refreshToken = _refresh;
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _api.logout(refreshToken, accessToken: accessToken);
      }
    } catch (_) {
    } finally {
      await _clearSession();
    }
  }

  /// 密码重置后服务端会使所有令牌失效，此处只清理本地会话。
  Future<void> clearSessionAfterPasswordReset() => _clearSession();

  Future<bool> updateProfile({
    required String username,
    required String email,
  }) async {
    final token = _token;
    if (token == null) {
      _error = '请先登录';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.updateProfile(username, email, token);
      _applyProfile(data);
      await _persist();
      return true;
    } catch (error) {
      _error = error is ApiException ? error.message : error.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> uploadAvatar({
    required List<int> bytes,
    required String filename,
  }) async {
    final token = _token;
    if (token == null) {
      _error = '请先登录';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.uploadAvatar(bytes, filename, token);
      _applyProfile(data);
      await _persist();
      return true;
    } catch (error) {
      _error = error is ApiException ? error.message : error.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _handleUnauthorized() async {
    if (_restoring || _token == null) return;
    final refreshed = await _refreshSession();
    if (!refreshed) {
      if (_refreshRejected || !_hasRefreshToken) {
        await _clearSession(error: '登录已失效，请重新登录');
        return;
      }
      _error = '登录凭据暂时无法验证，已保留本机登录状态';
      notifyListeners();
    }
  }

  Future<void> _restoreProfile() async {
    try {
      final me = await _api.getMe(_token!);
      _applyProfile(me);
      _error = null;
      await _persist();
    } on ApiException catch (error) {
      if (!error.unauthorized) {
        _error = error.message;
        return;
      }
      final refreshed = await _refreshSession();
      if (!refreshed) {
        if (_refreshRejected || !_hasRefreshToken) {
          await _clearSession(error: '登录已失效，请重新登录');
        } else {
          _error = '登录凭据暂时无法验证，已保留本机登录状态';
        }
        return;
      }
      try {
        final me = await _api.getMe(_token!);
        _applyProfile(me);
        _error = null;
        await _persist();
      } catch (_) {
        _error = '账号信息暂时无法同步，已保留本机登录状态';
      }
    } catch (_) {
      _error = '账号信息暂时无法同步，已保留本机登录状态';
    }
  }

  Future<bool> _refreshSession() {
    final activeRefresh = _refreshFuture;
    if (activeRefresh != null) return activeRefresh;
    final refresh = _refresh;
    if (refresh == null || refresh.isEmpty) {
      _refreshRejected = false;
      return Future.value(false);
    }
    late final Future<bool> future;
    future = _performRefresh(refresh).whenComplete(() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    });
    _refreshFuture = future;
    return future;
  }

  Future<bool> _performRefresh(String refresh) async {
    _refreshRejected = false;
    try {
      final data = await _api.refreshToken(refresh);
      final nextToken = _pickAny(
        data,
        const ['accessToken', 'access_token', 'token'],
      );
      if (nextToken == null) return false;
      _token = nextToken;
      _refresh = _pickRefreshToken(data) ?? refresh;
      _expiresAtMs = _resolveExpiresAtMs(data, nextToken);
      _applyProfile(data);
      _error = null;
      ApiClient.instance.bearerToken = nextToken;
      await _persist();
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _refreshRejected = error.unauthorized ||
          error.statusCode == 400 ||
          error.statusCode == 401 ||
          error.statusCode == 403;
      return false;
    } catch (_) {
      return false;
    }
  }

  bool get _hasRefreshToken => _refresh != null && _refresh!.isNotEmpty;

  bool get _accessTokenNearExpiry {
    final expiresAtMs = _expiresAtMs;
    if (expiresAtMs == null || expiresAtMs <= 0) return false;
    return _now().millisecondsSinceEpoch >= expiresAtMs - _expirySafetyWindowMs;
  }

  Future<void> _clearSession({String? error}) async {
    try {
      await onSessionCleared?.call();
    } catch (_) {}
    _token = null;
    _refresh = null;
    _username = null;
    _email = null;
    _avatarUrl = null;
    _expiresAtMs = null;
    _userId = null;
    _error = error;
    ApiClient.instance.bearerToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_avatarUrlKey);
    await prefs.remove(_expiresAtMsKey);
    await prefs.remove(_userIdKey);
    try {
      await _legacySessionSource.clear();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await _writeOrRemove(prefs, _tokenKey, _token);
    await _writeOrRemove(prefs, _refreshKey, _refresh);
    await _writeOrRemove(prefs, _usernameKey, _username);
    await _writeOrRemove(prefs, _emailKey, _email);
    await _writeOrRemove(prefs, _avatarUrlKey, _avatarUrl);
    await _writeIntOrRemove(prefs, _expiresAtMsKey, _expiresAtMs);
    await _writeOrRemove(prefs, _userIdKey, _userId);
  }

  Future<void> _migrateLegacySession(SharedPreferences prefs) async {
    LegacyAuthSession? legacySession;
    try {
      legacySession = await _legacySessionSource.read();
    } catch (_) {
      return;
    }
    if (legacySession == null) return;

    final accessWritten =
        await prefs.setString(_tokenKey, legacySession.accessToken);
    final refreshWritten =
        await prefs.setString(_refreshKey, legacySession.refreshToken);
    final expiryWritten = legacySession.expiresAtMs == null
        ? await prefs.remove(_expiresAtMsKey)
        : await prefs.setInt(_expiresAtMsKey, legacySession.expiresAtMs!);
    final userIdWritten = legacySession.userId == null
        ? await prefs.remove(_userIdKey)
        : await prefs.setString(_userIdKey, legacySession.userId!);
    final verified = accessWritten &&
        refreshWritten &&
        expiryWritten &&
        userIdWritten &&
        prefs.getString(_tokenKey) == legacySession.accessToken &&
        prefs.getString(_refreshKey) == legacySession.refreshToken &&
        prefs.getInt(_expiresAtMsKey) == legacySession.expiresAtMs &&
        prefs.getString(_userIdKey) == legacySession.userId;

    if (!verified) {
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshKey);
      await prefs.remove(_expiresAtMsKey);
      await prefs.remove(_userIdKey);
      return;
    }

    _token = legacySession.accessToken;
    _refresh = legacySession.refreshToken;
    _expiresAtMs = legacySession.expiresAtMs;
    _userId = legacySession.userId;
    try {
      await _legacySessionSource.clear();
    } catch (_) {}
  }

  Future<void> _writeOrRemove(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  Future<void> _writeIntOrRemove(
    SharedPreferences prefs,
    String key,
    int? value,
  ) async {
    if (value == null || value <= 0) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, value);
    }
  }

  String? _pick(Map<String, dynamic> data, String first,
      [String b = '', String c = '']) {
    return _pickAny(
      data,
      [first, b, c].where((key) => key.isNotEmpty),
    );
  }

  String? _pickAny(Map<String, dynamic> data, Iterable<String> keys) {
    for (final key in keys) {
      final value = _normalizedString(data[key]);
      if (value != null) return value;
    }
    return null;
  }

  String? _pickRefreshToken(Map<String, dynamic> data) {
    return _pickAny(
      data,
      const [
        'refreshToken',
        'refresh_token',
        'refresh',
        'refresh_token_value',
      ],
    );
  }

  int? _resolveExpiresAtMs(
    Map<String, dynamic> data,
    String accessToken,
  ) {
    final absolute = _readPositiveInt(
      data,
      const ['expiresAtMs', 'expires_at_ms'],
    );
    if (absolute != null) return absolute;

    final seconds = _readPositiveInt(
      data,
      const ['expiresInSeconds', 'expires_in', 'expiresIn'],
    );
    if (seconds != null) {
      return _now().millisecondsSinceEpoch + seconds * 1000;
    }

    final minutes = _readPositiveInt(
      data,
      const ['expiresInMinutes', 'expires_in_minutes'],
    );
    if (minutes != null) {
      return _now().millisecondsSinceEpoch + minutes * 60000;
    }

    return _jwtExpiresAtMs(accessToken);
  }

  int? _readPositiveInt(
    Map<String, dynamic> data,
    Iterable<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      final parsed =
          value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  int? _jwtExpiresAtMs(String accessToken) {
    try {
      final parts = accessToken.split('.');
      if (parts.length < 2) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final value = payload['exp'];
      final seconds =
          value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
      return seconds != null && seconds > 0 ? seconds * 1000 : null;
    } catch (_) {
      return null;
    }
  }

  String? _normalizedString(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void _applyProfile(
    Map<String, dynamic> data, {
    bool clearMissing = false,
  }) {
    final nested = data['user'];
    final profile =
        nested is Map ? {...data, ...Map<String, dynamic>.from(nested)} : data;
    _username = _pick(profile, 'username', 'userName', 'name') ?? _username;
    _email = _pick(profile, 'email') ?? (clearMissing ? null : _email);
    if (_containsAny(profile, const ['avatarUrl', 'avatar_url', 'avatar'])) {
      _avatarUrl = _normalizeAvatarUrl(
        _pick(profile, 'avatarUrl', 'avatar_url', 'avatar'),
      );
    } else if (clearMissing) {
      _avatarUrl = null;
    }
  }

  bool _containsAny(Map<String, dynamic> data, List<String> keys) {
    return keys.any(data.containsKey);
  }

  String? _normalizeAvatarUrl(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) {
      final apiHost = Uri.parse(AppConfig.apiBaseUrl).host;
      if (uri.host == apiHost && uri.path.startsWith('/api/v1/user/avatar/')) {
        return Uri.parse(AppConfig.userContentBaseUrl)
            .resolveUri(Uri(path: uri.path, query: uri.query))
            .toString();
      }
      return raw;
    }
    return Uri.parse(AppConfig.userContentBaseUrl).resolve(raw).toString();
  }
}
