import 'dart:convert';
import 'package:duck_music/core/api/user_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/playlists/playlist_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/models/playlist.dart';
import 'package:duck_music/core/config/audio_quality_policy.dart';
import 'package:duck_music/core/player/lrc_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth extends AuthController {
  @override
  String get token => 'synthetic';
  @override
  bool get isLoggedIn => true;
}

void main() {
  testWidgets(
      'black playlist scroll appends and favorite preserves its opaque ID',
      (tester) async {
    const id = '7530012345678901234:7000012345678901234:2';
    final pages = <int>[];
    final favorites = <Map>[];
    final requestedIds = <String?>[];
    final client = ApiClient.forTesting(MockClient((r) async {
      Map<String, dynamic> data = {};
      if (r.url.path == '/api/v1/music/playlist/detail') {
        requestedIds.add(r.url.queryParameters['id']);
        final page = int.parse(r.url.queryParameters['page']!);
        pages.add(page);
        data = {
          'total': null,
          'list': List.generate(
              page == 1 ? 100 : 1,
              (i) => {
                    'id': 'song-${(page - 1) * 100 + i}',
                    'name': '黑源歌曲 ${(page - 1) * 100 + i}',
                    'source': 'qishui',
                    'artist': '歌手',
                    'durationMs': 180000
                  })
        };
      } else if (r.method == 'POST') {
        favorites.add(jsonDecode(r.body) as Map);
      }
      return http.Response(jsonEncode({'code': 0, 'data': data}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    final settings = SettingsController();
    final player = PlayerController(settings: settings);
    final auth = _Auth();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: MaterialApp(
            theme: AppTheme.byId('dark')
                .data
                .copyWith(platform: TargetPlatform.android),
            home: PlaylistDetailView(
                playlist: Playlist.fromV1(
                    {'id': id, 'source': 'qishui', 'name': '黑源歌单'}),
                musicApi: MusicApi(client: client),
                userApi: UserApi(client: client)))));
    await tester.pumpAndSettle();
    expect(pages, [1]);
    await tester.tap(find.byTooltip('收藏歌单'));
    await tester.pumpAndSettle();
    expect(favorites.single['playlistId'], id);
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(pages, [1, 2]);
    expect(requestedIds, [id, id]);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('黑源歌曲 100'), findsOneWidget);
    expect(find.text('已加载 101 首'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
    settings.dispose();
    auth.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  test('black playlist identity survives search and paged detail requests',
      () async {
    const id = '7530012345678901234:7000012345678901234:2';
    final requests = <Uri>[];
    final api = MusicApi(client: ApiClient.forTesting(MockClient((r) async {
      requests.add(r.url);
      return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'id': id,
              'page': 2,
              'pageSize': 100,
              'total': null,
              'list': [
                {
                  'id': '7530012345678901234',
                  'name': '测试',
                  'source': 'qishui',
                  'artist': '歌手',
                  'artistId': '9530012345678901234',
                  'durationMs': 123456
                }
              ]
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    })));
    final p = Playlist.fromV1({'id': id, 'name': '歌单', 'source': 'qishui'});
    final page =
        await api.getPlaylistPage(p.detailId, source: 'qishui', offset: 100);
    expect(requests.single.queryParameters,
        {'source': 'qishui', 'id': id, 'page': '2', 'pageSize': '100'});
    expect(page.songs.single.id, '7530012345678901234');
    expect(page.songs.single.artists.single.detailId, '9530012345678901234');
    expect(page.songs.single.durationMs, 123456);
    expect(page.hasMore, isFalse);
    expect(page.nextOffset, 200);
  });
  test('black source defaults to explicit 320k and keeps timed lyrics',
      () async {
    expect(defaultQualityForSource('qishui'), 'exhigh');
    expect(normalizeQualityForSource('qs', 'auto'), 'exhigh');
    final api = MusicApi(
        client: ApiClient.forTesting(MockClient((r) async => http.Response(
            jsonEncode({
              'code': 0,
              'data': {
                'official': true,
                'provider': 'qishui',
                'lineLyrics': '[00:01.000]测试',
                'karaokeLyrics': '[1000,800](1000,300,0)测(1300,500,0)试'
              }
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'}))));
    final lyric = await api.getLyric('7530012345678901234', source: 'qishui');
    expect(lyric, '[1000,800](1000,300,0)测(1300,500,0)试');
    expect(parseKaraokeLrc(lyric!), isNotEmpty);
  });
  test('encrypted or unconfigured playback errors stay visible', () async {
    final api = MusicApi(
        client: ApiClient.forTesting(MockClient((r) async => http.Response(
            jsonEncode({'code': 1003, 'message': '黑源播放服务尚未配置'}), 503,
            headers: {'content-type': 'application/json; charset=utf-8'}))));
    await expectLater(
        api.getPlaybackInfo('id', source: 'qishui'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', '黑源播放服务尚未配置')));
  });
}
