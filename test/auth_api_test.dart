import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/auth_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
