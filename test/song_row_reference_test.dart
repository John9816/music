import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:duck_music/widgets/song_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  var fetches = 0;
  final favorites = <String>{};
  final deletions = <String>[];
  VoidCallback? onMutation;
  setUpAll(() {
    http.runWithClient(
        () => ApiClient.instance,
        () => MockClient((request) async {
              if (request.method == 'GET') {
                fetches++;
                return _response({
                  'items': [
                    if (request.headers['Authorization'] ==
                        'Bearer first-account')
                      for (final identity in favorites)
                        {
                          'songId': identity.split(':').last,
                          'source': identity.split(':').first
                        }
                  ]
                });
              }
              if (request.method == 'DELETE') {
                final identity =
                    '${request.url.queryParameters['source']}:${request.url.queryParameters['songId']}';
                favorites.remove(identity);
                deletions.add(identity);
                onMutation?.call();
              }
              return _response({});
            }));
  });
  setUp(() {
    fetches = 0;
    onMutation = null;
    deletions.clear();
    favorites
      ..clear()
      ..add('netease:same');
  });

  testWidgets('row hearts share one fetch and favorite taps do not play a song',
      (tester) async {
    final auth = _RowAuth();
    var plays = 0;
    await _pump(tester, auth, () => plays++);
    expect(fetches, 1);
    expect(find.byTooltip('取消收藏：红源歌曲'), findsOneWidget);
    expect(find.byTooltip('收藏歌曲：绿源歌曲'), findsOneWidget);
    final heart = tester.widget<GIconButton>(find
        .descendant(
            of: find.byType(SongRow).first, matching: find.byType(GIconButton))
        .first);
    expect(heart.tint, AppBrand.favoriteRed);
    await tester.tap(find.byTooltip('取消收藏：红源歌曲'));
    await tester.pumpAndSettle();
    expect(deletions, ['netease:same']);
    expect(find.byTooltip('收藏歌曲：红源歌曲'), findsOneWidget);
    expect(plays, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('row favorite state clears when the account changes',
      (tester) async {
    final auth = _RowAuth();
    await _pump(tester, auth, () {});
    expect(find.byTooltip('取消收藏：红源歌曲'), findsOneWidget);
    auth.switchAccount();
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消收藏：红源歌曲'), findsNothing);
    expect(find.byTooltip('收藏歌曲：红源歌曲'), findsOneWidget);
    expect(fetches, 2);
  });

  testWidgets('favorite completion updates the player after token rotation',
      (tester) async {
    final auth = _RowAuth();
    final player = await _pump(tester, auth, () {});
    player.setLiked(true);
    onMutation = auth.refreshToken;
    await tester.tap(find.byTooltip('取消收藏：红源歌曲'));
    await tester.pumpAndSettle();
    expect(auth.sessionGeneration, 1);
    expect(auth.token, 'refreshed-account');
    expect(player.liked, isFalse);
    expect(find.byTooltip('收藏歌曲：红源歌曲'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old account favorite completion cannot change the new player',
      (tester) async {
    final auth = _RowAuth();
    final player = await _pump(tester, auth, () {});
    player.setLiked(true);
    onMutation = auth.switchAccount;
    await tester.tap(find.byTooltip('取消收藏：红源歌曲'));
    await tester.pumpAndSettle();
    expect(auth.sessionGeneration, 2);
    expect(player.liked, isTrue);
    expect(find.text('已取消收藏'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

http.Response _response(Map<String, dynamic> data) => http.Response(
      jsonEncode({'code': 0, 'data': data}),
      200,
      headers: {'content-type': 'application/json'},
    );

Future<PlayerController> _pump(
    WidgetTester tester, _RowAuth auth, VoidCallback onPlay) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  final settings = SettingsController();
  final player = _RowPlayer(settings: settings);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
    auth.dispose();
    settings.dispose();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<PlayerController>.value(value: player),
      ],
      child: MaterialApp(
        theme: AppTheme.byId('dark').data,
        home: Scaffold(
            body: Column(children: [
          for (final source in ['netease', 'qq'])
            SongRow(
                song: Song(
                    id: 'same',
                    name: source == 'qq' ? '绿源歌曲' : '红源歌曲',
                    source: source,
                    artists: const [Artist(id: 1, name: '歌手名字')],
                    album: const Album(id: 1, name: '专辑'),
                    durationMs: 100000),
                onTap: onPlay),
        ])),
      )));
  await tester.pumpAndSettle();
  return player;
}

class _RowPlayer extends PlayerController {
  _RowPlayer({required super.settings});

  @override
  Song get current => Song(
      id: 'same',
      name: '红源歌曲',
      source: 'netease',
      artists: const [Artist(id: 1, name: '歌手名字')],
      album: const Album(id: 1, name: '专辑'),
      durationMs: 100000);
}

class _RowAuth extends AuthController {
  String accountToken = 'first-account';
  int generation = 1;
  @override
  String get token => accountToken;
  @override
  int get sessionGeneration => generation;
  void switchAccount() {
    accountToken = 'second-account';
    generation++;
    notifyListeners();
  }

  void refreshToken() {
    accountToken = 'refreshed-account';
    notifyListeners();
  }
}
