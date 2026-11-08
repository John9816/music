import 'dart:async';
import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/profile/profile_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

final _requests =
    <({String? authorization, Completer<http.Response> response})>[];

void main() {
  setUpAll(() {
    http.runWithClient(
      () => ApiClient.instance,
      () => MockClient((request) {
        expectSync(request.url.path, '/api/user/membership');
        final response = Completer<http.Response>();
        _requests.add((
          authorization: request.headers['Authorization'],
          response: response
        ));
        return response.future;
      }),
    );
  });

  setUp(() {
    _requests.clear();
    ApiClient.instance.bearerToken = null;
  });

  for (final change in ['account', 'token rotation', 'same-token session']) {
    testWidgets(
        '$change starts a new membership request while the old one is pending',
        (tester) async {
      final auth = _MembershipAuth();
      await _pumpProfile(tester, auth);
      expect(_requests, hasLength(1));

      switch (change) {
        case 'account':
          auth.changeSession('second-account');
        case 'token rotation':
          auth.rotateToken('refreshed-token');
        case 'same-token session':
          auth.changeSession('first-account');
      }
      await tester.pumpAndSettle();
      expect(_requests, hasLength(2));
      expect(_requests.last.authorization, 'Bearer ${auth.token}');
      _requests.first.response.complete(_membership('旧会员'));
      await tester.pumpAndSettle();
      expect(find.text('正在读取会员状态'), findsOneWidget);
      expect(find.textContaining('旧会员'), findsNothing);

      _requests.last.response.complete(_membership('当前会员'));
      await tester.pumpAndSettle();
      expect(find.text('当前会员 · 长期有效'), findsOneWidget);
      expect(find.text('正在读取会员状态'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final oldFails in [false, true]) {
    testWidgets(
        'old membership completion cannot replace a newer result; failure=$oldFails',
        (tester) async {
      final auth = _MembershipAuth();
      await _pumpProfile(tester, auth);
      auth.changeSession('second-account');
      await tester.pumpAndSettle();
      expect(_requests, hasLength(2));
      _requests.last.response.complete(_membership('新账号会员'));
      await tester.pumpAndSettle();
      _requests.first.response
          .complete(oldFails ? _failure() : _membership('旧账号会员'));
      await tester.pumpAndSettle();

      expect(find.text('新账号会员 · 长期有效'), findsOneWidget);
      expect(find.textContaining('旧账号会员'), findsNothing);
      expect(find.text('状态获取失败，点击重试'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('logout clears pending membership state; failure=$oldFails',
        (tester) async {
      final auth = _MembershipAuth();
      await _pumpProfile(tester, auth);
      auth.changeSession(null);
      await tester.pumpAndSettle();
      expect(find.text('登录后查看会员状态'), findsOneWidget);
      expect(find.text('正在读取会员状态'), findsNothing);
      _requests.single.response
          .complete(oldFails ? _failure() : _membership('旧账号会员'));
      await tester.pumpAndSettle();
      expect(find.text('登录后查看会员状态'), findsOneWidget);
      expect(find.text('状态获取失败，点击重试'), findsNothing);
      expect(find.textContaining('旧账号会员'), findsNothing);
      expect(_requests, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('membership failure retries once and keeps redemption hidden',
      (tester) async {
    await _pumpProfile(tester, _MembershipAuth());
    _requests.single.response.complete(_failure());
    await tester.pumpAndSettle();
    expect(find.text('状态获取失败，点击重试'), findsOneWidget);
    await tester.tap(find.text('会员权益'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('会员权益'));
    await tester.pumpAndSettle();
    expect(_requests, hasLength(2));
    _requests.last.response.complete(_membership('恢复会员'));
    await tester.pumpAndSettle();
    expect(find.text('恢复会员 · 长期有效'), findsOneWidget);
    await tester.tap(find.text('会员权益'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('兑换'), findsNothing);
    expect(_requests, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile changes preserve membership without another request',
      (tester) async {
    final auth = _MembershipAuth();
    await _pumpProfile(tester, auth);
    _requests.single.response.complete(_membership('当前会员'));
    await tester.pumpAndSettle();
    auth.rename('新昵称');
    await tester.pumpAndSettle();
    expect(find.text('当前会员 · 长期有效'), findsOneWidget);
    expect(_requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('membership completion after leaving the profile is ignored',
      (tester) async {
    await _pumpProfile(tester, _MembershipAuth());
    await tester.pumpWidget(const SizedBox.shrink());
    _requests.single.response.complete(_failure());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpProfile(WidgetTester tester, _MembershipAuth auth) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final request in _requests) {
      if (!request.response.isCompleted) {
        request.response.complete(_membership('结束'));
      }
    }
    await tester.pumpAndSettle();
    auth.dispose();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(ChangeNotifierProvider<AuthController>.value(
    value: auth,
    child: MaterialApp(
      theme:
          AppTheme.byId('dark').data.copyWith(platform: TargetPlatform.android),
      home: const ProfileView(),
    ),
  ));
  await tester.pumpAndSettle();
}

http.Response _membership(String name) => http.Response(
      jsonEncode({
        'code': 0,
        'data': {'active': true, 'lifetime': true, 'typeName': name}
      }),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _failure() => http.Response(
      jsonEncode({'code': 503, 'message': '暂时不可用'}),
      503,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

class _MembershipAuth extends AuthController {
  String? _currentToken = 'first-account';
  int _generation = 1;
  String _name = '测试用户';

  @override
  String? get token => _currentToken;
  @override
  bool get isLoggedIn => token != null;
  @override
  int get sessionGeneration => _generation;
  @override
  String get username => _name;

  void changeSession(String? token) {
    _currentToken = token;
    _generation++;
    notifyListeners();
  }

  void rotateToken(String token) {
    _currentToken = token;
    notifyListeners();
  }

  void rename(String name) {
    _name = name;
    notifyListeners();
  }
}
