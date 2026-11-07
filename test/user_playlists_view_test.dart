import 'dart:async';

import 'package:duck_music/core/api/user_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/profile/user_library_view.dart';
import 'package:duck_music/features/profile/user_playlists_view.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final current in [
    (id: '一', source: 'qq', staysLiked: false),
    (id: '二', source: 'qq', staysLiked: true),
    (id: '一', source: 'netease', staysLiked: true),
  ]) {
    testWidgets(
        'removing favorite updates only matching current ${current.id}/${current.source}',
        (tester) async {
      final song = _librarySong('一');
      final remove = Completer<void>();
      late _LibraryPlayer player;
      await _pumpLibrary(tester,
          kind: UserLibraryKind.favorites,
          playerFactory: (settings) => player = _LibraryPlayer(settings, song),
          loader: () async => [song],
          onRemove: (_) => remove.future);
      player.setLiked(true);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多：歌曲 一'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消喜欢'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消喜欢'));
      await tester.pump();
      player.currentSong = _librarySong(current.id, source: current.source);
      remove.complete();
      await tester.pumpAndSettle();
      expect(player.liked, current.staysLiked);
    });
  }

  for (final entry in {
    UserLibraryKind.playlist: '从歌单移除',
    UserLibraryKind.favorites: '取消喜欢',
    UserLibraryKind.history: '删除播放记录',
  }.entries) {
    testWidgets('${entry.key} removal is confirmed from the song menu',
        (tester) async {
      final songs = [_librarySong('一'), _librarySong('二')];
      final removed = <String>[];
      await _pumpLibrary(tester,
          kind: entry.key,
          loader: () async => List.of(songs),
          onRemove: (song) async {
            removed.add(song.id);
            songs.removeWhere((item) => item.id == song.id);
          });
      await tester.pumpAndSettle();
      expect(find.byTooltip('删除'), findsNothing);
      await tester.tap(find.byTooltip('更多：歌曲 一'));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      await tester.ensureVisible(find.text(entry.value));
      await tester.tap(find.text(entry.value));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(removed, isEmpty);
      expect(find.text('歌曲 一'), findsOneWidget);
      await tester.tap(find.byTooltip('更多：歌曲 一'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(entry.value));
      await tester.tap(find.text(entry.value));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, entry.value));
      await tester.pumpAndSettle();
      expect(removed, ['一']);
      expect(find.text('歌曲 一'), findsNothing);
      expect(find.text('歌曲 二'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('first library load distinguishes loading from an empty list',
      (tester) async {
    final pending = Completer<List<Song>>();
    await _pumpLibrary(tester, loader: () => pending.future);

    expect(find.textContaining('0 首'), findsNothing);
    expect(find.textContaining('正在加载歌曲'), findsOneWidget);
    expect(find.byType(GSkeletonList), findsOneWidget);
    expect(find.text('歌单为空'), findsNothing);

    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.textContaining('0 首歌曲'), findsOneWidget);
    expect(find.text('歌单为空'), findsOneWidget);
    expect(find.text('在歌曲菜单中选择“收藏到歌单”，添加到这个歌单'), findsOneWidget);
  });

  testWidgets('refresh preserves visible songs and scroll position',
      (tester) async {
    final pending = Completer<List<Song>>();
    final songs = List.generate(24, (index) => _librarySong('$index'));
    var loads = 0;
    await _pumpLibrary(tester,
        loader: () => ++loads == 1 ? Future.value(songs) : pending.future);
    await tester.pumpAndSettle();
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('歌曲 10'), 200, scrollable: list);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('歌曲 10'));
    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    final refreshDone = refresh.onRefresh();
    await tester.pump();

    expect(find.text('歌曲 10'), findsOneWidget);
    expect(tester.getTopLeft(find.text('歌曲 10')), before);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(GSkeletonList), findsNothing);
    pending.complete(songs);
    await refreshDone;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('歌曲 10')), before);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('failed refresh keeps songs and offers a working retry',
      (tester) async {
    var loads = 0;
    await _pumpLibrary(tester, loader: () async {
      loads++;
      if (loads == 2) throw StateError('offline');
      return [_librarySong(loads == 1 ? '原来' : '更新')];
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新列表'));
    await tester.pumpAndSettle();

    expect(find.text('歌曲 原来'), findsOneWidget);
    expect(find.text('刷新失败，仍显示上次的内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('歌曲 更新'), findsOneWidget);
    expect(find.text('刷新失败，仍显示上次的内容'), findsNothing);
  });

  testWidgets('changing the library never reuses the previous library songs',
      (tester) async {
    final next = Completer<List<Song>>();
    final stale = Completer<List<Song>>();
    var loads = 0;
    final title = ValueNotifier('歌单 A');
    addTearDown(title.dispose);
    await _pumpLibrary(tester,
        loader: () =>
            ++loads == 1 ? Future.value([_librarySong('A')]) : stale.future,
        title: title,
        nextLoader: () => next.future);
    await tester.pumpAndSettle();
    final refreshDone = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    title.value = '歌单 B';
    await tester.pump();
    expect(find.text('歌曲 A'), findsNothing);
    expect(find.textContaining('正在加载歌曲'), findsOneWidget);
    stale.complete([_librarySong('旧请求')]);
    await refreshDone;
    await tester.pump();
    expect(find.text('歌曲 旧请求'), findsNothing);
    next.complete([_librarySong('B')]);
    await tester.pumpAndSettle();
    expect(find.text('歌曲 B'), findsOneWidget);
  });

  testWidgets('desktop library filter opens and clears through its icon',
      (tester) async {
    await _pumpLibrary(tester,
        size: const Size(1440, 900),
        loader: () async => [_librarySong('一'), _librarySong('二')]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('筛选歌曲'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '歌曲 二');
    await tester.pumpAndSettle();
    expect(find.text('歌曲 一'), findsNothing);
    await tester.tap(find.byTooltip('筛选歌曲'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('歌曲 一'), findsOneWidget);
  });

  for (final width in [320.0, 1440.0]) {
    testWidgets('library menu follows its toolbar button at width $width',
        (tester) async {
      await _pumpLibrary(tester,
          size: Size(width, 900), loader: () async => [_librarySong('一')]);
      await tester.pumpAndSettle();
      final anchor = tester.getRect(find.byTooltip('更多'));
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byType(PopupMenuItem<String>));
      expect(menu.top, greaterThanOrEqualTo(anchor.bottom));
      expect(menu.right, closeTo(anchor.right, 16));
      expect(menu.left, greaterThanOrEqualTo(0));
    });
  }

  testWidgets('playlist directory supports single and batch deletion',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {
      'auth_token': 'playlist-token',
    });
    final auth = AuthController();
    await auth.load();
    final api = _PlaylistApi();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthController>.value(
        value: auth,
        child: MaterialApp(home: UserPlaylistsView(api: api)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的歌单'), findsWidgets);
    expect(find.text('收藏歌单'), findsWidgets);
    expect(find.byTooltip('管理歌单'), findsOneWidget);
    expect(find.byTooltip('删除歌单'), findsNWidgets(2));

    await tester.tap(find.byTooltip('管理歌单'));
    await tester.pump();
    expect(find.text('全选'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.pump();
    await tester.tap(find.byTooltip('删除所选歌单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(api.deletedOwned, ['1']);
    expect(api.removedFavorites, [('qq', 'remote-2')]);
  });

  testWidgets('owned playlist supports track deletion management',
      (tester) async {
    final settings = SettingsController();
    final player = PlayerController(settings: settings);
    addTearDown(settings.dispose);
    addTearDown(player.dispose);
    final song = Song(
      id: 'song-1',
      name: '歌曲一',
      source: 'qq',
      artists: const [Artist(id: 0, name: '歌手')],
      album: const Album(id: 0, name: '专辑'),
      durationMs: 180000,
      libraryId: 'item-1',
    );
    final song2 = Song(
      id: 'song-2',
      name: '歌曲二',
      source: 'qq',
      artists: const [Artist(id: 0, name: '歌手')],
      album: const Album(id: 0, name: '专辑'),
      durationMs: 180000,
      libraryId: 'item-2',
    );
    final removed = <String>[];

    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerController>.value(
        value: player,
        child: MaterialApp(
          home: UserLibraryView(
            title: '我的歌单',
            kind: UserLibraryKind.playlist,
            loader: () async => [song, song2],
            onRemove: (value) async => removed.add(value.libraryId!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('管理歌曲'), findsOneWidget);
    await tester.tap(find.byTooltip('管理歌曲'));
    await tester.pump();
    await tester.tap(find.text('全选'));
    await tester.pump();
    await tester.tap(find.byTooltip('删除所选歌曲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(removed, ['item-1', 'item-2']);
  });

  for (final size in [const Size(320, 700), const Size(812, 375)]) {
    testWidgets('owned playlist remains usable with large text at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = SettingsController();
      final player = PlayerController(settings: settings);
      addTearDown(settings.dispose);
      addTearDown(player.dispose);
      var syncs = 0;
      await tester.pumpWidget(
        ChangeNotifierProvider<PlayerController>.value(
          value: player,
          child: MaterialApp(
            theme: AppTheme.byId('dark').data,
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
              ),
              child: UserLibraryView(
                title: '那些陪我度过漫长夜晚的音乐',
                loader: () async => [
                  for (var index = 0; index < 8; index++)
                    Song(
                      id: '$index',
                      name: '歌曲 $index',
                      source: 'qq',
                      artists: const [Artist(id: 1, name: '歌手')],
                      album: const Album(id: 1, name: '专辑'),
                      durationMs: 180000,
                    ),
                ],
                onRemove: (_) async {},
                onSync: () async => syncs++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('同步歌单'));
      await tester.pumpAndSettle();
      expect(syncs, 1);
      await tester.tap(find.byTooltip('搜索歌曲'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextField),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), '歌曲 7');
      await tester.pumpAndSettle();
      final result = find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == '歌曲 7');
      await tester.ensureVisible(result);
      await tester.pumpAndSettle();
      expect(result.hitTestable(), findsOneWidget);
      expect(find.text('歌曲 0'), findsNothing);
      await tester.tap(find.byTooltip('管理歌曲'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('全选'));
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('1/1 已选'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('退出管理'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('筛选歌曲'));
      await tester.tap(find.byTooltip('筛选歌曲'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.scrollUntilVisible(
        find.text('歌曲 0'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('歌曲 0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Song _librarySong(String id, {String source = 'qq'}) => Song(
      id: id,
      name: '歌曲 $id',
      source: source,
      artists: const [Artist(id: 0, name: '歌手')],
      album: const Album(id: 0, name: '专辑'),
      durationMs: 180000,
    );

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required Future<List<Song>> Function() loader,
  Size size = const Size(390, 844),
  ValueNotifier<String>? title,
  Future<List<Song>> Function()? nextLoader,
  Future<void> Function(Song)? onRemove,
  UserLibraryKind kind = UserLibraryKind.playlist,
  PlayerController Function(SettingsController)? playerFactory,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 24);
  final settings = SettingsController();
  final player =
      playerFactory?.call(settings) ?? PlayerController(settings: settings);
  final auth = AuthController();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
    settings.dispose();
    auth.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
  Widget library(String name) => UserLibraryView(
        title: name,
        loader: name == '歌单 B' ? nextLoader! : loader,
        kind: kind,
        onRemove: onRemove,
      );
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<PlayerController>.value(value: player),
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ChangeNotifierProvider<SettingsController>.value(value: settings),
    ],
    child: MaterialApp(
      theme: AppTheme.byId('dark').data,
      home: title == null
          ? library('测试歌单')
          : ValueListenableBuilder<String>(
              valueListenable: title,
              builder: (_, name, __) => library(name),
            ),
    ),
  ));
}

class _LibraryPlayer extends PlayerController {
  _LibraryPlayer(SettingsController settings, this.currentSong)
      : super(settings: settings);
  Song currentSong;
  @override
  Song get current => currentSong;
}

class _PlaylistApi extends UserApi {
  final deletedOwned = <String>[];
  final removedFavorites = <(String, String)>[];

  @override
  Future<List<Map<String, dynamic>>> getUserPlaylists(String token) async => [
        {
          'id': 1,
          'name': '我的歌单',
          'source': 'local',
          'sourceId': 'local-1',
        },
        {
          'id': 2,
          'name': '收藏歌单',
          'source': 'qq',
          'sourceId': 'remote-2',
        },
      ];

  @override
  Future<void> deleteUserPlaylist(String playlistId, String token) async {
    deletedOwned.add(playlistId);
  }

  @override
  Future<void> removePlaylistFavorite(
    String source,
    String playlistId,
    String token,
  ) async {
    removedFavorites.add((source, playlistId));
  }
}
