import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/models/artist_info.dart';
import 'package:duck_music/core/api/artist_info_api.dart';
import 'package:duck_music/core/api/auth_api.dart';
import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/api/user_api.dart';
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
import 'package:duck_music/features/player/desktop_player_panel.dart';
import 'package:duck_music/features/player/mini_player.dart';
import 'package:duck_music/features/player/player_view.dart';
import 'package:duck_music/features/home/home_shell.dart';
import 'package:duck_music/features/profile/profile_view.dart';
import 'package:duck_music/features/profile/login_view.dart';
import 'package:duck_music/features/profile/legal_document_view.dart';
import 'package:duck_music/features/profile/user_library_view.dart';
import 'package:duck_music/features/search/search_view.dart';
import 'package:duck_music/features/search/artist_detail_view.dart';
import 'package:duck_music/features/search/artist_names_link.dart';
import 'package:duck_music/features/playlists/playlists_view.dart';
import 'package:duck_music/features/playlists/playlist_detail_view.dart';
import 'package:duck_music/features/discover/discover_view.dart';
import 'package:duck_music/features/settings/settings_components.dart';
import 'package:duck_music/features/tools/tools_view.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:duck_music/widgets/async_cover.dart';
import 'package:duck_music/widgets/song_row.dart';
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

  testWidgets('artist detail loads subsequent catalog pages', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    final firstSong = _song(
      '1',
      '第一页歌曲',
      artists: ['歌手甲'],
      albumId: 8,
      album: '专辑 A',
    );
    final secondSong = _song(
      '2',
      '第二页歌曲',
      artists: ['歌手甲'],
      albumId: 9,
      album: '专辑 B',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.byId('dark').data,
        home: ArtistDetailView(
          artistName: '歌手甲',
          loader: () async => const ArtistInfo(
            name: '歌手甲',
            profile: '简介',
          ),
          catalogLoader: () async => ArtistCatalog.fromSongs(
            artistName: '歌手甲',
            searchedSongs: [firstSong],
            hasMore: true,
            nextOffset: 30,
          ),
          catalogPageLoader: (offset) async {
            expect(offset, 30);
            return ArtistCatalog.fromSongs(
              artistName: '歌手甲',
              searchedSongs: [secondSong],
              nextOffset: 31,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌曲 1+'));
    await tester.pumpAndSettle();
    expect(find.text('歌曲 2'), findsOneWidget);
    expect(find.text('第一页歌曲'), findsOneWidget);
    expect(find.text('第二页歌曲'), findsOneWidget);
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
    expect(find.text('柒伍壹壹音乐'), findsOneWidget);
    expect(find.text('继续聆听'), findsOneWidget);
    expect(find.text('已阅读并同意用户协议与隐私政策'), findsOneWidget);
    expect(find.text('忘记密码'), findsOneWidget);
    expect(find.text('创建账号'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
    expect(tester.takeException(), isNull);

    final passwordField = tester.widget<TextField>(find.byType(TextField).last);
    expect(passwordField.obscureText, isTrue);
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isFalse,
    );

    await tester.tap(find.text('创建账号'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterView), findsOneWidget);
    expect(find.text('昵称'), findsOneWidget);
    expect(find.text('邮箱'), findsOneWidget);
    expect(find.text('创建账号'), findsWidgets);
    expect(find.text('已经有账号？'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
  });

  testWidgets('login legal and password recovery routes are functional',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final auth = AuthController();
    addTearDown(auth.dispose);
    final resetApi = _FakePasswordResetApi();

    Widget app(Widget home) => ChangeNotifierProvider<AuthController>.value(
          value: auth,
          child: MaterialApp(
            key: ValueKey(home.runtimeType),
            theme: AppTheme.byId('dark').data,
            home: home,
          ),
        );

    await tester.pumpWidget(app(const LoginView(allowBack: false)));
    await tester.tap(find.text('查看用户协议'));
    await tester.pumpAndSettle();
    expect(find.byType(LegalDocumentView), findsOneWidget);
    expect(find.text('用户协议'), findsWidgets);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看隐私政策'));
    await tester.pumpAndSettle();
    expect(find.text('隐私政策'), findsWidgets);

    await tester.pumpWidget(app(ForgotPasswordView(api: resetApi)));
    await tester.enterText(
      find.byType(TextField).at(0),
      'listener@751152.xyz',
    );
    await tester.tap(find.text('获取验证码'));
    await tester.pump();
    expect(resetApi.email, 'listener@751152.xyz');
    expect(find.text('2 秒后重发'), findsOneWidget);
    expect(find.text('验证码已发送，10 分钟内有效'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1 秒后重发'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.enterText(find.byType(TextField).at(2), 'new-secret');
    await tester.enterText(find.byType(TextField).at(3), 'new-secret');
    await tester.tap(find.text('重置密码'));
    await tester.pump();
    await tester.pump();
    expect(resetApi.confirmedEmail, 'listener@751152.xyz');
    expect(resetApi.verificationCode, '123456');
    expect(resetApi.newPassword, 'new-secret');
    expect(find.text('密码已重置，请使用新密码登录'), findsOneWidget);
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

  testWidgets('desktop mini player toggles functional lyrics and queue panels',
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
    tester.view.physicalSize = const Size(1280, 720);

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
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('歌词'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopPlayerPanel), findsOneWidget);
    expect(tester.getTopRight(find.byType(DesktopPlayerPanel)).dx, 1280);
    expect(find.text('穿过人海只为与你相见'), findsOneWidget);

    await tester.tap(find.byTooltip('播放队列'));
    await tester.pumpAndSettle();
    expect(find.text('接下来播放'), findsOneWidget);
    expect(find.text('顺序播放'), findsOneWidget);
    expect(find.text('不循环'), findsOneWidget);
    expect(find.text('2 首'), findsOneWidget);

    await tester.tap(find.byTooltip('更多：测试下一首'));
    await tester.pumpAndSettle();
    for (final action in const ['播放', '下一首播放', '喜欢', '收藏到歌单', '下载']) {
      expect(find.text(action), findsOneWidget);
    }
    await tester.tap(find.text('下一首播放'));
    await tester.pumpAndSettle();
    expect(player.movedToNextIndex, 1);
    expect(find.text('已设为下一首播放'), findsOneWidget);

    await tester.tap(find.byTooltip('更多：测试下一首'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('喜欢'));
    await tester.pumpAndSettle();
    expect(find.text('请先登录后再喜欢歌曲'), findsOneWidget);

    await tester.tap(find.text('顺序播放'));
    await tester.pump();
    expect(find.text('随机播放'), findsOneWidget);
    await tester.tap(find.text('不循环'));
    await tester.pump();
    expect(find.text('列表循环'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭播放队列'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(DesktopPlayerPanel)).dx, 1304);
    expect(tester.takeException(), isNull);
  });

  testWidgets('song rows expose the complete shared action menu',
      (tester) async {
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('dark').data,
          home: Scaffold(body: SongRow(song: player.current)),
        ),
      ),
    );

    expect(find.byTooltip('更多：The Gentlemen (Live)'), findsOneWidget);
    await tester.tap(find.byTooltip('更多：The Gentlemen (Live)'));
    await tester.pumpAndSettle();
    for (final action in const ['播放', '下一首播放', '喜欢', '收藏到歌单', '下载']) {
      expect(find.text(action), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop playlist uses compact layout and anchored song actions',
      (tester) async {
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 760);

    final songs = [
      _song(
        'playlist-song-1',
        '想去海边',
        artists: ['音乐怪人'],
        albumId: 11,
        album: '夏日歌集',
      ),
      _song(
        'playlist-song-2',
        '无期',
        artists: ['音乐怪人'],
        albumId: 12,
        album: '夜晚歌集',
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('light').data.copyWith(
                platform: TargetPlatform.macOS,
              ),
          home: PlaylistDetailView(
            playlist: Playlist(
              id: 7511,
              name: '予你情诗百首，余生你是我的所有',
              creatorName: '音乐怪人',
              description:
                  'Without you\nHowever beautiful the city is\nIt is just null',
            ),
            loader: () async => songs,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final playlistCover = find.byWidgetPredicate(
      (widget) => widget is AsyncCover && widget.size == 200,
    );
    expect(playlistCover, findsOneWidget);
    expect(tester.getSize(playlistCover), const Size.square(200));
    expect(tester.getSize(find.text('全部播放')).height, lessThan(32));
    expect(find.text('展开全部'), findsOneWidget);

    await tester.tap(find.text('展开全部'));
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);

    await tester.tap(find.byTooltip('更多：想去海边'));
    await tester.pumpAndSettle();
    for (final action in const ['播放', '下一首播放', '喜欢', '收藏到歌单', '下载']) {
      expect(find.text(action), findsOneWidget);
    }
    expect(tester.getTopLeft(find.text('播放')).dx, greaterThan(700));

    await tester.tap(find.text('下一首播放'));
    await tester.pump();
    expect(player.playedNext?.id, 'playlist-song-1');
    expect(find.text('已设为下一首播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('playlist favorite uses online favorite endpoints',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'playlist-token',
      'auth_username': '测试用户',
    });
    final auth = AuthController(api: _PlaylistAuthApi());
    await auth.load();
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final userApi = _FakePlaylistUserApi();
    addTearDown(auth.dispose);
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 760);

    final playlist = Playlist(
      id: 123456,
      name: '线上收藏测试歌单',
      source: 'netease',
      description: '用于验证线上歌单收藏',
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('light').data.copyWith(
                platform: TargetPlatform.macOS,
              ),
          home: PlaylistDetailView(
            playlist: playlist,
            userApi: userApi,
            loader: () async => [
              _song(
                'favorite-song',
                '收藏歌曲',
                artists: ['测试歌手'],
                albumId: 1,
                album: '测试专辑',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('收藏歌单'));
    await tester.pumpAndSettle();
    expect(userApi.addedSource, 'netease');
    expect(userApi.addedPlaylistId, '123456');
    expect(userApi.addedToken, 'playlist-token');
    expect(find.byTooltip('取消收藏'), findsOneWidget);
    expect(find.text('歌单已收藏'), findsOneWidget);

    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pumpAndSettle();
    expect(userApi.removedSource, 'netease');
    expect(userApi.removedPlaylistId, '123456');
    expect(userApi.removedToken, 'playlist-token');
    expect(find.byTooltip('收藏歌单'), findsOneWidget);
    expect(find.text('已取消收藏'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('macOS headers avoid window controls only in full-window content',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    final theme = AppTheme.byId('light').data.copyWith(
          platform: TargetPlatform.macOS,
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GAppBar(title: '登录', onBack: _noop),
              GPageHeader(title: '首页'),
            ],
          ),
        ),
      ),
    );

    expect(
        tester.getTopLeft(find.byTooltip('返回')).dx, greaterThanOrEqualTo(80));
    expect(tester.getTopLeft(find.text('首页')).dx, greaterThanOrEqualTo(96));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: GWindowControlsSafeRegion(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GAppBar(title: '设置', onBack: _noop),
                GPageHeader(title: '搜索'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byTooltip('返回')).dx, lessThan(20));
    expect(tester.getTopLeft(find.text('搜索')).dx, closeTo(24, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS shell drag region stays inside the sidebar',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('light').data.copyWith(
                platform: TargetPlatform.macOS,
              ),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();

    final dragRegion = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_WindowDragBar',
    );
    expect(dragRegion, findsOneWidget);
    expect(tester.getRect(dragRegion).right, lessThanOrEqualTo(280));

    await tester.tap(find.text('我的'));
    await tester.pump();
    final profileTitle = find.descendant(
      of: find.byType(ProfileView),
      matching: find.text('我的'),
    );
    expect(profileTitle, findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);

    await tester.tap(find.text('首页'));
    await tester.pump();
    expect(profileTitle, findsNothing);
    expect(find.text('首页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop search controls accept clicks across visible bounds',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('light').data.copyWith(
                platform: TargetPlatform.macOS,
              ),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();

    final searchControl = find.byKey(const ValueKey('sidebar_search_control'));
    expect(tester.getSize(searchControl).height, 40);
    final searchRect = tester.getRect(searchControl);
    await tester.tapAt(Offset(searchRect.left + 1, searchRect.center.dy));
    await tester.pump();
    expect(find.byType(SearchView), findsOneWidget);

    final qqSource = find.byKey(const ValueKey('search_source_qq'));
    expect(tester.getSize(qqSource).height, greaterThanOrEqualTo(40));
    final sourceRect = tester.getRect(qqSource);
    await tester.tapAt(Offset(sourceRect.left + 2, sourceRect.bottom - 2));
    await tester.pump();
    expect(settings.source, 'qq');
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS icon buttons keep a practical click target',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.byId('light').data.copyWith(
              platform: TargetPlatform.macOS,
            ),
        home: const Scaffold(
          body: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GIconButton(
                  icon: Icons.add_rounded,
                  tooltip: '新增',
                  size: 18,
                  padding: 4,
                  onTap: _noop,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(GIconButton)).shortestSide, 36);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings pickers use the root navigator overlay',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (nestedContext) => Scaffold(
              body: TextButton(
                onPressed: () => showSettingsPicker<String>(
                  nestedContext,
                  title: '选择音质',
                  current: 'auto',
                  options: const [
                    (value: 'auto', label: '自动'),
                    (value: 'lossless', label: '无损'),
                  ],
                ),
                child: const Text('打开选择器'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开选择器'));
    await tester.pumpAndSettle();

    expect(find.text('选择音质'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('选择音质'),
        matching: find.byType(Navigator),
      ),
      findsOneWidget,
    );
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
    expect(find.byTooltip('返回'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      app(
        UserLibraryView(
          title: '喜欢的音乐',
          embedded: true,
          loader: () async => const <Song>[],
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('返回'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      app(
        UserLibraryView(
          title: '喜欢的音乐',
          loader: () async => const <Song>[],
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile profile exposes music library entries', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final settings = SettingsController();
    final auth = AuthController();
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var favoritesOpened = false;
    var historyOpened = false;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('dark').data,
          home: ProfileView(
            embedded: true,
            onOpenFavorites: () => favoritesOpened = true,
            onOpenHistory: () => historyOpened = true,
          ),
        ),
      ),
    );
    await tester.pump();

    for (final label in const [
      '喜欢的音乐',
      '我的歌单',
      '收藏的歌单',
      '播放历史',
      '下载管理',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('喜欢的音乐'));
    await tester.tap(find.text('播放历史'));
    expect(favoritesOpened, isTrue);
    expect(historyOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS player opens with cover and reveals lyrics on cover tap',
      (tester) async {
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

    expect(find.text('穿过人海只为与你相见'), findsNothing);
    expect(find.byTooltip('收起播放器'), findsOneWidget);
    expect(find.bySemanticsLabel('查看歌词'), findsOneWidget);
    expect(find.byTooltip('返回封面'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('查看歌词'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('穿过人海只为与你相见'), findsOneWidget);
    expect(find.byTooltip('返回封面'), findsOneWidget);
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

  testWidgets('search input text stays visible on all supported platforms',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    const cases = <(TargetPlatform, String, Size)>[
      (TargetPlatform.android, 'light', Size(390, 844)),
      (TargetPlatform.android, 'dark', Size(390, 844)),
      (TargetPlatform.iOS, 'light', Size(390, 844)),
      (TargetPlatform.iOS, 'dark', Size(390, 844)),
      (TargetPlatform.macOS, 'light', Size(1280, 800)),
      (TargetPlatform.macOS, 'dark', Size(1280, 800)),
      (TargetPlatform.windows, 'light', Size(1280, 800)),
      (TargetPlatform.windows, 'dark', Size(1280, 800)),
    ];

    for (final (platform, themeId, size) in cases) {
      tester.view.physicalSize = size;
      final theme = AppTheme.byId(themeId).data.copyWith(platform: platform);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerController>.value(value: player),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
          ],
          child: MaterialApp(
            theme: theme,
            home: const SearchView(),
          ),
        ),
      );
      await tester.pump();

      final fieldFinder = find.byType(TextField);
      await tester.enterText(fieldFinder, '周杰伦');
      await tester.pump();

      final field = tester.widget<TextField>(fieldFinder);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, '周杰伦');
      expect(field.style?.color, theme.colorScheme.onSurface);
      expect(editable.style.color, theme.colorScheme.onSurface);
      expect(editable.cursorColor, theme.colorScheme.primary);
      expect(
        tester.getSize(find.byType(EditableText)).width,
        greaterThan(size.width * 0.55),
        reason: '可编辑区域不应被前后图标挤压',
      );
      expect(
        tester.getCenter(find.byTooltip('清除搜索')).dx,
        greaterThan(size.width * 0.82),
        reason: '清除按钮应位于搜索框右端',
      );
      expect(tester.takeException(), isNull, reason: '$platform at $size');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('password fields keep text space on all supported platforms',
      (tester) async {
    const cases = <(TargetPlatform, String, Size)>[
      (TargetPlatform.android, 'light', Size(390, 844)),
      (TargetPlatform.android, 'dark', Size(390, 844)),
      (TargetPlatform.iOS, 'light', Size(390, 844)),
      (TargetPlatform.iOS, 'dark', Size(390, 844)),
      (TargetPlatform.macOS, 'light', Size(1280, 800)),
      (TargetPlatform.macOS, 'dark', Size(1280, 800)),
      (TargetPlatform.windows, 'light', Size(1280, 800)),
      (TargetPlatform.windows, 'dark', Size(1280, 800)),
    ];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final (platform, themeId, size) in cases) {
      final auth = AuthController();
      tester.view.physicalSize = size;
      final theme = AppTheme.byId(themeId).data.copyWith(platform: platform);
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthController>.value(
          value: auth,
          child: MaterialApp(
            theme: theme,
            home: const LoginView(allowBack: false),
          ),
        ),
      );
      await tester.pump();

      final passwordField = find.byType(TextField).last;
      await tester.enterText(passwordField, 'visible-password');
      await tester.pump();
      final editable = find.byType(EditableText).last;
      final fieldRect = tester.getRect(passwordField);
      expect(
        tester.widget<EditableText>(editable).controller.text,
        'visible-password',
      );
      expect(
        tester.getSize(editable).width,
        greaterThan(fieldRect.width * 0.65),
        reason: '密码可编辑区域不应被眼睛按钮挤压',
      );
      expect(
        tester.getCenter(find.byTooltip('显示密码')).dx,
        greaterThan(fieldRect.right - 32),
        reason: '眼睛按钮应位于密码框右端',
      );
      expect(tester.takeException(), isNull, reason: '$platform at $size');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      auth.dispose();
    }
  });

  testWidgets('search pagination requests every result type with page offsets',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final api = _PagedSearchMusicApi();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('light').data,
          home: SearchView(api: api),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), '测试');
    await tester.pump(const Duration(milliseconds: 401));
    await tester.pumpAndSettle();

    expect(find.text('第 1 页'), findsOneWidget);
    expect(api.calls, contains(('song', 0, 30)));
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(api.calls, contains(('song', 30, 30)));
    expect(find.text('单曲 30'), findsOneWidget);

    for (final type in const ['歌手', '专辑', '歌单']) {
      await tester.tap(find.text(type));
      await tester.pumpAndSettle();
      final apiType = switch (type) {
        '歌手' => 'artist',
        '专辑' => 'album',
        _ => 'playlist',
      };
      expect(api.calls, contains((apiType, 0, 30)));
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(api.calls, contains((apiType, 30, 30)));
      expect(find.text('$type 30'), findsOneWidget);
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('search source switch reloads every result type from that source',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final api = _PagedSearchMusicApi();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('light').data,
          home: SearchView(api: api, initialQuery: '测试'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
        api.sources,
        containsAll(<(String, String)>[
          ('song', 'netease'),
          ('artist', 'netease'),
          ('album', 'netease'),
          ('playlist', 'netease'),
        ]));

    api.sources.clear();
    await tester.tap(find.text('绿源'));
    await tester.pump();
    await tester.pump();

    expect(settings.source, 'qq');
    expect(
        api.sources,
        containsAll(<(String, String)>[
          ('song', 'qq'),
          ('artist', 'qq'),
          ('album', 'qq'),
          ('playlist', 'qq'),
        ]));
    expect(api.sources.every((call) => call.$2 == 'qq'), isTrue);
    expect(tester.takeException(), isNull);
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

    final navLabels = ['首页', '发现', '搜索', '我的'];
    final labelCenters = [
      for (final label in navLabels) tester.getCenter(find.text(label).last).dx,
    ];
    expect(labelCenters, orderedEquals([...labelCenters]..sort()));
    expect(find.text('资料库'), findsNothing);

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(find.text('喜欢的音乐'), findsOneWidget);
    expect(find.text('播放历史'), findsOneWidget);
    expect(find.text('我的歌单'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('深浅模式'), findsOneWidget);
    expect(find.text('默认播放音质'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    final profileScroll = find
        .descendant(
          of: find.byType(ProfileView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('工具箱'),
      260,
      scrollable: profileScroll,
    );
    await tester.drag(profileScroll, const Offset(0, -100));
    await tester.pumpAndSettle();
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

class _PagedSearchMusicApi extends MusicApi {
  final List<(String, int, int)> calls = [];
  final List<(String, String)> sources = [];

  int _count(int offset, int limit) => offset == 0 ? limit : 1;

  @override
  Future<List<Song>> searchSongs(
    String keyword, {
    String source = 'netease',
    int offset = 0,
    int limit = 30,
  }) async {
    calls.add(('song', offset, limit));
    sources.add(('song', source));
    return List.generate(
      _count(offset, limit),
      (index) => _song(
        'song-${offset + index}',
        '单曲 ${offset + index}',
        artists: const ['测试歌手'],
        albumId: offset + index,
        album: '测试专辑',
      ),
    );
  }

  @override
  Future<List<SearchArtist>> searchArtists(
    String keyword, {
    String source = 'netease',
    int offset = 0,
    int limit = 30,
  }) async {
    calls.add(('artist', offset, limit));
    sources.add(('artist', source));
    return List.generate(
      _count(offset, limit),
      (index) => SearchArtist(
        id: 'artist-${offset + index}',
        name: '歌手 ${offset + index}',
        source: source,
      ),
    );
  }

  @override
  Future<List<SearchAlbum>> searchAlbums(
    String keyword, {
    String source = 'netease',
    int offset = 0,
    int limit = 30,
  }) async {
    calls.add(('album', offset, limit));
    sources.add(('album', source));
    return List.generate(
      _count(offset, limit),
      (index) => SearchAlbum(
        id: 'album-${offset + index}',
        name: '专辑 ${offset + index}',
        artist: '测试歌手',
        source: source,
      ),
    );
  }

  @override
  Future<List<Playlist>> searchPlaylists(
    String keyword, {
    String source = 'netease',
    int offset = 0,
    int limit = 30,
  }) async {
    calls.add(('playlist', offset, limit));
    sources.add(('playlist', source));
    return List.generate(
      _count(offset, limit),
      (index) => Playlist(
        id: offset + index,
        name: '歌单 ${offset + index}',
        source: source,
      ),
    );
  }
}

class _PreviewPlayerController extends PlayerController {
  _PreviewPlayerController() : super(settings: SettingsController());

  int? movedToNextIndex;
  Song? playedNext;

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

  late final List<Song> _previewQueue = [
    _song,
    Song(
      id: 'preview-next',
      name: '测试下一首',
      source: 'netease',
      artists: const [Artist(id: 3, name: '歌手丙')],
      album: const Album(id: 2, name: '测试专辑二'),
      durationMs: 185000,
    ),
    Song(
      id: 'preview-later',
      name: '测试稍后播放',
      source: 'netease',
      artists: const [Artist(id: 4, name: '歌手丁')],
      album: const Album(id: 3, name: '测试专辑三'),
      durationMs: 192000,
    ),
  ];

  @override
  Song get current => _song;

  @override
  List<Song> get queue => _previewQueue;

  @override
  int get queueIndex => 0;

  @override
  void moveToNext(int index) {
    movedToNextIndex = index;
    notifyListeners();
  }

  @override
  void playNext(Song song, {int? queueIndex}) {
    playedNext = song;
    notifyListeners();
  }

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

class _FakePlaylistUserApi extends UserApi {
  String? addedSource;
  String? addedPlaylistId;
  String? addedToken;
  String? removedSource;
  String? removedPlaylistId;
  String? removedToken;
  String? deletedToken;
  bool favorite = false;

  @override
  Future<Map<String, dynamic>> getPlaylistFavoriteStatus(
    String source,
    String playlistId,
    String token,
  ) async {
    return {
      'source': source,
      'playlistId': playlistId,
      'favorite': favorite,
      'userPlaylistId': favorite ? 42 : null,
    };
  }

  @override
  Future<Map<String, dynamic>> addPlaylistFavorite(
    String source,
    String playlistId,
    String token,
  ) async {
    addedSource = source;
    addedPlaylistId = playlistId;
    addedToken = token;
    favorite = true;
    return const {
      'id': 42,
    };
  }

  @override
  Future<void> removePlaylistFavorite(
    String source,
    String playlistId,
    String token,
  ) async {
    removedSource = source;
    removedPlaylistId = playlistId;
    removedToken = token;
    deletedToken = token;
    favorite = false;
  }
}

class _PlaylistAuthApi extends AuthApi {
  @override
  Future<Map<String, dynamic>> getMe(String token) async => {
        'username': '测试用户',
      };
}

class _FakePasswordResetApi extends AuthApi {
  String? email;
  String? confirmedEmail;
  String? verificationCode;
  String? newPassword;

  @override
  Future<PasswordResetCodeInfo> requestPasswordResetCode(String email) async {
    this.email = email;
    return const PasswordResetCodeInfo(
      resendAfterSeconds: 2,
      expiresInSeconds: 600,
    );
  }

  @override
  Future<void> confirmPasswordReset(
    String email,
    String verificationCode,
    String newPassword,
  ) async {
    confirmedEmail = email;
    this.verificationCode = verificationCode;
    this.newPassword = newPassword;
  }
}
