import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/models/artist_info.dart';
import 'package:duck_music/core/api/artist_info_api.dart';
import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/models/membership.dart';
import 'package:duck_music/core/models/playlist.dart';
import 'package:duck_music/app.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duck_music/core/player/lrc_parser.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:duck_music/core/services/app_update_service.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/player/mini_player.dart';
import 'package:duck_music/features/player/player_view.dart';
import 'package:duck_music/features/home/home_shell.dart';
import 'package:duck_music/features/profile/profile_view.dart';
import 'package:duck_music/features/profile/login_view.dart';
import 'package:duck_music/features/profile/user_library_view.dart';
import 'package:duck_music/features/search/search_view.dart';
import 'package:duck_music/features/search/artist_detail_view.dart';
import 'package:duck_music/features/search/artist_names_link.dart';
import 'package:duck_music/features/playlists/playlists_view.dart';
import 'package:duck_music/features/discover/discover_view.dart';
import 'package:duck_music/features/tools/tools_view.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void _noop() {}

void main() {
  test('update service selects only the current platform asset', () {
    final assets = [
      {
        'name': 'duck-music-android.apk',
        'browser_download_url': 'https://example.com/app.apk',
      },
      {
        'name': 'duck-music-android-universal.apk',
        'browser_download_url': 'https://example.com/universal.apk',
      },
      {
        'name': 'duck-music-macos.dmg',
        'browser_download_url': 'https://example.com/app.dmg',
      },
      {
        'name': 'duck-music-windows.exe',
        'browser_download_url': 'https://example.com/app.exe',
      },
      {
        'name': 'duck-music-windows.zip',
        'browser_download_url': 'https://example.com/windows.zip',
      },
    ];

    expect(
      AppUpdateService.selectAssetUrl(assets, UpdateTarget.android),
      'https://example.com/universal.apk',
    );
    expect(
      AppUpdateService.selectAssetUrl(assets, UpdateTarget.macos),
      'https://example.com/app.dmg',
    );
    expect(
      AppUpdateService.selectAssetUrl(assets, UpdateTarget.windows),
      'https://example.com/app.exe',
    );
    expect(
      AppUpdateService.selectAssetUrl(assets, UpdateTarget.ios),
      isNull,
    );
    expect(
      AppUpdateService.selectAssetUrl(
        [assets.last],
        UpdateTarget.macos,
      ),
      isNull,
    );
    expect(
      AppUpdateService.selectAssetUrl(
        assets,
        UpdateTarget.android,
        requiredNamePrefix: 'DuckMusic-Flutter-',
      ),
      isNull,
    );
    expect(
      AppUpdateService.selectAssetUrl(
        [
          {
            'name': 'duck-music-macos-arm64.dmg',
            'browser_download_url': 'https://example.com/arm64.dmg',
          },
          {
            'name': 'duck-music-macos-x64.dmg',
            'browser_download_url': 'https://example.com/x64.dmg',
          },
        ],
        UpdateTarget.macos,
        architecture: 'macosArm64',
      ),
      'https://example.com/arm64.dmg',
    );
  });

  test('update service distinguishes available, current, and failed checks',
      () async {
    final client = MockClient((request) async => http.Response(
          '''[{
            "tag_name": "v9.0.0",
            "html_url": "https://example.com/native-release",
            "assets": []
          }, {
            "tag_name": "flutter-v1.2.0",
            "html_url": "https://example.com/release",
            "draft": false,
            "prerelease": false,
            "assets": [{
              "name": "DuckMusic-Flutter-v1.2.0-Android-universal.apk",
              "browser_download_url": "https://example.com/app.apk"
            }]
          }]''',
          200,
        ));
    final service = AppUpdateService(client: client);

    final available = await service.checkLatest(
      currentVersion: '1.1.0',
      target: UpdateTarget.android,
    );
    final current = await service.checkLatest(
      currentVersion: '1.2.0',
      target: UpdateTarget.android,
    );
    final failed = await AppUpdateService(
      client: MockClient((request) async => http.Response('', 503)),
    ).checkLatest(target: UpdateTarget.android);

    expect(available.status, UpdateCheckStatus.updateAvailable);
    expect(available.release?.assetUrl, 'https://example.com/app.apk');
    expect(current.status, UpdateCheckStatus.upToDate);
    expect(failed.status, UpdateCheckStatus.failed);
  });

  test('iOS update check uses the App Store version and destination', () async {
    final service = AppUpdateService(
      client: MockClient((request) async {
        expect(request.url.host, 'itunes.apple.com');
        expect(request.url.queryParameters['id'], '123456789');
        return http.Response(
          '''{
            "resultCount": 1,
            "results": [{
              "version": "1.3.0",
              "trackViewUrl": "https://apps.apple.com/app/id123456789"
            }]
          }''',
          200,
        );
      }),
    );

    final result = await service.checkLatest(
      currentVersion: '1.2.0',
      target: UpdateTarget.ios,
      iosAppStoreId: '123456789',
    );

    expect(result.status, UpdateCheckStatus.updateAvailable);
    expect(result.release?.version, '1.3.0');
    expect(
      result.release?.releasePageUrl,
      'https://apps.apple.com/app/id123456789',
    );
    expect(result.release?.assetUrl, isNull);
  });

  test('update version comparison handles prefixes and build components', () {
    expect(AppUpdateService.isNewer('v1.10.0', '1.9.9'), isTrue);
    expect(AppUpdateService.isNewer('1.0.0', 'v1.0.0'), isFalse);
    expect(AppUpdateService.isNewer('1.0.0.2', '1.0.0.1'), isTrue);
  });

  test('parseLrc parses timestamps and sorts', () {
    final lines = parseLrc(
      '[00:01.50]\u7b2c\u4e00\u53e5\n'
      '[00:00.20]\u7b2c\u4e8c\u53e5\n'
      '[00:03]\u7b2c\u4e09\u53e5\n',
    );
    expect(lines.length, 3);
    expect(lines.first.text, '\u7b2c\u4e8c\u53e5');
    expect(lines.first.time.inMilliseconds, 200);
    expect(lines[1].time.inMilliseconds, 1500);
    expect(lines[2].time.inSeconds, 3);
  });

  test('parseLrc returns empty list for empty input', () {
    expect(parseLrc(''), isEmpty);
  });

  test('membership parses redeem response fields', () {
    final membership = Membership.fromJson({
      'type': 'MONTH',
      'typeName': '月卡',
      'active': true,
      'lifetime': false,
      'expiresAt': '2026-09-04T12:00:00',
      'remainingSeconds': 2678400,
    });
    expect(membership.type, 'MONTH');
    expect(membership.typeName, '月卡');
    expect(membership.active, isTrue);
    expect(membership.expiresAt, isNotNull);
  });

  test('music models tolerate numeric ids and non-string text', () {
    final song = Song.fromV1({
      'id': 123456,
      'name': 2026,
      'artist': '歌手甲 / 歌手乙',
      'albumId': 98,
      'album': '测试专辑',
      'coverUrl': Uri.parse('https://example.com/cover.jpg'),
      'durationSec': 180,
    });
    final playlist = Playlist.fromV1({
      'id': 654321,
      'name': 2026,
      'creatorName': 751152,
    });
    final userSong = itemToSong({
      'songId': 42,
      'songName': 2026,
      'artist': 751152,
      'source': 'netease',
    });

    expect(song.id, '123456');
    expect(song.name, '2026');
    expect(song.album.id, 98);
    expect(playlist.id, 654321);
    expect(playlist.name, '2026');
    expect(userSong.id, '42');
    expect(userSong.name, '2026');
  });

  test('library songs split multiple artists for individual profiles', () {
    final song = itemToSong({
      'songId': 42,
      'songName': '合唱歌曲',
      'artist': '歌手甲 / 歌手乙, 歌手丙',
    });

    expect(song.artists.map((artist) => artist.name), ['歌手甲', '歌手乙', '歌手丙']);
  });

  test('artist info parses profile and upgrades image URL to HTTPS', () {
    final info = ArtistInfo.fromJson({
      'name': '王俊凯',
      'imgurl': 'http://singerimg.kugou.com/avatar.jpg',
      'profile': ' 歌手简介 ',
    });

    expect(info.name, '王俊凯');
    expect(info.imageUrl, 'https://singerimg.kugou.com/avatar.jpg');
    expect(info.profile, '歌手简介');
  });

  test('artist info API sends the artist name and parses its response',
      () async {
    final api = ArtistInfoApi(
      client: MockClient((request) async {
        expect(request.url.queryParameters['type'], 'json');
        expect(request.url.queryParameters['msg'], '王俊凯');
        return http.Response(
          '{"code":200,"data":{"name":"王俊凯",'
          '"imgurl":"http://example.com/avatar.jpg",'
          '"profile":"歌手简介"}}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final info = await api.getArtistInfo(' 王俊凯 ');
    expect(info.name, '王俊凯');
    expect(info.imageUrl, 'https://example.com/avatar.jpg');
    expect(info.profile, '歌手简介');
  });

  test('artist catalog keeps exact artist songs and groups albums', () {
    final catalog = ArtistCatalog.fromSongs(
      artistName: '歌手甲',
      searchedSongs: [
        _song('1', '歌曲一', artists: ['歌手甲'], albumId: 8, album: '专辑 A'),
        _song('2', '歌曲二', artists: ['歌手甲', '歌手乙'], albumId: 8, album: '专辑 A'),
        _song('3', '歌手甲的故事', artists: ['其他歌手'], albumId: 9, album: '专辑 B'),
      ],
    );

    expect(catalog.songs.map((song) => song.id), ['1', '2']);
    expect(catalog.albums, hasLength(1));
    expect(catalog.albums.single.album.name, '专辑 A');
    expect(catalog.albums.single.songs, hasLength(2));
  });

  testWidgets('artist detail renders loaded information', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.byId('dark').data,
        home: ArtistDetailView(
          artistName: '王俊凯',
          loader: () async => const ArtistInfo(
            name: '王俊凯',
            profile: '测试歌手简介',
          ),
          catalogLoader: () async => _artistCatalog(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('歌手'), findsOneWidget);
    expect(find.text('王俊凯'), findsWidgets);
    expect(find.text('歌手简介'), findsOneWidget);
    expect(find.text('测试歌手简介'), findsOneWidget);
    expect(find.text('歌曲 1'), findsOneWidget);
    expect(find.text('专辑 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('歌曲 1'));
    await tester.pump();
    expect(find.text('全部歌曲'), findsOneWidget);

    await tester.tap(find.text('专辑 1'));
    await tester.pump();
    expect(find.text('全部专辑'), findsOneWidget);
  });

  testWidgets('artist link opens profile without triggering its parent',
      (tester) async {
    var parentTapped = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.byId('dark').data,
        home: Scaffold(
          body: GPressScale(
            onTap: () => parentTapped = true,
            child: ArtistNamesLink(
              artists: const [Artist(id: 1, name: '王俊凯')],
              loader: () async => const ArtistInfo(
                name: '王俊凯',
                profile: '测试歌手简介',
              ),
              catalogLoader: () async => _emptyArtistCatalog(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('王俊凯'));
    await tester.pumpAndSettle();

    expect(parentTapped, isFalse);
    expect(find.text('歌手'), findsOneWidget);
    expect(find.text('测试歌手简介'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('artist link asks which profile to open for collaborations',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.byId('dark').data,
        home: Scaffold(
          body: ArtistNamesLink(
            artists: const [
              Artist(id: 1, name: '歌手甲'),
              Artist(id: 2, name: '歌手乙'),
            ],
            loader: () async => const ArtistInfo(
              name: '歌手乙',
              profile: '歌手乙简介',
            ),
            catalogLoader: () async => _emptyArtistCatalog(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('歌手甲 / 歌手乙'));
    await tester.pumpAndSettle();
    expect(find.text('选择歌手'), findsOneWidget);

    await tester.tap(find.text('歌手乙'));
    await tester.pumpAndSettle();
    expect(find.text('歌手'), findsOneWidget);
    expect(find.text('歌手乙简介'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first launch waits for auth and opens login', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final auth = AuthController();
    addTearDown(auth.dispose);
    await auth.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthController>.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.byId('dark').data,
          home: const AuthGate(),
        ),
      ),
    );

    expect(auth.initialized, isTrue);
    expect(find.byType(LoginView), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    expect(find.text('没有账号？去注册'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('没有账号？去注册'));
    await tester.pump();
    expect(find.text('邮箱'), findsOneWidget);
    expect(find.text('注册并登录'), findsOneWidget);
    expect(find.text('已有账号？去登录'), findsOneWidget);
  });

  testWidgets('mini player fits desktop and compact widths', (tester) async {
    final player = _PreviewPlayerController();
    addTearDown(player.dispose);

    Future<void> pumpAt(Size size, {double? sidebarWidth}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ChangeNotifierProvider<PlayerController>.value(
          value: player,
          child: MaterialApp(
            theme: AppTheme.byId('dark').data.copyWith(
                  platform: size.width < 600
                      ? TargetPlatform.iOS
                      : TargetPlatform.macOS,
                ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: MiniPlayer(sidebarWidth: sidebarWidth),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await pumpAt(const Size(1280, 720), sidebarWidth: 280);
    await pumpAt(const Size(760, 600), sidebarWidth: 232);
    await pumpAt(const Size(390, 844));
  });

  testWidgets('iOS app bar respects safe area and 44pt touch targets',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.byId('dark').data.copyWith(
              platform: TargetPlatform.iOS,
            ),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: Scaffold(
            body: GAppBar(title: '详情', onBack: _noop),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(GAppBar)).height,
      inInclusiveRange(103, 104),
    );
    expect(tester.getSize(find.byType(GIconButton)).shortestSide, 44);
    expect(tester.getCenter(find.text('详情')).dx, closeTo(195, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('player and embedded profile fit desktop layout', (tester) async {
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);

    Widget app(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerController>.value(value: player),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
            ChangeNotifierProvider<AuthController>.value(value: auth),
            ChangeNotifierProvider<SleepTimer>.value(value: timer),
          ],
          child: MaterialApp(
            theme: AppTheme.byId('dark').data,
            home: child,
          ),
        );

    await tester.pumpWidget(app(const PlayerView()));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(app(const ProfileView(embedded: true)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS player opens as an immersive lyric screen', (tester) async {
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SleepTimer>.value(value: timer),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('light').data.copyWith(
                platform: TargetPlatform.iOS,
              ),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 47, bottom: 34),
            ),
            child: PlayerView(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('穿过人海只为与你相见'), findsOneWidget);
    expect(find.byTooltip('收起播放器'), findsOneWidget);
    expect(find.byTooltip('切换到唱片'), findsOneWidget);
    expect(find.byIcon(Icons.album_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('切换到唱片'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('切换到歌词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary content pages render at desktop and compact widths',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    tester.view.devicePixelRatio = 1;

    Widget app(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerController>.value(value: player),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
          ],
          child: MaterialApp(
            theme: AppTheme.byId('dark').data,
            home: child,
          ),
        );

    for (final size in const [Size(1280, 800), Size(430, 760)]) {
      tester.view.physicalSize = size;
      for (final page in const <Widget>[
        SearchView(),
        PlaylistsView(),
        DiscoverView(),
        ToolsView(),
      ]) {
        await tester.pumpWidget(app(page));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: '${page.runtimeType} failed at $size');
      }
    }
  });

  testWidgets('secondary content routes keep shell and mini player visible',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SleepTimer>.value(value: timer),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('dark').data,
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();

    final navLabels = ['首页', '发现', '搜索', '资料库', '我的'];
    final labelCenters = [
      for (final label in navLabels) tester.getCenter(find.text(label).last).dx,
    ];
    expect(labelCenters, orderedEquals([...labelCenters]..sort()));

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('工具箱'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('工具箱').last);
    await tester.pumpAndSettle();
    expect(find.text('工具箱'), findsOneWidget);

    await tester.tap(find.text('AI 绘画'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Song _song(
  String id,
  String name, {
  required List<String> artists,
  required int albumId,
  required String album,
}) {
  return Song(
    id: id,
    name: name,
    source: 'netease',
    artists: [
      for (var index = 0; index < artists.length; index++)
        Artist(id: index + 1, name: artists[index]),
    ],
    album: Album(id: albumId, name: album),
    durationMs: 180000,
  );
}

ArtistCatalog _artistCatalog() {
  final song = _song(
    'artist-song',
    '测试歌曲',
    artists: ['王俊凯'],
    albumId: 1,
    album: '测试专辑',
  );
  return ArtistCatalog(
    songs: [song],
    albums: [
      ArtistAlbum(album: song.album, songs: [song]),
    ],
  );
}

ArtistCatalog _emptyArtistCatalog() =>
    const ArtistCatalog(songs: [], albums: []);

class _PreviewPlayerController extends PlayerController {
  _PreviewPlayerController() : super(settings: SettingsController());

  final Song _song = Song(
    id: 'preview',
    name: 'The Gentlemen (Live)',
    source: 'netease',
    artists: const [
      Artist(id: 1, name: '弹壳Danko'),
      Artist(id: 2, name: 'Vinz-T')
    ],
    album: const Album(id: 1, name: '现场', picUrl: null),
    durationMs: 207000,
  );

  @override
  Song get current => _song;

  @override
  bool get loading => false;

  @override
  bool get playing => false;

  @override
  bool get liked => false;

  @override
  Duration get position => const Duration(minutes: 2, seconds: 50);

  @override
  Duration? get duration => const Duration(minutes: 3, seconds: 27);

  @override
  String get lyric => '''
[02:24.00]夜色落在城市的屋檐
[02:32.00]我们走过熟悉的街
[02:40.00]所有故事都在此刻沉淀
[02:49.00]穿过人海只为与你相见
[02:57.00]让晚风把心事轻轻吹远
[03:05.00]明天依然会有新的画面
[03:13.00]当音乐停下我们也不说再见
''';

  @override
  double get volume => 0.7;
}
