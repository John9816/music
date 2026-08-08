import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/discover/discover_view.dart';
import 'package:duck_music/features/playlists/playlist_detail_view.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('latest albums appear before daily recommendations',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    await _pumpDiscover(tester, api);

    final latestTitle = find.descendant(
      of: find.byType(SectionHeader),
      matching: find.text('最新专辑'),
    );
    final dailyTitle = find.descendant(
      of: find.byType(SectionHeader),
      matching: find.text('每日推荐'),
    );

    expect(
      tester.getTopLeft(latestTitle).dy,
      lessThan(tester.getTopLeft(dailyTitle).dy),
    );
  });

  testWidgets('latest album opens its song detail page with current source',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    await _pumpDiscover(tester, api);

    await tester.tap(find.text('测试新专辑'));
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistDetailView), findsOneWidget);
    final detail = tester.widget<PlaylistDetailView>(
      find.byType(PlaylistDetailView),
    );
    expect(detail.playlist.id, 42);
    expect(detail.playlist.name, '测试新专辑');
    expect(detail.playlist.source, 'qq');
    expect(api.albumDetailRequests.single, ('0035Y3b01o1BsG', 'qq'));
    expect(find.byTooltip('收藏歌单'), findsNothing);
    expect(find.byTooltip('加入我的歌单'), findsNothing);
  });
}

Future<void> _pumpDiscover(
  WidgetTester tester,
  _FakeDiscoverMusicApi api,
) async {
  SharedPreferences.setMockInitialValues(const {});
  final settings = SettingsController();
  await settings.setSource('qq');
  final player = PlayerController(settings: settings);
  final auth = AuthController();
  addTearDown(player.dispose);
  addTearDown(settings.dispose);
  addTearDown(auth.dispose);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 1000);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<AuthController>.value(value: auth),
      ],
      child: MaterialApp(
        theme: AppTheme.byId('light').data,
        home: DiscoverView(api: api),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeDiscoverMusicApi extends MusicApi {
  final albumDetailRequests = <(String, String)>[];

  final List<Song> daily = [
    Song(
      id: 'daily-1',
      name: '每日歌曲',
      source: 'qq',
      artists: const [Artist(id: 7, name: '每日歌手')],
      album: const Album(id: 8, name: '每日专辑'),
      durationMs: 180000,
    ),
  ];

  final albums = const [
    Album(
      id: 42,
      sourceId: '0035Y3b01o1BsG',
      name: '测试新专辑',
    ),
  ];

  @override
  Future<List<Song>> getDailyRecommend({String source = 'netease'}) async {
    return daily;
  }

  @override
  Future<List<Album>> getNewestAlbums({String source = 'netease'}) async {
    return albums;
  }

  @override
  Future<List<Song>> getAlbumDetail(
    String id, {
    String source = 'netease',
    int offset = 0,
    int limit = 100,
  }) async {
    albumDetailRequests.add((id, source));
    return daily;
  }
}
