import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/auth_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('email login sends the email field', () async {
    Map<String, dynamic>? requestBody;
    final client = ApiClient.forTesting(MockClient((request) async {
      requestBody = Map<String, dynamic>.from(
        jsonDecode(request.body) as Map,
      );
      return _okResponse();
    }));
    final api = AuthApi(client: client);

    await api.login(' listener@qq.com ', 'secret12');

    expect(requestBody, {
      'email': 'listener@qq.com',
      'password': 'secret12',
    });
  });

  test('username login sends the username field', () async {
    Map<String, dynamic>? requestBody;
    final client = ApiClient.forTesting(MockClient((request) async {
      requestBody = Map<String, dynamic>.from(
        jsonDecode(request.body) as Map,
      );
      return _okResponse();
    }));
    final api = AuthApi(client: client);

    await api.login(' listener ', 'secret12');

    expect(requestBody, {
      'username': 'listener',
      'password': 'secret12',
    });
  });

  test('registration code request uses the public email-code endpoint',
      () async {
    late http.Request capturedRequest;
    final client = ApiClient.forTesting(MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            'resendAfterSeconds': '45',
            'expiresInSeconds': 300,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }));
    final api = AuthApi(client: client);

    final info = await api.requestRegistrationCode('12345@qq.com');

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.url.path, '/api/auth/email-code');
    expect(jsonDecode(capturedRequest.body), {'email': '12345@qq.com'});
    expect(info.resendAfterSeconds, 45);
    expect(info.expiresInSeconds, 300);
  });

  test('registration submits the email verification code', () async {
    late http.Request capturedRequest;
    final client = ApiClient.forTesting(MockClient((request) async {
      capturedRequest = request;
      return _okResponse();
    }));
    final api = AuthApi(client: client);

    await api.register('listener', '12345@qq.com', 'secret12', '123456');

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.url.path, '/api/auth/register');
    expect(jsonDecode(capturedRequest.body), {
      'username': 'listener',
      'email': '12345@qq.com',
      'password': 'secret12',
      'verificationCode': '123456',
    });
  });

  test('refresh request sends snake and camel case token fields', () async {
    Map<String, dynamic>? requestBody;
    final client = ApiClient.forTesting(MockClient((request) async {
      requestBody = Map<String, dynamic>.from(
        jsonDecode(request.body) as Map,
      );
      return _okResponse();
    }));
    final api = AuthApi(client: client);

    await api.refreshToken('rotating-refresh');

    expect(requestBody, {
      'refresh_token': 'rotating-refresh',
      'refreshToken': 'rotating-refresh',
    });
  });

  test('logout sends refresh token body and access token header', () async {
    Map<String, dynamic>? requestBody;
    String? authorization;
    final client = ApiClient.forTesting(MockClient((request) async {
      requestBody = Map<String, dynamic>.from(
        jsonDecode(request.body) as Map,
      );
      authorization = request.headers['authorization'];
      return _okResponse();
    }));
    final api = AuthApi(client: client);

    await api.logout(
      'logout-refresh',
      accessToken: 'logout-access',
    );

    expect(requestBody, {
      'refresh_token': 'logout-refresh',
      'refreshToken': 'logout-refresh',
    });
    expect(authorization, 'Bearer logout-access');
  });
}

http.Response _okResponse() {
  return http.Response(
    jsonEncode({'code': 0, 'data': <String, dynamic>{}}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
