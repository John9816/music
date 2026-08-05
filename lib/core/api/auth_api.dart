import 'api_client.dart';

class AuthApi {
  final ApiClient _client = ApiClient.instance;

  Future<Map<String, dynamic>> login(String username, String password) async {
    final data = await _client.postJson('api/auth/login', body: {
      'username': username,
      'password': password,
    });
    return data;
  }

  Future<Map<String, dynamic>> register(
      String username, String email, String password) async {
    final data = await _client.postJson('api/auth/register', body: {
      'username': username,
      'email': email,
      'password': password,
    });
    return data;
  }

  Future<Map<String, dynamic>> refreshToken(String refresh) async {
    final data = await _client.postJson('api/auth/refresh', body: {
      'refresh_token': refresh,
    });
    return data;
  }

  Future<void> logout(String token) async {
    await _client.postJson('api/auth/logout', body: null, headers: {
      'Authorization': 'Bearer $token',
    });
  }

  Future<Map<String, dynamic>> getMe(String token) async {
    final data = await _client.getJson('api/user/me', headers: {
      'Authorization': 'Bearer $token',
    });
    return data;
  }

  Future<String> requestPasswordReset(String account, String token) async {
    final data = await _client.postJson(
      'api/auth/forgot-password',
      body: {'email': account, 'username': account},
      headers: {'Authorization': 'Bearer $token'},
    );
    return data['message']?.toString() ?? '安全重置邮件已发送';
  }

  Future<List<Map<String, dynamic>>> getDevices(String token) async {
    final data = await _client.getJson(
      'api/user/me/devices',
      headers: {'Authorization': 'Bearer $token'},
    );
    final raw = data['items'] ?? data['devices'] ?? data['list'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> revokeDevice(String deviceId, String token) async {
    await _client.deleteJson(
      'api/user/me/devices/${Uri.encodeComponent(deviceId)}',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> deleteAccount(String token) async {
    await _client.deleteJson(
      'api/user/me',
      headers: {'Authorization': 'Bearer $token'},
    );
  }
}
