import 'package:duck_music/core/api/user_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/library/library_view.dart';
import 'package:duck_music/features/profile/user_library_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  for (final width in [320.0, 390.0, 700.0]) {
    testWidgets('library keeps its cards usable at ${width.toInt()}px',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final settings = SettingsController();
      final player = PlayerController(settings: settings);
      final auth = AuthController();
      addTearDown(settings.dispose);
      addTearDown(player.dispose);
      addTearDown(auth.dispose);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.forAccent('forestGreen', dark: false).data,
          home: LibraryView(
            onOpenFavorites: () {},
            onOpenHistory: () {},
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('资料库'), findsOneWidget);
    });
  }

  testWidgets('owned playlists show real content and open using string IDs',
      (tester) async {
    final api = _LibraryApi();
    final auth = _LibraryAuth();
    await _pumpLibrary(tester, api: api, auth: auth);
    expect(find.text('通勤歌单'), findsOneWidget);
    expect(find.text('2 首歌曲'), findsOneWidget);
    expect(find.text('把喜欢的歌整理成自己的歌单'), findsNothing);
    await tester.ensureVisible(find.text('通勤歌单'));
    await tester.tap(find.text('通勤歌单'));
    await tester.pumpAndSettle();
    expect(find.byType(UserLibraryView), findsOneWidget);
    expect(api.openedPlaylist, 'playlist-with-string-id');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed library loads offer retry and retain successful refresh data',
      (tester) async {
    final api = _LibraryApi()..fail = true;
    await _pumpLibrary(tester, api: api, auth: _LibraryAuth());
    expect(find.text('资料库加载失败'), findsOneWidget);
    api.fail = false;
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('通勤歌单'), findsOneWidget);
    expect(find.text('资料库加载失败'), findsNothing);
    api.fail = true;
    await tester.ensureVisible(find.byTooltip('刷新资料库'));
    await tester.tap(find.byTooltip('刷新资料库'));
    await tester.pumpAndSettle();
    expect(find.text('资料库加载失败'), findsOneWidget);
    expect(find.text('通勤歌单'), findsOneWidget);
    expect(api.loads, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signing out removes account library data immediately',
      (tester) async {
    final auth = _LibraryAuth();
    await _pumpLibrary(tester, api: _LibraryApi(), auth: auth);
    expect(find.text('通勤歌单'), findsOneWidget);
    auth.clearSession();
    await tester.pumpAndSettle();
    expect(find.text('通勤歌单'), findsNothing);
    expect(find.text('登录后同步你的音乐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library supports enlarged text inside narrow desktop content',
      (tester) async {
    await _pumpLibrary(tester,
        api: _LibraryApi(),
        auth: _LibraryAuth(),
        windowWidth: 1280,
        contentWidth: 390,
        scale: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact macOS library avoids native window controls',
      (tester) async {
    await _pumpLibrary(tester,
        api: _LibraryApi(),
        auth: _LibraryAuth(),
        windowWidth: 700,
        platform: TargetPlatform.macOS);

    expect(tester.getTopLeft(find.text('资料库')).dx, greaterThanOrEqualTo(94));
    expect(tester.takeException(), isNull);
  });

  testWidgets('token rotation does not discard an open create-playlist dialog',
      (tester) async {
    final auth = _LibraryAuth();
    final api = _LibraryApi();
    await _pumpLibrary(tester, api: api, auth: auth);
    await tester.tap(find.byTooltip('新建歌单'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '继续编辑的歌单');
    auth.rotateToken();
    await tester.pumpAndSettle();
    expect(find.text('继续编辑的歌单'), findsOneWidget);

    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(api.createdName, '继续编辑的歌单');
    expect(api.createdToken, auth.token);
    expect(find.text('歌单已创建'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required UserApi api,
  required AuthController auth,
  double windowWidth = 390,
  double? contentWidth,
  double scale = 1,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(windowWidth, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final settings = SettingsController();
  final player = PlayerController(settings: settings);
  addTearDown(settings.dispose);
  addTearDown(player.dispose);
  addTearDown(auth.dispose);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsController>.value(value: settings),
      ChangeNotifierProvider<PlayerController>.value(value: player),
      ChangeNotifierProvider<AuthController>.value(value: auth),
    ],
    child: MaterialApp(
      theme: AppTheme.forAccent('forestGreen', dark: false)
          .data
          .copyWith(platform: platform),
      home: Builder(
          builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                      width: contentWidth ?? windowWidth,
                      child: LibraryView(
                          api: api,
                          onOpenFavorites: () {},
                          onOpenHistory: () {})),
                ),
              )),
    ),
  ));
  await tester.pumpAndSettle();
}

class _LibraryAuth extends AuthController {
  String? _testToken = 'library-session';
  int _generation = 0;
  @override
  String? get token => _testToken;
  @override
  bool get isLoggedIn => _testToken != null;
  @override
  int get sessionGeneration => _generation;

  void rotateToken() {
    _testToken = 'refreshed-library-session';
    notifyListeners();
  }

  void clearSession() {
    _testToken = null;
    _generation++;
    notifyListeners();
  }
}

class _LibraryApi extends UserApi {
  bool fail = false;
  int loads = 0;
  String? openedPlaylist;
  String? createdName;
  String? createdToken;

  @override
  Future<Map<String, dynamic>> createPlaylist(
      String name, String? description, String token) async {
    createdName = name;
    createdToken = token;
    return {'id': 'new-playlist', 'name': name, 'source': 'local'};
  }

  @override
  Future<List<Map<String, dynamic>>> getOwnedPlaylists(String token) async {
    loads++;
    if (fail) throw StateError('Network unavailable');
    return [
      {
        'id': 'playlist-with-string-id',
        'name': '通勤歌单',
        'source': 'local',
        'songCount': 12,
        'coverImgUrl': null
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getFavorites(String token) async => [
        {'songId': 'favorite-1', 'songName': '晚风', 'source': 'netease'},
        {'songId': 'favorite-2', 'songName': '明天见', 'source': 'netease'},
      ];

  @override
  Future<List<Map<String, dynamic>>> getUserPlaylistSongs(
      String playlistId, String token) async {
    openedPlaylist = playlistId;
    return [];
  }
}
