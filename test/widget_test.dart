import 'package:duck_music/features/settings/settings_view.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/models/artist_info.dart';
import 'package:duck_music/core/api/artist_info_api.dart';
import 'package:duck_music/core/api/auth_api.dart';
import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/api/user_api.dart';
import 'package:duck_music/core/models/membership.dart';
import 'package:duck_music/core/models/playlist.dart';
import 'package:duck_music/core/models/book.dart';
import 'package:duck_music/app.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/auth/legacy_auth_session.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:duck_music/core/player/lrc_parser.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:duck_music/core/services/app_update_service.dart';
import 'package:duck_music/core/services/desktop_integration_service.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/player/desktop_player_panel.dart';
import 'package:duck_music/features/player/mini_player.dart';
import 'package:duck_music/features/player/player_view.dart';
import 'package:duck_music/features/home/home_shell.dart';
import 'package:duck_music/features/profile/profile_view.dart';
import 'package:duck_music/features/profile/login_view.dart';
import 'package:duck_music/features/profile/legal_document_view.dart';
import 'package:duck_music/features/profile/user_library_view.dart';
import 'package:duck_music/features/profile/user_playlists_view.dart';
import 'package:duck_music/features/search/search_view.dart';
import 'package:duck_music/features/search/artist_detail_view.dart';
import 'package:duck_music/features/search/artist_names_link.dart';
import 'package:duck_music/features/playlists/playlists_view.dart';
import 'package:duck_music/features/playlists/playlist_detail_view.dart';
import 'package:duck_music/features/discover/discover_view.dart';
import 'package:duck_music/features/settings/settings_components.dart';
import 'package:duck_music/features/tools/tools_view.dart';
import 'package:duck_music/features/books/book_reader_view.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:duck_music/widgets/async_cover.dart';
import 'package:duck_music/widgets/song_row.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:ffi' as ffi;

void _noop() {}

