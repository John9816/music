import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/playlist.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/playlists/playlist_detail_view.dart';
import 'package:duck_music/widgets/song_action_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('mobile playlist preserves download, filtering and sorting',
      (tester) async {
    await _pumpPlaylist(tester);

    final searchIcon = find.descendant(
        of: find.byTooltip('搜索歌曲'), matching: find.byType(Icon));
    expect(tester.widget<Icon>(searchIcon).color, Colors.white);

    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('176首 · 32分钟'), findsOneWidget);
    expect(find.byTooltip('收藏歌单').hitTestable(), findsOneWidget);
    expect(
        find.byKey(const ValueKey('mobile-play-panel-pinned')), findsNothing);

    await tester.tap(find.byTooltip('下载全部'));
    await tester.pumpAndSettle();
    expect(find.text('将下载歌单中的 20 首歌曲。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('倒序排列'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('测试歌曲 19')).dy,
      lessThan(tester.getTopLeft(find.text('测试歌曲 18')).dy),
    );

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('恢复原排序'), findsOneWidget);
    await tester.tap(find.text('筛选歌曲'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '测试歌曲 19');
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == '测试歌曲 19'),
        findsOneWidget);
    expect(find.text('测试歌曲 18'), findsNothing);
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    expect(find.text('测试歌曲 18'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('large text playlist controls remain reachable at $size',
        (tester) async {
      await _pumpPlaylist(tester, size: size, textScale: 2);
      expect(tester.takeException(), isNull);

      final scroll =
          tester.widget<CustomScrollView>(find.byType(CustomScrollView));
      final hero = find.byKey(const ValueKey('mobile-playlist-hero-cover'));
      scroll.controller!.jumpTo(tester.getSize(hero).height + 80);
      await tester.pumpAndSettle();

      final pinned = find.byKey(const ValueKey('mobile-play-panel-pinned'));
      expect(pinned, findsOneWidget);
      expect(
        find.descendant(of: pinned, matching: find.text('播放全部')).hitTestable(),
        findsOneWidget,
      );
      final download = find.descendant(
        of: pinned,
        matching: find.byTooltip('下载全部'),
      );
      expect(download.hitTestable(), findsOneWidget);
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(find.text('下载全部歌曲'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      final visibleRows = find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('mobile-playlist-song-'),
      );
      expect(visibleRows, findsWidgets);
      for (final element in visibleRows.evaluate()) {
        final row = element.renderObject! as RenderBox;
        expect(row.size.height, greaterThan(80));
      }
      expect(find.byType(SongActionButton), findsWidgets);
      expect(tester.takeException(), isNull);

      // Returning to the top must release the pinned controls after using
      // the actual header height as the scrolling threshold.
      scroll.controller!.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('mobile-play-panel-pinned')), findsNothing);
      expect(find.byTooltip('搜索歌曲').hitTestable(), findsOneWidget);
    });
  }
}

Future<void> _pumpPlaylist(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final settings = SettingsController();
  final player = PlayerController(settings: settings);
  final auth = AuthController();
  addTearDown(settings.dispose);
  addTearDown(player.dispose);
  addTearDown(auth.dispose);
  final songs = List.generate(
    20,
    (index) => Song(
      id: 'song-$index',
      name: index == 0 ? '去见你' : '测试歌曲 $index',
      source: 'netease',
      artists: const [Artist(id: 1, name: '徐秉龙')],
      album: const Album(id: 1, name: '去见你'),
      durationMs: 96000,
      availableQualities: const ['flac'],
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<AuthController>.value(value: auth),
      ],
      child: MaterialApp(
        theme:
            AppTheme.byId('light').data.copyWith(platform: TargetPlatform.iOS),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: EdgeInsets.only(
                top: size.height > size.width ? 47 : 0, bottom: 34),
            textScaler: TextScaler.linear(textScale),
          ),
          child: PlaylistDetailView(
            playlist: Playlist(
              id: 7511,
              name: '我喜欢的音乐',
              creatorName: 'Smile 大虎',
              trackCount: 176,
              playCount: 3488,
            ),
            loader: () async => songs,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
