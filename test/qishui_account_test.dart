import 'dart:async';
import 'dart:convert';
import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/qishui_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/features/settings/qishui_account_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class TestAuth extends AuthController {
  int generation = 1;
  bool loggedIn = true;
  @override
  bool get isLoggedIn => loggedIn;
  @override
  int get sessionGeneration => generation;
  void switchAccount() {
    generation++;
    notifyListeners();
  }
}

http.Response ok(Map<String, dynamic> data) =>
    http.Response(jsonEncode({'code': 0, 'data': data}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
void main() {
  test(
      'QR poll uses encoded session path and does not retry under another login',
      () async {
    var refreshes = 0;
    final requests = <http.Request>[];
    final client = ApiClient.forTesting(MockClient((r) async {
      requests.add(r);
      return http.Response('{"code":401}', 401);
    }))
      ..bearerToken = 'synthetic';
    client.onUnauthorized = () async {
      refreshes++;
      client.bearerToken = 'another';
    };
    await expectLater(QishuiApi(client: client).poll('session/one'),
        throwsA(isA<ApiException>()));
    expect(requests.single.url.pathSegments.last, 'session/one');
    expect(refreshes, 0);
  });
  test('old account response cannot leak after account switch', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final auth = TestAuth();
    final api = QishuiApi(
        client: ApiClient.forTesting(MockClient((_) => ++calls == 1
            ? pending.future
            : Future.value(ok({'status': 'unbound', 'bound': false})))));
    final c = QishuiAccountController(auth: auth, api: api);
    final first = c.load();
    auth.switchAccount();
    await Future<void>.delayed(Duration.zero);
    pending.complete(
        ok({'status': 'bound', 'bound': true, 'nickname': 'old-private-name'}));
    await first;
    expect(c.account?.nickname, isNull);
    expect(c.account?.bound, isFalse);
    c.dispose();
    auth.dispose();
  });
  testWidgets('scanned polling retains the PNG and expired sessions stop',
      (tester) async {
    final auth = TestAuth();
    var polls = 0;
    final api = QishuiApi(client: ApiClient.forTesting(MockClient((r) async {
      if (r.method == 'POST') {
        return ok({
          'status': 'new',
          'sessionId': 'one',
          'qrcode': 'aGVsbG8=',
          'qrcodeUrl': 'aweme://synthetic',
          'sessionExpiresAt':
              DateTime.now().add(const Duration(minutes: 3)).toIso8601String()
        });
      }
      return ok({'status': ++polls == 1 ? 'scanned' : 'expired'});
    })));
    final c = QishuiAccountController(auth: auth, api: api);
    c.setActive(false);
    await tester.runAsync(c.start);
    c.setActive(true);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(c.qr?.status, 'scanned');
    expect(c.qr?.qrcode, 'aGVsbG8=');
    expect(c.qr?.qrcodeUrl, 'aweme://synthetic');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(c.qr, isNull);
    expect(c.error, contains('过期'));
    await tester.pump(const Duration(seconds: 10));
    expect(polls, 2);
    c.dispose();
    auth.dispose();
  });

  testWidgets('unauthorized polling stops without replay or indefinite retries',
      (tester) async {
    final auth = TestAuth();
    var polls = 0;
    final api = QishuiApi(client: ApiClient.forTesting(MockClient((r) async {
      if (r.method == 'POST') {
        return ok({
          'status': 'new',
          'sessionId': 'one',
          'qrcode': 'aGVsbG8=',
          'sessionExpiresAt':
              DateTime.now().add(const Duration(minutes: 3)).toIso8601String()
        });
      }
      polls++;
      return http.Response('{"code":401}', 401);
    })));
    final c = QishuiAccountController(auth: auth, api: api);
    c.setActive(false);
    await tester.runAsync(c.start);
    c.setActive(true);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(c.qr, isNull);
    expect(c.error, isNotNull);
    await tester.pump(const Duration(seconds: 10));
    expect(polls, 1);
    c.dispose();
    auth.dispose();
  });

  testWidgets('poll stops in background, handles terminal state and disposal',
      (tester) async {
    final auth = TestAuth();
    var polls = 0;
    final api = QishuiApi(client: ApiClient.forTesting(MockClient((r) async {
      if (r.method == 'POST') {
        return ok({
          'status': 'new',
          'sessionId': 's1',
          'qrcode': 'aGVsbG8=',
          'sessionExpiresAt':
              DateTime.now().add(const Duration(minutes: 3)).toIso8601String(),
          'pollIntervalSeconds': 2
        });
      }
      polls++;
      return ok({'status': 'confirmed', 'bound': true, 'nickname': 'new-name'});
    })));
    final c = QishuiAccountController(auth: auth, api: api);
    await tester.runAsync(c.start);
    c.setActive(false);
    await tester.pump(const Duration(seconds: 5));
    expect(polls, 0);
    c.setActive(true);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(polls, 1);
    expect(c.account?.nickname, 'new-name');
    expect(c.qr, isNull);
    await tester.pump(const Duration(seconds: 6));
    expect(polls, 1);
    c.dispose();
    auth.dispose();
  });
}
