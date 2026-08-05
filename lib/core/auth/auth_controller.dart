import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/auth_api.dart';
import '../api/api_client.dart';

/// 登录状态管理 + token 持久化（对应 macOS 版 AuthService + ViewModel）。
class AuthController extends ChangeNotifier {
  static const _tokenKey = 'auth_token';
  static const _refreshKey = 'auth_refresh_token';
  static const _usernameKey = 'auth_username';

  final AuthApi _api = AuthApi();

  String? _token;
  String? _refresh;
  String? _username;
  bool _loading = false;
  bool _initialized = false;
  String? _error;
  bool _invalidating = false;

  AuthController() {
    ApiClient.instance.onUnauthorized = _handleUnauthorized;
  }

  String? get token => _token;
  String? get username => _username;
  bool get isLoggedIn => _token != null;
  bool get loading => _loading;
  bool get initialized => _initialized;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);
      _refresh = prefs.getString(_refreshKey);
      _username = prefs.getString(_usernameKey);
      ApiClient.instance.bearerToken = _token;
      if (_token != null) {
        try {
          final me = await _api.getMe(_token!);
          _username = _pick(me, 'username', 'name') ?? _username;
        } catch (e) {
          if (e is! ApiException || !e.unauthorized) {
            _error = null;
          }
        }
      }
    } finally {
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
      _username = _pick(d, 'username') ?? username;
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
      _username = _pick(d, 'username') ?? username;
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
    ApiClient.instance.bearerToken = null;
    if (token != null) {
      try {
        await _api.logout(token);
      } catch (_) {}
    }
    await _clearSession();
  }

  Future<void> _handleUnauthorized() async {
    if (_invalidating || _token == null) return;
    _invalidating = true;
    try {
      await _clearSession(error: '登录已失效，请重新登录');
    } finally {
      _invalidating = false;
    }
  }

  Future<void> _clearSession({String? error}) async {
    _token = null;
    _refresh = null;
    _username = null;
    _error = error;
    ApiClient.instance.bearerToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_usernameKey);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) await prefs.setString(_tokenKey, _token!);
    if (_refresh != null) await prefs.setString(_refreshKey, _refresh!);
    if (_username != null) await prefs.setString(_usernameKey, _username!);
  }

  String? _pick(Map<String, dynamic> d, String a,
      [String b = '', String c = '']) {
    for (final k in [a, b, c].where((x) => x.isNotEmpty)) {
      final v = d[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }
}
