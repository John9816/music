import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/auth_api.dart';
import '../api/api_client.dart';
import '../config/app_config.dart';

/// 登录状态管理 + token 持久化（对应 macOS 版 AuthService + ViewModel）。
class AuthController extends ChangeNotifier {
  static const _tokenKey = 'auth_token';
  static const _refreshKey = 'auth_refresh_token';
  static const _usernameKey = 'auth_username';
  static const _emailKey = 'auth_email';
  static const _avatarUrlKey = 'auth_avatar_url';

  AuthController({
    AuthApi? api,
    this.onSessionCleared,
  }) : _api = api ?? AuthApi() {
    ApiClient.instance.onUnauthorized = _handleUnauthorized;
  }

  final AuthApi _api;
  final Future<void> Function()? onSessionCleared;

  String? _token;
  String? _refresh;
  String? _username;
  String? _email;
  String? _avatarUrl;
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
      _token = prefs.getString(_tokenKey);
      _refresh = prefs.getString(_refreshKey);
      _username = prefs.getString(_usernameKey);
      _email = prefs.getString(_emailKey);
      final storedAvatarUrl = prefs.getString(_avatarUrlKey);
      _avatarUrl = _normalizeAvatarUrl(storedAvatarUrl);
      if (_avatarUrl != storedAvatarUrl) {
        await _writeOrRemove(prefs, _avatarUrlKey, _avatarUrl);
      }
      ApiClient.instance.bearerToken = _token;

      if (_token == null && _refresh != null) {
        await _refreshSession();
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
      _token = _pick(d, 'accessToken', 'access_token', 'token');
      _refresh = _pick(d, 'refreshToken', 'refresh_token');
      _applyProfile(d, clearMissing: true);
      _username ??= username;
      if (_token == null) throw Exception('登录响应缺少 accessToken');
      ApiClient.instance.bearerToken = _token;
      if (_email == null || _avatarUrl == null) await _restoreProfile();
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
      _token = _pick(d, 'accessToken', 'access_token', 'token');
      _refresh = _pick(d, 'refreshToken', 'refresh_token');
      _applyProfile(d, clearMissing: true);
      _username ??= username;
      _email ??= email;
      if (_token == null) throw Exception('注册响应缺少 accessToken');
      ApiClient.instance.bearerToken = _token;
      if (_avatarUrl == null) await _restoreProfile();
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
    final token = _token;
    await _clearSession();
    if (token != null) {
      try {
        await _api.logout(token);
      } catch (_) {}
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
      final nextToken = _pick(data, 'accessToken', 'access_token', 'token');
      if (nextToken == null) return false;
      _token = nextToken;
      _refresh = _pick(data, 'refreshToken', 'refresh_token') ?? refresh;
      _applyProfile(data);
      _error = null;
      ApiClient.instance.bearerToken = nextToken;
      await _persist();
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _refreshRejected = error.unauthorized;
      return false;
    } catch (_) {
      return false;
    }
  }

  bool get _hasRefreshToken => _refresh != null && _refresh!.isNotEmpty;

  Future<void> _clearSession({String? error}) async {
    await onSessionCleared?.call();
    _token = null;
    _refresh = null;
    _username = null;
    _email = null;
    _avatarUrl = null;
    _error = error;
    ApiClient.instance.bearerToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_avatarUrlKey);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await _writeOrRemove(prefs, _tokenKey, _token);
    await _writeOrRemove(prefs, _refreshKey, _refresh);
    await _writeOrRemove(prefs, _usernameKey, _username);
    await _writeOrRemove(prefs, _emailKey, _email);
    await _writeOrRemove(prefs, _avatarUrlKey, _avatarUrl);
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

  String? _pick(Map<String, dynamic> d, String a,
      [String b = '', String c = '']) {
    for (final k in [a, b, c].where((x) => x.isNotEmpty)) {
      final v = d[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
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
