import 'dart:async';

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
  testWidgets('albums are usable while daily recommendations are loading',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    final daily = Completer<List<Song>>();
    final albums = Completer<List<Album>>();
    api.loadDaily = () => daily.future;
    api.loadAlbums = () => albums.future;
    await _pumpDiscover(tester, api, settle: false);

    albums.complete(api.albums);
    await tester.pump();
    await tester.pump();

    expect(find.text('测试新专辑').hitTestable(), findsOneWidget);
    expect(find.byType(GSkeletonList), findsOneWidget);
    expect(find.byTooltip('播放每日推荐'), findsNothing);

    await tester.tap(find.text('测试新专辑'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PlaylistDetailView), findsOneWidget);
    expect(api.albumDetailRequests.single, ('0035Y3b01o1BsG', 'qq'));
    daily.complete(api.daily);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily recommendations appear while albums are loading',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    final daily = Completer<List<Song>>();
    final albums = Completer<List<Album>>();
    api.loadDaily = () => daily.future;
    api.loadAlbums = () => albums.future;
    await _pumpDiscover(tester, api, settle: false);

    daily.complete(api.daily);
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('播放每日推荐').hitTestable(), findsOneWidget);
    expect(find.text('每日歌曲'), findsNWidgets(2));
    expect(find.byType(GSkeletonList), findsNothing);
    expect(find.byType(GSkeleton), findsWidgets);
    expect(find.text('测试新专辑'), findsNothing);

    albums.complete(api.albums);
    await tester.pumpAndSettle();
    expect(find.text('测试新专辑'), findsOneWidget);
    expect(find.byType(GSkeleton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily failure exposes its retry before albums finish loading',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    final daily = Completer<List<Song>>();
    final albums = Completer<List<Album>>();
    api.loadDaily = () => daily.future;
    api.loadAlbums = () => albums.future;
    await _pumpDiscover(tester, api, settle: false);

    daily.completeError(StateError('daily offline'));
    await tester.pump();
    await tester.pump();

    expect(find.text('重试每日推荐'), findsOneWidget);
    expect(find.byType(GSkeleton), findsWidgets);
    albums.complete(api.albums);
    await tester.pumpAndSettle();
    expect(find.text('测试新专辑').hitTestable(), findsOneWidget);

    final retry = Completer<List<Song>>();
    api.loadDaily = () => retry.future;
    await tester.tap(find.text('重试每日推荐'));
    await tester.tap(find.text('重试每日推荐'));
    await tester.pump();

    expect(api.dailyRequests, 2);
    expect(api.albumRequests, 1);
    expect(find.text('测试新专辑').hitTestable(), findsOneWidget);
    expect(find.byType(GSkeletonList), findsOneWidget);
    retry.complete(api.daily);
    await tester.pumpAndSettle();

    expect(find.byTooltip('播放每日推荐'), findsOneWidget);
    expect(find.text('重试每日推荐'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('album failure preserves daily music and retries only albums',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    final albums = Completer<List<Album>>();
    api.loadAlbums = () => albums.future;
    await _pumpDiscover(tester, api, settle: false);
    albums.completeError(StateError('albums offline'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('播放每日推荐').hitTestable(), findsOneWidget);
    expect(find.text('每日歌曲'), findsNWidgets(2));
    expect(find.text('重试最新专辑'), findsOneWidget);

    final retry = Completer<List<Album>>();
    api.loadAlbums = () => retry.future;
    await tester.tap(find.text('重试最新专辑'));
    await tester.pump();

    expect(api.dailyRequests, 1);
    expect(api.albumRequests, 2);
    expect(find.byTooltip('播放每日推荐').hitTestable(), findsOneWidget);
    retry.complete(api.albums);
    await tester.pumpAndSettle();

    expect(find.text('测试新专辑'), findsOneWidget);
    expect(find.text('重试最新专辑'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh reuses each in-flight initial request', (tester) async {
    final api = _FakeDiscoverMusicApi();
    final daily = Completer<List<Song>>();
    final albums = Completer<List<Album>>();
    api.loadDaily = () => daily.future;
    api.loadAlbums = () => albums.future;
    await _pumpDiscover(tester, api, settle: false);
    final onRefresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh;

    final firstRefresh = onRefresh();
    final secondRefresh = onRefresh();
    await tester.pump();
    expect(api.dailyRequests, 1);
    expect(api.albumRequests, 1);

    daily.complete(api.daily);
    albums.complete(api.albums);
    await Future.wait([firstRefresh, secondRefresh]);
    await tester.pumpAndSettle();

    expect(find.text('测试新专辑'), findsOneWidget);
    expect(find.byTooltip('播放每日推荐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh updates a completed section while retaining the other',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    await _pumpDiscover(tester, api);
    final daily = Completer<List<Song>>();
    final albums = Completer<List<Album>>();
    api.loadDaily = () => daily.future;
    api.loadAlbums = () => albums.future;
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();

    albums.complete([const Album(id: 77, name: '刚刚更新的专辑')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('刚刚更新的专辑').hitTestable(), findsOneWidget);
    expect(find.text('每日歌曲'), findsNWidgets(2));
    expect(find.byType(GSkeleton), findsNothing);

    daily.complete([_testSong(0)]);
    await refresh;
    await tester.pumpAndSettle();

    expect(find.text('推荐歌曲 2'), findsNWidgets(2));
    expect(find.text('刚刚更新的专辑'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('desktop latest albums provide previous and next controls',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    await _pumpDiscover(tester, api);

    final albumList = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.horizontal,
    );
    final scrollable = find.descendant(
      of: albumList,
      matching: find.byType(Scrollable),
    );
    expect(find.byTooltip('上一组专辑'), findsOneWidget);
    expect(find.byTooltip('下一组专辑'), findsOneWidget);
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);

    await tester.tap(find.byTooltip('下一组专辑'));
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow desktop windows keep latest album controls',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    await _pumpDiscover(
      tester,
      api,
      size: const Size(620, 700),
      platform: TargetPlatform.macOS,
    );

    expect(find.byTooltip('上一组专辑'), findsOneWidget);
    expect(find.byTooltip('下一组专辑'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile featured music leaves albums visible in the first screen',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    await _pumpDiscover(
      tester,
      api,
      size: const Size(390, 720),
      platform: TargetPlatform.android,
    );

    // The featured artwork is now the primary surface; the complete first
    // album and its label must still fit before the playback/navigation area.
    expect(
        tester.getBottomRight(find.text('测试新专辑')).dy, lessThanOrEqualTo(640));
    expect(find.byTooltip('播放每日推荐'), findsOneWidget);
    expect(find.text('测试新专辑').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh keeps content interactive and preserves scroll position',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    api.daily.addAll(List.generate(20, _testSong));
    await _pumpDiscover(
      tester,
      api,
      size: const Size(390, 720),
      platform: TargetPlatform.android,
    );
    final scrollable = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(150);
    await tester.pumpAndSettle();
    final scrollOffset = position.pixels;
    final albumTop = tester.getTopLeft(find.text('测试新专辑')).dy;
    final daily = Completer<List<Song>>();
    final albums = Completer<List<Album>>();
    api.loadDaily = () => daily.future;
    api.loadAlbums = () => albums.future;

    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();

    expect(find.byType(GSkeleton), findsNothing);
    expect(find.text('测试新专辑').hitTestable(), findsOneWidget);
    expect(position.pixels, scrollOffset);
    expect(tester.getTopLeft(find.text('测试新专辑')).dy, albumTop);

    await tester.tap(find.text('测试新专辑'));
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistDetailView), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    daily.complete(api.daily);
    albums.complete(api.albums);
    await refresh;
    await tester.pumpAndSettle();

    expect(position.pixels, scrollOffset);
    expect(api.dailyRequests, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed refresh retains music and retries only its section',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    await _pumpDiscover(tester, api);
    final daily = Completer<List<Song>>();
    api.loadDaily = () => daily.future;
    final errors = <Object>[];
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    final handledRefresh = refresh.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) => errors.add(error),
    );
    await tester.pump();

    daily.completeError(StateError('offline'));
    await handledRefresh;
    await tester.pumpAndSettle();

    expect(errors, isEmpty);
    expect(find.text('测试新专辑'), findsOneWidget);
    expect(find.text('每日歌曲'), findsNWidgets(2));
    expect(find.text('重试每日推荐'), findsOneWidget);

    api.loadDaily = null;
    await tester.tap(find.text('重试每日推荐'));
    await tester.pumpAndSettle();

    expect(api.dailyRequests, 3);
    expect(api.albumRequests, 2);
    expect(find.text('测试新专辑'), findsOneWidget);
    expect(find.text('重试每日推荐'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first load reserves the same featured and album layout',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    final daily = Completer<List<Song>>();
    api.loadDaily = () => daily.future;
    await _pumpDiscover(
      tester,
      api,
      size: const Size(390, 720),
      platform: TargetPlatform.android,
      settle: false,
    );

    expect(find.byType(GSkeleton), findsWidgets);
    expect(find.text('最新专辑'), findsOneWidget);
    final loadingAlbumTop = tester.getTopLeft(find.text('最新专辑')).dy;

    daily.complete(api.daily);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('最新专辑')).dy, loadingAlbumTop);
    expect(find.byType(GSkeleton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short content still responds to pull to refresh',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    api.daily.clear();
    api.albums.clear();
    await _pumpDiscover(
      tester,
      api,
      size: const Size(390, 1200),
      platform: TargetPlatform.android,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
    await tester.pumpAndSettle();

    expect(api.dailyRequests, 2);
    expect(api.albumRequests, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small Android screen supports large text without overflowing',
      (tester) async {
    final api = _FakeDiscoverMusicApi();
    await _pumpDiscover(
      tester,
      api,
      size: const Size(320, 740),
      platform: TargetPlatform.android,
      textScale: 2,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -360));
    await tester.pumpAndSettle();

    expect(find.text('测试新专辑').hitTestable(), findsOneWidget);
  });
}

Future<void> _pumpDiscover(
  WidgetTester tester,
  _FakeDiscoverMusicApi api, {
  Size size = const Size(1000, 1000),
  TargetPlatform platform = TargetPlatform.macOS,
  double textScale = 1,
  bool settle = true,
}) async {
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
  tester.view.physicalSize = size;

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<AuthController>.value(value: auth),
      ],
      child: MaterialApp(
        theme: AppTheme.byId('light').data.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: DiscoverView(api: api),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

class _FakeDiscoverMusicApi extends MusicApi {
  final albumDetailRequests = <(String, String)>[];
  Future<List<Song>> Function()? loadDaily;
  Future<List<Album>> Function()? loadAlbums;
  int dailyRequests = 0;
  int albumRequests = 0;

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

  final albums = [
    const Album(
      id: 42,
      sourceId: '0035Y3b01o1BsG',
      name: '测试新专辑',
    ),
    const Album(id: 43, name: '测试新专辑 2'),
    const Album(id: 44, name: '测试新专辑 3'),
    const Album(id: 45, name: '测试新专辑 4'),
    const Album(id: 46, name: '测试新专辑 5'),
    const Album(id: 47, name: '测试新专辑 6'),
    const Album(id: 48, name: '测试新专辑 7'),
    const Album(id: 49, name: '测试新专辑 8'),
  ];

  @override
  Future<List<Song>> getDailyRecommend({String source = 'netease'}) async {
    dailyRequests++;
    if (loadDaily != null) return loadDaily!();
    return daily;
  }

  @override
  Future<List<Album>> getNewestAlbums({String source = 'netease'}) async {
    albumRequests++;
    if (loadAlbums != null) return loadAlbums!();
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

Song _testSong(int index) => Song(
      id: 'daily-${index + 2}',
      name: '推荐歌曲 ${index + 2}',
      source: 'qq',
      artists: const [Artist(id: 7, name: '每日歌手')],
      album: const Album(id: 8, name: '每日专辑'),
      durationMs: 180000,
    );
