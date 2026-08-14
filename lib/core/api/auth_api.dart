import 'api_client.dart';

class PasswordResetCodeInfo {
  const PasswordResetCodeInfo({
    required this.resendAfterSeconds,
    required this.expiresInSeconds,
  });

  final int resendAfterSeconds;
  final int expiresInSeconds;
}

class RegistrationCodeInfo {
  const RegistrationCodeInfo({
    required this.resendAfterSeconds,
    required this.expiresInSeconds,
  });

  final int resendAfterSeconds;
  final int expiresInSeconds;
}

class AuthApi {
  AuthApi({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<Map<String, dynamic>> login(String account, String password) async {
    final value = account.trim();
    return _client.postJson(
      'api/auth/login',
      body: value.contains('@')
          ? {'email': value, 'password': password}
          : {'username': value, 'password': password},
    );
  }

  Future<Map<String, dynamic>> register(
    String username,
    String email,
    String password,
    String verificationCode,
  ) async {
    final data = await _client.postJson('api/auth/register', body: {
      'username': username,
      'email': email,
      'password': password,
      'verificationCode': verificationCode,
    });
    return data;
  }

  Future<RegistrationCodeInfo> requestRegistrationCode(String email) async {
    final data = await _client.postJson(
      'api/auth/email-code',
      body: {'email': email},
    );
    return RegistrationCodeInfo(
      resendAfterSeconds: _intValue(data['resendAfterSeconds'], 60),
      expiresInSeconds: _intValue(data['expiresInSeconds'], 600),
    );
  }

  Future<Map<String, dynamic>> refreshToken(String refresh) async {
    final data = await _client.postJson(
      'api/auth/refresh',
      body: {
        'refresh_token': refresh,
        'refreshToken': refresh,
      },
      retryUnauthorized: false,
    );
    return data;
  }

  Future<void> logout(
    String refreshToken, {
    String? accessToken,
  }) async {
    await _client.postJson(
      'api/auth/logout',
      body: {
        'refresh_token': refreshToken,
        'refreshToken': refreshToken,
      },
      headers: {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      retryUnauthorized: false,
    );
  }

  Future<Map<String, dynamic>> getMe(String token) async {
    final data = await _client.getJson('api/user/me', headers: {
      'Authorization': 'Bearer $token',
    });
    return data;
  }

  Future<Map<String, dynamic>> updateProfile(
    String username,
    String email,
    String token,
  ) async {
    return _client.putJson(
      'api/user/profile',
      body: {
        'username': username.trim(),
        'email': email.trim(),
      },
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<Map<String, dynamic>> uploadAvatar(
    List<int> bytes,
    String filename,
    String token,
  ) async {
    return _client.postMultipart(
      'api/user/avatar',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
      contentType: _avatarContentType(filename),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  String? _avatarContentType(String filename) {
    switch (filename.split('.').last.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return null;
    }
  }

  Future<PasswordResetCodeInfo> requestPasswordResetCode(String email) async {
    final data = await _client.postJson(
      'api/auth/password-reset/email-code',
      body: {'email': email},
    );
    return PasswordResetCodeInfo(
      resendAfterSeconds: _intValue(data['resendAfterSeconds'], 60),
      expiresInSeconds: _intValue(data['expiresInSeconds'], 600),
    );
  }

  Future<void> confirmPasswordReset(
    String email,
    String verificationCode,
    String newPassword,
  ) async {
    await _client.postJson(
      'api/auth/password-reset/confirm',
      body: {
        'email': email,
        'verificationCode': verificationCode,
        'newPassword': newPassword,
      },
    );
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

  int _intValue(Object? value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
