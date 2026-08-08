import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('unauthorized request refreshes and retries with the new token',
      () async {
    var requestCount = 0;
    late final ApiClient client;
    final httpClient = MockClient((request) async {
      requestCount++;
      if (requestCount == 1) {
        expect(request.headers['authorization'], 'Bearer expired-access');
        return http.Response(
          jsonEncode({
            'code': 401,
            'message': '需要登录才能播放',
            'data': null,
          }),
          401,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      expect(request.headers['authorization'], 'Bearer refreshed-access');
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {'ok': true},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    client = ApiClient.forTesting(httpClient)
      ..bearerToken = 'expired-access'
      ..onUnauthorized = () async {
        client.bearerToken = 'refreshed-access';
      };

    final result = await client.getJson(
      'api/v1/music/new',
      headers: {'Authorization': 'Bearer expired-access'},
    );

    expect(result['ok'], isTrue);
    expect(requestCount, 2);
  });

  test('unauthorized retry runs at most once', () async {
    var requestCount = 0;
    late final ApiClient client;
    final httpClient = MockClient((_) async {
      requestCount++;
      return http.Response(
        jsonEncode({
          'code': 401,
          'message': '需要登录才能播放',
          'data': null,
        }),
        401,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    client = ApiClient.forTesting(httpClient)
      ..bearerToken = 'expired-access'
      ..onUnauthorized = () async {
        client.bearerToken = 'refreshed-access';
      };

    await expectLater(
      client.getJson('api/v1/music/new'),
      throwsA(isA<ApiException>().having(
        (error) => error.unauthorized,
        'unauthorized',
        isTrue,
      )),
    );
    expect(requestCount, 2);
  });
}
