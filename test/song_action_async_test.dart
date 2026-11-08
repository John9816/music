import 'dart:async';
import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/widgets/song_action_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _song = Song(
  id: 'async-menu-song',
  name: '异步菜单歌曲',
  source: 'netease',
  artists: const [Artist(id: 1, name: '歌手')],
  album: const Album(id: 1, name: '专辑'),
  durationMs: 180000,
);

void main() {
  late Future<http.Response> Function(http.Request) respond;
  setUpAll(() {
    http.runWithClient(() => ApiClient.instance,
        () => MockClient((request) => respond(request)));
  });
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    respond = (_) async => _response({'items': []});
  });

  testWidgets('favorite action waits for current status before changing it',
      (tester) async {
    final status = Completer<http.Response>();
    addTearDown(() {
      if (!status.isCompleted) status.complete(_response({'items': []}));
    });
    var writes = 0;
    respond = (request) async {
      if (request.method == 'GET') return status.future;
      writes++;
      return _response({});
    };
    await _openMenu(tester);
    await tester.tap(find.text('喜欢'));
    await tester.pump();
    expect(writes, 0);
    status.complete(_response({
      'items': [
        {'songId': _song.id, 'source': _song.source}
      ]
    }));
    await tester.pumpAndSettle();
    expect(find.text('取消喜欢'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorite mutation ignores repeated taps and keeps server state',
      (tester) async {
    final mutation = Completer<http.Response>();
    addTearDown(() {
      if (!mutation.isCompleted) mutation.complete(_response({}));
    });
    var deletes = 0;
    respond = (request) async {
      if (request.method == 'GET') {
        return _response({
          'items': [
            {'songId': _song.id, 'source': _song.source}
          ]
        });
      }
      expect(request.method, 'DELETE');
      deletes++;
      return mutation.future;
    };
    await _openMenu(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消喜欢'));
    await tester.pump();
    await tester.tap(find.text('取消喜欢'));
    await tester.pump();
    expect(deletes, 1);
    mutation.complete(_response({}));
    await tester.pumpAndSettle();
    expect(find.text('喜欢'), findsOneWidget);
    expect(find.text('已取消喜欢'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'playlist fetch ignores repeated taps and can retry after failure',
      (tester) async {
    final failed = Completer<http.Response>();
    addTearDown(() {
      if (!failed.isCompleted) failed.complete(_response({'items': []}));
    });
    var loads = 0;
    respond = (request) async {
      if (request.url.path.endsWith('/playlists')) {
        loads++;
        if (loads == 1) return failed.future;
        return _response({'items': []});
      }
      return _response({'items': []});
    };
    await _openMenu(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏到歌单'));
    await tester.pump();
    await tester.tap(find.text('收藏到歌单'));
    await tester.pump();
    expect(loads, 1);
    failed.complete(http.Response(
        jsonEncode({'code': 500, 'message': '歌单暂时无法加载'}), 500,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await tester.pumpAndSettle();
    expect(find.text('歌单暂时无法加载'), findsOneWidget);
    await tester.tap(find.text('收藏到歌单'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('新建歌单'), findsOneWidget);
    expect(find.text('还没有歌单'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

http.Response _response(Map<String, dynamic> data) => http.Response(
      jsonEncode({'code': 0, 'data': data}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Future<void> _openMenu(WidgetTester tester) async {
  final settings = SettingsController();
  final player = PlayerController(settings: settings);
  final auth = _SignedInAuth();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
    player.dispose();
    auth.dispose();
  });
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsController>.value(value: settings),
      ChangeNotifierProvider<PlayerController>.value(value: player),
      ChangeNotifierProvider<AuthController>.value(value: auth),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: Scaffold(body: Center(child: SongActionButton(song: _song))),
    ),
  ));
  await tester.tap(find.byTooltip('更多：异步菜单歌曲'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

class _SignedInAuth extends AuthController {
  @override
  String get token => 'test-session';
  @override
  bool get isLoggedIn => true;
}
