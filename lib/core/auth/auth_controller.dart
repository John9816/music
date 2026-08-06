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
  String? _avatarUrl;
  bool _loading = false;
  bool _initialized = false;
  String? _error;
  bool _refreshing = false;
  bool _restoring = false;

  String? get token => _token;
  String? get username => _username;
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
      if (_token == null) throw Exception('注册响应缺少 accessToken');
      ApiClient.instance.bearerToken = _token;
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

  Future<void> _handleUnauthorized() async {
    if (_restoring || _refreshing || _token == null) return;
    final refreshed = await _refreshSession();
    if (!refreshed) {
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
      if (!error.unauthorized || !await _refreshSession()) {
        _error = error.unauthorized ? '登录凭据暂时无法验证，已保留本机登录状态' : error.message;
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

  Future<bool> _refreshSession() async {
    final refresh = _refresh;
    if (_refreshing || refresh == null || refresh.isEmpty) return false;
    _refreshing = true;
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
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _clearSession({String? error}) async {
    await onSessionCleared?.call();
    _token = null;
    _refresh = null;
    _username = null;
    _avatarUrl = null;
    _error = error;
    ApiClient.instance.bearerToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_avatarUrlKey);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await _writeOrRemove(prefs, _tokenKey, _token);
    await _writeOrRemove(prefs, _refreshKey, _refresh);
    await _writeOrRemove(prefs, _usernameKey, _username);
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
    _username = _pick(data, 'username', 'name') ?? _username;
    if (data.containsKey('avatarUrl')) {
      _avatarUrl = _normalizeAvatarUrl(_pick(data, 'avatarUrl'));
    } else if (clearMissing) {
      _avatarUrl = null;
    }
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