Future<void> _sendSystemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void main() {
  test('Android update manifest uses canonical ABI names', () {
    expect(
      AppUpdateService.androidAbiName(ffi.Abi.androidArm64),
      'arm64-v8a',
    );
    expect(
      AppUpdateService.androidAbiName(ffi.Abi.androidArm),
      'armeabi-v7a',
    );
    expect(AppUpdateService.androidAbiName(ffi.Abi.androidX64), 'x86_64');
  });

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
            'name': 'DuckMusic-Flutter-v1.2.0-Android-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/arm64.apk',
          },
          {
            'name': 'DuckMusic-Flutter-v1.2.0-Android-x86_64.apk',
            'browser_download_url': 'https://example.com/x86_64.apk',
          },
        ],
        UpdateTarget.android,
        requiredNamePrefix: 'DuckMusic-Flutter-',
        architecture: 'androidArm64',
      ),
      'https://example.com/arm64.apk',
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

  const androidReleaseAssets = [
    {
      'name': 'DuckMusic-Flutter-v1.1.54-Android-universal.apk',
      'browser_download_url': 'https://example.com/universal.apk',
    },
    {
      'name': 'DuckMusic-Flutter-v1.1.54-Android-armeabi-v7a.apk',
      'browser_download_url': 'https://example.com/armv7.apk',
    },
    {
      'name': 'DuckMusic-Flutter-v1.1.54-Android-x86_64.apk',
      'browser_download_url': 'https://example.com/x64.apk',
    },
    {
      'name': 'DuckMusic-Flutter-v1.1.54-Android-arm64-v8a.apk',
      'browser_download_url': 'https://example.com/arm64.apk',
    },
    {
      'name': 'DuckMusic-Flutter-v1.1.54-Android-x86.apk',
      'browser_download_url': 'https://example.com/x86.apk',
    },
  ];
  for (final scenario in [
    (abi: ffi.Abi.androidArm64, url: 'https://example.com/arm64.apk'),
    (abi: ffi.Abi.androidArm, url: 'https://example.com/armv7.apk'),
    (abi: ffi.Abi.androidX64, url: 'https://example.com/x64.apk'),
  ]) {
    test('Android GitHub update prefers the matching ${scenario.abi} APK', () {
      expect(
        AppUpdateService.selectAssetUrl(
          androidReleaseAssets,
          UpdateTarget.android,
          requiredNamePrefix: 'DuckMusic-Flutter-',
          architecture: scenario.abi.toString(),
        ),
        scenario.url,
      );
    });

    test('Android GitHub update falls back to universal for ${scenario.abi}',
        () {
      expect(
        AppUpdateService.selectAssetUrl(
          androidReleaseAssets
              .where((asset) => asset['browser_download_url'] != scenario.url)
              .toList(),
          UpdateTarget.android,
          architecture: scenario.abi.toString(),
        ),
        'https://example.com/universal.apk',
      );
    });

    test('Android GitHub update rejects other ABIs for ${scenario.abi}', () {
      expect(
        AppUpdateService.selectAssetUrl(
          androidReleaseAssets
              .where((asset) =>
                  asset['browser_download_url'] != scenario.url &&
                  asset['browser_download_url'] !=
                      'https://example.com/universal.apk')
              .toList(),
          UpdateTarget.android,
          architecture: scenario.abi.toString(),
        ),
        isNull,
      );
    });
  }

  test('Android GitHub update does not guess an unknown device ABI', () {
    expect(
      AppUpdateService.selectAssetUrl(
        androidReleaseAssets.sublist(1),
        UpdateTarget.android,
        architecture: 'unknown',
      ),
      isNull,
    );
  });

  test('Android GitHub update preserves an unlabelled APK fallback', () {
    expect(
      AppUpdateService.selectAssetUrl(
        [
          androidReleaseAssets[1],
          {
            'name': 'DuckMusic-Flutter-v1.1.54-Android.apk',
            'browser_download_url': 'https://example.com/app.apk',
          },
        ],
        UpdateTarget.android,
        architecture: ffi.Abi.androidArm64.toString(),
      ),
      'https://example.com/app.apk',
    );
  });

  for (final scenario in [
    (target: UpdateTarget.macos, architecture: 'macosArm64', extension: 'dmg'),
    (
      target: UpdateTarget.windows,
      architecture: 'windowsX64',
      extension: 'exe'
    ),
  ]) {
    test('desktop update keeps universal preference for ${scenario.target}',
        () {
      expect(
        AppUpdateService.selectAssetUrl(
          [
            {
              'name':
                  'DuckMusic-${scenario.architecture}.${scenario.extension}',
              'browser_download_url': 'https://example.com/matching',
            },
            {
              'name': 'DuckMusic-universal.${scenario.extension}',
              'browser_download_url': 'https://example.com/universal',
            },
          ],
          scenario.target,
          architecture: scenario.architecture,
        ),
        'https://example.com/universal',
      );
    });
  }

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

  test('android update check prefers the ECS manifest', () async {
    var requestCount = 0;
    final service = AppUpdateService(
      client: MockClient((request) async {
        requestCount++;
        expect(request.url.host, 'api.751152.xyz');
        return http.Response(
          '''{
            "version": "1.1.33",
            "buildNumber": 44,
            "downloadUrl": "https://api.751152.xyz/updates/app.apk"
          }''',
          200,
        );
      }),
    );

    final result = await service.checkLatest(
      currentVersion: '1.1.27',
      target: UpdateTarget.android,
    );

    expect(result.status, UpdateCheckStatus.updateAvailable);
    expect(result.release?.version, '1.1.33');
    expect(result.release?.assetUrl, 'https://api.751152.xyz/updates/app.apk');
    expect(requestCount, 1);
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
      'artistId': '11',
      'artistIds': ['11', '22'],
      'availableQualities': ['128k', 'flac'],
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
    expect(song.durationMs, 180000);
    expect(song.artists.map((artist) => artist.id), [11, 22]);
    expect(song.availableQualities, ['128k', 'flac']);
    expect(playlist.id, 654321);
    expect(playlist.name, '2026');
    expect(userSong.id, '42');
    expect(userSong.name, '2026');
  });

  test('song duration accepts source-specific and string fields', () {
    Map<String, dynamic> songJson(Map<String, dynamic> duration) => {
          'id': 'duration-test',
          'name': '时长测试',
          'artist': '测试歌手',
          'album': '测试专辑',
          ...duration,
        };

    expect(Song.fromV1(songJson({'durationMs': '187000'})).durationMs, 187000);
    expect(Song.fromV1(songJson({'durationSec': '187'})).durationMs, 187000);
    expect(Song.fromV1(songJson({'dt': 187000})).durationMs, 187000);
    expect(Song.fromV1(songJson({'interval': 187})).durationMs, 187000);
    expect(Song.fromV1(songJson({'duration': 187})).durationMs, 187000);
    expect(Song.fromV1(songJson({'duration': 187000})).durationMs, 187000);
    expect(
      Song.fromV1(songJson({'durationMs': 0, 'durationSec': 187})).durationMs,
      187000,
    );
  });

  testWidgets('progress bar seeks by tap and commits drag only once',
      (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: GProgressBar(
              position: const Duration(seconds: 20),
              duration: const Duration(seconds: 100),
              onSeek: seeks.add,
            ),
          ),
        ),
      ),
    );

    final progress = find.byType(GProgressBar);
    final rect = tester.getRect(progress);
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pump();
    expect(seeks, [const Duration(seconds: 75)]);

    seeks.clear();
    await tester.dragFrom(
      Offset(rect.left + rect.width * 0.2, rect.center.dy),
      Offset(rect.width * 0.6, 0),
    );
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(seeks.single.inMilliseconds, closeTo(80000, 1000));
  });

  testWidgets('progress bar with unknown duration never seeks to zero',
      (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: GProgressBar(
              position: const Duration(seconds: 20),
              duration: Duration.zero,
              onSeek: seeks.add,
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(GProgressBar));
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.dragFrom(rect.center, const Offset(60, 0));
    await tester.pump();
    expect(seeks, isEmpty);
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
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    final desktop = DesktopIntegrationService(
      settings: settings,
      player: player,
    );
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);
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
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SleepTimer>.value(value: timer),
          ChangeNotifierProvider<DesktopIntegrationService>.value(
              value: desktop),
        ],
        child: MaterialApp(
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
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    final desktop = DesktopIntegrationService(
      settings: settings,
      player: player,
    );
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
          ChangeNotifierProvider<DesktopIntegrationService>.value(
              value: desktop),
        ],
        child: MaterialApp(
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
    final auth = AuthController(
      legacySessionSource: const _EmptyLegacyAuthSessionSource(),
    );
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
    expect(find.text('我已阅读并同意'), findsOneWidget);
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

    await tester.tap(find.text('创建账号').last);
    await tester.pumpAndSettle();
    expect(find.byType(RegisterView), findsOneWidget);
    expect(find.text('昵称'), findsOneWidget);
    expect(find.text('邮箱'), findsOneWidget);
    expect(find.text('创建账号'), findsWidgets);
    expect(find.text('已经有账号？'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
  });

  testWidgets('registration sends and submits the current email code',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final api = _FakeRegistrationApi();
    final auth = AuthController(api: api);
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthController>.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.byId('dark').data,
          home: const RegisterView(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'listener');
    await tester.enterText(find.byType(TextField).at(1), '12345@qq.com');
    await tester.tap(find.text('获取验证码'));
    await tester.pump();

    expect(api.codeEmail, '12345@qq.com');
    expect(find.text('2 秒后重发'), findsOneWidget);
    expect(find.text('验证码已发送，10 分钟内有效'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(2), '123456');
    await tester.enterText(find.byType(TextField).at(3), 'secret12');
    await tester.tap(find.text('创建账号').last);
    await tester.pump();
    expect(api.registeredUsername, isNull);
    expect(find.text('请先阅读并同意用户协议与隐私政策'), findsOneWidget);

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.ensureVisible(find.text('创建账号').last);
    await tester.tap(find.text('创建账号').last);
    await tester.pump();
    await tester.pump();

    expect(api.registeredUsername, 'listener');
    expect(api.registeredEmail, '12345@qq.com');
    expect(api.registeredPassword, 'secret12');
    expect(api.registeredCode, '123456');
    expect(auth.isLoggedIn, isTrue);
  });

  testWidgets('login legal and password recovery routes are functional',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final auth = AuthController(
      legacySessionSource: const _EmptyLegacyAuthSessionSource(),
    );
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
    await tester.tap(find.text('《用户协议》'));
    await tester.pumpAndSettle();
    expect(find.byType(LegalDocumentView), findsOneWidget);
    expect(find.text('用户协议'), findsWidgets);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('《隐私政策》'));
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
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    await pumpAt(const Size(900, 700), sidebarWidth: 236);
    await pumpAt(const Size(768, 1024));
    await pumpAt(const Size(390, 844));
  });

  testWidgets(
      'collapsed mobile player disc reflects the actual playback fraction',
      (tester) async {
    final player = _PreviewPlayerController();
    addTearDown(player.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerController>.value(
        value: player,
        child: MaterialApp(
          theme: AppTheme.byId('dark').data.copyWith(
                platform: TargetPlatform.iOS,
              ),
          home: const Scaffold(body: MiniPlayer(collapsed: true)),
        ),
      ),
    );
    await tester.pump();

    final progress = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('mobile-player-disc-progress')),
    );
    expect(progress.value, closeTo(170 / 207, .001));
    expect(find.byKey(const ValueKey('mobile-mini-player-progress-fill')),
        findsNothing);
    expect(find.byTooltip('打开播放器'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mini player takes no space before the first song is played',
      (tester) async {
    final settings = SettingsController();
    final player = PlayerController(settings: settings);
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);

    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerController>.value(
        value: player,
        child: MaterialApp(
          theme: AppTheme.byId('dark').data.copyWith(
                platform: TargetPlatform.macOS,
              ),
          home: const Scaffold(body: MiniPlayer(sidebarWidth: 264)),
        ),
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(MiniPlayer)), Size.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('press scale activates from keyboard focus', (tester) async {
    var activations = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GPressScale(
              onTap: () => activations++,
              child: const Text('键盘操作'),
            ),
          ),
        ),
      ),
    );

    Focus.of(tester.element(find.text('键盘操作'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(activations, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page header stacks actions on compact widths', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GPageHeader(
            title: '个人资料',
            subtitle: '管理你的账户信息',
            trailing: GButton(label: '编辑', onTap: _noop),
          ),
        ),
      ),
    );
    await tester.pump();

    final title = find.text('个人资料');
    final action = find.text('编辑');
    expect(
      tester.getTopLeft(action).dy,
      greaterThan(tester.getBottomLeft(title).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty book reader explains when no chapters are available',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.byId('light').data.copyWith(
              platform: TargetPlatform.iOS,
            ),
        home: const BookReaderView(
          book: Book(sourceId: 'test', name: '测试小说', bookUrl: 'book://test'),
          chapters: [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无可读章节'), findsOneWidget);
    expect(find.byTooltip('上一章'), findsNothing);
    final backButton = find.byTooltip('返回');
    expect(backButton, findsOneWidget);
    expect(tester.getTopLeft(backButton).dy, lessThan(80));
    expect(tester.getSize(backButton).height, lessThan(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop mini player toggles functional lyrics and queue panels',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    final desktop = DesktopIntegrationService(
      settings: settings,
      player: player,
    );
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
          ChangeNotifierProvider<DesktopIntegrationService>.value(
              value: desktop),
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
    expect(find.text('列表循环'), findsOneWidget);
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

    await tester.tap(find.text('列表循环'));
    await tester.pump();
    expect(find.text('单曲循环'), findsOneWidget);
    await tester.tap(find.text('单曲循环'));
    await tester.pump();
    expect(find.text('随机播放'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭播放队列'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(DesktopPlayerPanel)).dx, 1304);
    expect(tester.takeException(), isNull);
  });

  testWidgets('song rows expose the complete shared action menu',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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
          theme: AppTheme.byId('dark')
              .data
              .copyWith(platform: TargetPlatform.android),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SongRow(song: player.current))),
        ),
      ),
    );

    expect(find.byTooltip('更多：The Gentlemen (Live)'), findsOneWidget);
    await tester.tap(find.byTooltip('更多：The Gentlemen (Live)'));
    await tester.pumpAndSettle();
    for (final action in const ['播放', '下一首播放', '喜欢', '收藏到歌单', '下载']) {
      final item = find.text(action);
      expect(item.hitTestable(), findsOneWidget);
      final bounds = tester.getRect(item);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(700));
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
    final theme = AppTheme.forAccent('skyBlue', dark: true).data;
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
          theme: theme.copyWith(platform: TargetPlatform.macOS),
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
    expect(
      find.ancestor(
        of: find.text('全部播放'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color ==
                  theme.colorScheme.primary,
        ),
      ),
      findsOneWidget,
    );
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
      inInclusiveRange(111, 112),
    );
    expect(tester.getSize(find.byType(GBackButton)).shortestSide,
        greaterThanOrEqualTo(44));
    expect(tester.getCenter(find.text('详情')).dx, closeTo(195, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS back button keeps its full target clickable',
      (tester) async {
    var tapped = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.byId('dark').data.copyWith(
              platform: TargetPlatform.iOS,
            ),
        home: Scaffold(
          body: GAppBar(
            title: '详情',
            onBack: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('返回'), findsNothing);
    final backRect = tester.getRect(find.byType(GBackButton));
    await tester.tapAt(Offset(backRect.right - 1, backRect.center.dy));
    expect(tapped, isTrue);
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

    expect(tester.getTopLeft(find.byTooltip('返回')).dx, closeTo(24, 0.5));
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
    final timer = SleepTimer();
    final desktop = DesktopIntegrationService(
      settings: settings,
      player: player,
    );
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SleepTimer>.value(value: timer),
          ChangeNotifierProvider<DesktopIntegrationService>.value(
              value: desktop),
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

    await tester.tap(find.text('首页').first);
    await tester.pumpAndSettle();
    expect(profileTitle, findsNothing);
    expect(
        find.descendant(
          of: find.byType(DiscoverView),
          matching: find.text('首页'),
        ),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile library routes keep the same nested shell behavior',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'library-route-token',
      'auth_username': '测试用户',
    });
    final auth = AuthController(api: _PlaylistAuthApi());
    await auth.load();
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final timer = SleepTimer();
    final desktop = DesktopIntegrationService(
      settings: settings,
      player: player,
    );
    addTearDown(auth.dispose);
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(timer.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SleepTimer>.value(value: timer),
          ChangeNotifierProvider<DesktopIntegrationService>.value(
              value: desktop),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('dark').data.copyWith(
                platform: TargetPlatform.macOS,
              ),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('测试用户').last);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(ProfileView),
        matching: find.text('我的歌单'),
      ),
    );
    await tester.pump();

    expect(find.byType(UserPlaylistsView), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byType(MiniPlayer), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(ProfileView),
        matching: find.text('播放历史'),
      ),
    );
    await tester.pump();

    expect(find.byType(UserLibraryView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(UserLibraryView),
        matching: find.text('播放历史'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byType(MiniPlayer), findsOneWidget);
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
    final timer = SleepTimer();
    final desktop = DesktopIntegrationService(
      settings: settings,
      player: player,
    );
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SleepTimer>.value(value: timer),
          ChangeNotifierProvider<DesktopIntegrationService>.value(
              value: desktop),
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
    await tester.pumpAndSettle();
    expect(tester.getSize(qqSource).height, greaterThanOrEqualTo(40));
    final sourceRect = tester.getRect(qqSource);
    await tester.tapAt(Offset(sourceRect.left + 2, sourceRect.bottom - 2));
    await tester.pump();
    expect(settings.source, 'netease');
    expect(settings.searchSource, 'qq');
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
                    (value: 'auto', label: '自动', detail: null),
                    (value: 'lossless', label: '无损', detail: null),
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
          kind: UserLibraryKind.favorites,
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
          kind: UserLibraryKind.favorites,
          loader: () async => const <Song>[],
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('playlist libraries keep their title and follow the active skin',
      (tester) async {
    final player = _PreviewPlayerController();
    addTearDown(player.dispose);
    final theme = AppTheme.forAccent('skyBlue', dark: true).data;

    Widget app(UserLibraryView child) =>
        ChangeNotifierProvider<PlayerController>.value(
          value: player,
          child: MaterialApp(theme: theme, home: child),
        );

    await tester.pumpWidget(
      app(
        UserLibraryView(
          title: '周末歌单',
          kind: UserLibraryKind.playlist,
          loader: () async => const <Song>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('周末歌单'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox &&
            widget.color == theme.colorScheme.surfaceContainerLowest,
      ),
      findsWidgets,
    );
    expect(find.text('播放历史'), findsNothing);
    expect(find.text('最近播放'), findsNothing);
    await tester.tap(find.byTooltip('搜索歌曲'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      '搜索歌曲',
    );

    await tester.pumpWidget(
      app(
        UserLibraryView(
          title: '喜欢的音乐',
          kind: UserLibraryKind.favorites,
          loader: () async => const <Song>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final favoriteIcon = tester.widget<Icon>(
      find.byIcon(Icons.favorite_rounded).first,
    );
    expect(favoriteIcon.color, AppBrand.favoriteRed);
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

    for (final label in const [
      '深浅模式',
      '主题色',
      '默认音乐源',
      '默认播放音质',
      '液态玻璃质量',
      '减弱动态效果',
      '存储与缓存',
      '通知',
    ]) {
      expect(find.text(label), findsNothing);
    }

    await tester.tap(find.text('喜欢的音乐'));
    await tester.tap(find.text('播放历史'));
    expect(favoritesOpened, isTrue);
    expect(historyOpened, isTrue);
    for (final icon in [Icons.favorite_rounded, Icons.bookmark_rounded]) {
      expect(
          tester.widget<Icon>(find.byIcon(icon)).color, AppBrand.favoriteRed);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS player swipes between artwork and immersive lyrics',
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
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    expect(find.text('心动'), findsNothing);
    expect(find.byKey(const ValueKey('mobile-player-artwork')), findsOneWidget);
    expect(find.byTooltip('收起播放器'), findsOneWidget);
    expect(find.bySemanticsLabel('查看歌词'), findsOneWidget);
    expect(find.byTooltip('AirPlay 或蓝牙'), findsNothing);
    expect(find.byTooltip('播放队列'), findsOneWidget);
    expect(find.byTooltip('切换音质'), findsOneWidget);
    expect(find.byTooltip('返回封面'), findsNothing);
    expect(find.textContaining('关注'), findsNothing);
    expect(find.textContaining('作曲：'), findsNothing);
    expect(
      find.bySemanticsLabel('查看弹壳Danko / Vinz-T的歌手信息'),
      findsOneWidget,
    );
    // The player now keeps the close control inside the safe-area toolbar
    // instead of translating it under the status bar.
    expect(tester.getTopLeft(find.byTooltip('收起播放器')).dy,
        greaterThanOrEqualTo(47));
    expect(tester.takeException(), isNull);

    player.setPlaying(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 340));
    expect(find.byTooltip('暂停'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    player.setPlaying(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 740));
    expect(find.byTooltip('播放'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final progressBar = find.byType(GProgressBar);
    final progressRect = tester.getRect(progressBar);
    await tester.tapAt(
      Offset(
          progressRect.left + progressRect.width * 0.5, progressRect.center.dy),
    );
    await tester.pump();
    expect(player.soughtTo, const Duration(milliseconds: 103500));

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌曲百科'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('歌曲百科'), findsOneWidget);
    expect(find.text('The Gentlemen (Live)'), findsNWidgets(2));
    expect(find.text('歌手信息'), findsOneWidget);
    expect(find.text('弹壳Danko'), findsOneWidget);
    expect(find.text('Vinz-T'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭歌曲信息'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌曲操作'));
    await tester.pumpAndSettle();
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('收藏到歌单'), findsNothing);
    await tester.tapAt(const Offset(8, 80));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('切换音质'));
    await tester.pumpAndSettle();
    expect(find.text('红源 · 当前歌曲音质'), findsOneWidget);
    await tester.tap(find.text('无损 SQ'));
    await tester.pumpAndSettle();
    expect(settings.quality, 'lossless');
    expect(find.text('无损音质'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pump(const Duration(milliseconds: 400));
    final fullLyricLine = find.descendant(
      of: find.byType(ListView),
      matching: find.text('穿过人海只为与你相见'),
    );
    await tester.scrollUntilVisible(fullLyricLine, 120,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    expect(fullLyricLine, findsOneWidget);
    expect(find.byKey(const ValueKey('lyric-title')), findsOneWidget);
    expect(find.byTooltip('播放队列').hitTestable(), findsNothing);
    expect(find.byTooltip('播放').hitTestable(), findsNothing);

    await tester.ensureVisible(fullLyricLine);
    await tester.pump();
    await tester.tap(fullLyricLine);
    await tester.pump();
    expect(player.soughtTo, const Duration(minutes: 2, seconds: 49));
    expect(find.byTooltip('AirPlay 或蓝牙'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('AirPlay 或蓝牙'), findsNothing);

    await tester.tapAt(const Offset(8, 330));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('lyric-title')), findsOneWidget);
    await tester.tap(find.byTooltip('返回封面'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('查看歌词'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('查看歌词'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('lyric-title')), findsOneWidget);
    expect(find.byTooltip('AirPlay 或蓝牙'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('QQ songs only show supported playback qualities',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    player.replaceCurrent(
      Song(
        id: 'qq-preview',
        name: '绿源测试歌曲',
        source: 'qq',
        artists: const [Artist(id: 1, name: '测试歌手')],
        album: const Album(id: 1, name: '测试专辑'),
        durationMs: 180000,
      ),
    );
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);

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
            data: MediaQueryData(size: Size(390, 844)),
            child: PlayerView(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('切换音质'));
    await tester.pumpAndSettle();

    expect(find.text('绿源 · 当前歌曲音质'), findsOneWidget);
    expect(find.text('标准音质'), findsOneWidget);
    expect(find.text('高品质'), findsOneWidget);
    expect(find.text('无损音质'), findsOneWidget);
    expect(find.text('智能选择'), findsNothing);
    expect(find.text('Hi-Res'), findsNothing);
    expect(find.text('128 Kbps'), findsOneWidget);
    expect(find.text('320 Kbps'), findsOneWidget);
    expect(find.text('FLAC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'mobile full-screen player keeps controls visible at supported sizes',
      (tester) async {
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pumpPlayer(Size size, TargetPlatform platform) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerController>.value(value: player),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
            ChangeNotifierProvider<AuthController>.value(value: auth),
            ChangeNotifierProvider<SleepTimer>.value(value: timer),
          ],
          child: MaterialApp(
            theme: AppTheme.byId('light').data.copyWith(platform: platform),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                padding: platform == TargetPlatform.iOS
                    ? const EdgeInsets.only(top: 47, bottom: 34)
                    : const EdgeInsets.only(top: 24, bottom: 24),
              ),
              child: const PlayerView(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final platform in const [
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      for (final size in const [
        Size(320, 568),
        Size(375, 667),
        Size(390, 844),
        Size(430, 932),
      ]) {
        await pumpPlayer(size, platform);

        expect(find.text('心动'), findsNothing);
        final coverSize =
            tester.getSize(find.byKey(const ValueKey('mobile-player-artwork')));
        expect(coverSize.width, closeTo(coverSize.height, 0.01));
        expect(find.bySemanticsLabel('查看歌词'), findsOneWidget);
        expect(find.byTooltip('AirPlay 或蓝牙'), findsNothing);
        expect(find.byTooltip('播放设置'), findsOneWidget);
        expect(find.byTooltip('播放队列'), findsOneWidget);
        expect(find.byTooltip('歌曲百科'), findsNothing);
        expect(find.byTooltip('更多'), findsOneWidget);

        final viewport = Offset.zero & size;
        for (final finder in [
          find.byTooltip('播放'),
          find.byTooltip('播放设置'),
          find.byTooltip('播放队列'),
        ]) {
          expect(viewport.contains(tester.getCenter(finder)), isTrue);
        }
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('歌曲百科'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('当前音质'));
        await tester.pumpAndSettle();
        expect(
          viewport.contains(tester.getCenter(find.text('当前音质'))),
          isTrue,
        );
        await tester.ensureVisible(find.byTooltip('关闭歌曲信息'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭歌曲信息'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('mobile full-screen player returns to cover when song changes',
      (tester) async {
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          home: const PlayerView(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('查看歌词'));
    await tester.pump(const Duration(milliseconds: 400));
    player.replaceCurrent(
      _song(
        'replacement',
        '下一首测试歌曲',
        artists: const ['测试歌手'],
        albumId: 99,
        album: '测试专辑',
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('查看歌词'), findsOneWidget);
    expect(find.text('下一首测试歌曲'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary content pages render at desktop and compact widths',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

    for (final size in const [
      Size(1280, 800),
      Size(900, 700),
      Size(768, 1024),
      Size(430, 760),
    ]) {
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
        greaterThan(tester.getSize(fieldFinder).width * 0.55),
        reason: '可编辑区域不应被前后图标挤压',
      );
      expect(
        tester.getCenter(find.byTooltip('清除搜索')).dx,
        greaterThan(tester.getRect(fieldFinder).right - 40),
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

    Future<void> reachNextPage(String type) async {
      final scroll = tester.widget<CustomScrollView>(
          find.byKey(const ValueKey('search-results-scroll')));
      for (var attempt = 0;
          attempt < 8 && !api.calls.contains((type, 30, 30));
          attempt++) {
        scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
    }

    expect(find.byTooltip('下一页'), findsNothing);
    expect(api.calls, contains(('song', 0, 30)));
    await reachNextPage('song');
    expect(api.calls, contains(('song', 30, 30)));

    for (final type in const ['艺人', '专辑', '歌单']) {
      final scroll = tester.widget<CustomScrollView>(
          find.byKey(const ValueKey('search-results-scroll')));
      scroll.controller!.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text(type).first);
      await tester.pumpAndSettle();
      final apiType = switch (type) {
        '艺人' => 'artist',
        '专辑' => 'album',
        _ => 'playlist',
      };
      expect(api.calls, contains((apiType, 0, 30)));
      await reachNextPage(apiType);
      expect(api.calls, contains((apiType, 30, 30)));
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('绿源'));
    await tester.pump();
    await tester.pump();

    expect(settings.source, 'netease');
    expect(settings.searchSource, 'qq');
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

  testWidgets(
      'secondary content routes keep mini player and hide bottom navigation',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    final desktop = DesktopIntegrationService(
      settings: settings,
      player: player,
    );
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
          ChangeNotifierProvider<DesktopIntegrationService>.value(
              value: desktop),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('dark').data,
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();

    final navLabels = ['探索', '资料库', '我的'];
    final labelCenters = [
      for (final label in navLabels) tester.getCenter(find.text(label).last).dx,
    ];
    expect(labelCenters, orderedEquals([...labelCenters]..sort()));
    expect(find.text('资料库'), findsWidgets);
    expect(find.text('影视'), findsNothing);
    expect(find.text('直播'), findsNothing);

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(find.text('喜欢的音乐'), findsOneWidget);
    expect(find.text('播放历史'), findsOneWidget);
    expect(find.text('我的歌单'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('深浅模式'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('默认播放音质'), 200,
        scrollable: find
            .descendant(
                of: find.byType(SettingsView),
                matching: find.byType(Scrollable))
            .first);
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
    expect(
      find.byKey(const ValueKey('mobile-bottom-nav-surface')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('toolbox exposes live TV without playlist import',
      (tester) async {
    final settings = SettingsController();
    final player = _PreviewPlayerController();
    addTearDown(settings.dispose);
    addTearDown(player.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<PlayerController>.value(value: player),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('dark').data,
          home: const ToolsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('电视直播'), findsOneWidget);
    expect(find.text('导入歌单'), findsNothing);
    expect(find.text('即将上线'), findsNothing);
    expect(find.text('电台'), findsNothing);
  });

  testWidgets('Android system back unwinds the active tab before the app',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    final desktop = DesktopIntegrationService(
      settings: settings,
      player: player,
    );
    final platformCalls = <MethodCall>[];
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SleepTimer>.value(value: timer),
          ChangeNotifierProvider<DesktopIntegrationService>.value(
              value: desktop),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('dark').data.copyWith(
                platform: TargetPlatform.android,
              ),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('深浅模式'), findsOneWidget);

    await _sendSystemBack(tester);
    expect(find.text('深浅模式'), findsNothing);
    expect(find.byType(ProfileView), findsOneWidget);

    await _sendSystemBack(tester);
    expect(find.byType(ProfileView), findsNothing);
    expect(find.byType(DiscoverView), findsOneWidget);

    await _sendSystemBack(tester);
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive tab history does not intercept Android system back',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    final desktop = DesktopIntegrationService(
      settings: settings,
      player: player,
    );
    final platformCalls = <MethodCall>[];
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SleepTimer>.value(value: timer),
          ChangeNotifierProvider<DesktopIntegrationService>.value(
              value: desktop),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('dark').data.copyWith(
                platform: TargetPlatform.android,
              ),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await _sendSystemBack(tester);
    expect(find.byType(ProfileView), findsOneWidget);
    await tester.tap(find.text('探索').last);
    await tester.pumpAndSettle();

    await _sendSystemBack(tester);
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS edge swipe pops a nested page', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final player = _PreviewPlayerController();
    final settings = SettingsController();
    final auth = AuthController();
    final timer = SleepTimer();
    final desktop = DesktopIntegrationService(
      settings: settings,
      player: player,
    );
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 760);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SleepTimer>.value(value: timer),
          ChangeNotifierProvider<DesktopIntegrationService>.value(
              value: desktop),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('dark').data.copyWith(
                platform: TargetPlatform.iOS,
              ),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('深浅模式'), findsOneWidget);

    await tester.dragFrom(const Offset(1, 300), const Offset(360, 0));
    await tester.pumpAndSettle();
    expect(find.text('深浅模式'), findsNothing);
    expect(find.byType(ProfileView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('mobile themes preserve native back transitions', () {
    final builders = AppTheme.byId('dark').data.pageTransitionsTheme.builders;

    expect(
      builders[TargetPlatform.android],
      isA<PredictiveBackPageTransitionsBuilder>(),
    );
    expect(
      builders[TargetPlatform.iOS],
      isA<cupertino.CupertinoPageTransitionsBuilder>(),
    );
  });
}

class _EmptyLegacyAuthSessionSource implements LegacyAuthSessionSource {
  const _EmptyLegacyAuthSessionSource();

  @override
  Future<LegacyAuthSession?> read() async => null;

  @override
  Future<void> clear() async {}
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
  Duration? soughtTo;
  bool _playing = false;

  Song _song = Song(
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

  void replaceCurrent(Song song) {
    _song = song;
    notifyListeners();
  }

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
  bool get playing => _playing;

  void setPlaying(bool value) {
    _playing = value;
    notifyListeners();
  }

  @override
  bool get liked => false;

  @override
  Duration get position => const Duration(minutes: 2, seconds: 50);

  @override
  Stream<Duration> get positionStream => const Stream.empty();

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

  @override
  Future<void> seek(Duration position) async {
    soughtTo = position;
  }
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

class _FakeRegistrationApi extends AuthApi {
  String? codeEmail;
  String? registeredUsername;
  String? registeredEmail;
  String? registeredPassword;
  String? registeredCode;

  @override
  Future<RegistrationCodeInfo> requestRegistrationCode(String email) async {
    codeEmail = email;
    return const RegistrationCodeInfo(
      resendAfterSeconds: 2,
      expiresInSeconds: 600,
    );
  }

  @override
  Future<Map<String, dynamic>> register(
    String username,
    String email,
    String password,
    String verificationCode,
  ) async {
    registeredUsername = username;
    registeredEmail = email;
    registeredPassword = password;
    registeredCode = verificationCode;
    return {
      'accessToken': 'registration-access',
      'refreshToken': 'registration-refresh',
      'username': username,
      'email': email,
      'avatarUrl': 'https://example.com/avatar.png',
    };
  }
}
