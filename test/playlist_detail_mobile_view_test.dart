import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/playlist.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/playlists/playlist_detail_view.dart';
import 'package:duck_music/widgets/async_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('mobile playlist detail matches the immersive reference layout',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
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
          theme: AppTheme.byId('light').data.copyWith(
                platform: TargetPlatform.iOS,
              ),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 47, bottom: 34),
            ),
            child: PlaylistDetailView(
              playlist: Playlist(
                id: 7511,
                name: '我喜欢的音乐',
                coverUrl: 'https://example.com/playlist-cover.jpg',
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

    final heroCover = find.byWidgetPredicate(
      (widget) => widget is AsyncCover && widget.size == 112,
    );
    final songCovers = find.byWidgetPredicate(
      (widget) => widget is AsyncCover && widget.size == 44,
    );
    final ambient =
        find.byKey(const ValueKey('mobile-playlist-ambient-background'));
    expect(tester.getTopLeft(ambient), Offset.zero);
    expect(tester.getSize(ambient), const Size(390, 844));
    expect(
      find.descendant(of: ambient, matching: find.byType(ImageFiltered)),
      findsNothing,
    );
    expect(tester.getSize(heroCover), const Size.square(112));
    expect(tester.getSize(songCovers.first), const Size.square(44));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('播放全部'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('mobile-play-panel-pinned')), findsNothing);
    expect(find.text('176首 · 32分钟'), findsOneWidget);
    expect(find.text('分享'), findsNothing);
    expect(find.text('评论'), findsNothing);
    expect(find.text('超清母带'), findsWidgets);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('mobile-playlist-hero-title')),
          )
          .style
          ?.fontSize,
      20,
    );
    expect(tester.widget<Text>(find.text('播放全部')).style?.fontSize, 17);
    expect(tester.widget<Text>(find.text('去见你')).style?.fontSize, 16);
    expect(
      tester
          .widgetList<ColoredBox>(
            find.ancestor(
              of: find.text('去见你'),
              matching: find.byType(ColoredBox),
            ),
          )
          .any((box) => box.color == Colors.transparent),
      isTrue,
    );
    expect(
      Theme.of(tester.element(find.text('播放全部'))).brightness,
      Brightness.light,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -220));
    await tester.pumpAndSettle();

    expect(find.text('我喜欢的音乐'), findsNWidgets(2));
    final pinnedPlayPanel =
        find.byKey(const ValueKey('mobile-play-panel-pinned'));
    expect(pinnedPlayPanel, findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.getTopLeft(pinnedPlayPanel).dy, 111);
    expect(tester.getSize(pinnedPlayPanel).height, 56);
    final pageColor =
        AppTheme.byId('light').data.colorScheme.surfaceContainerLowest;
    final topBarSurface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('mobile-playlist-top-bar-surface')),
    );
    final pinnedSurface = tester.widget<Container>(
      find.byKey(const ValueKey('mobile-play-panel-pinned-surface')),
    );
    expect((topBarSurface.decoration! as BoxDecoration).color, pageColor);
    expect(pinnedSurface.color, pageColor);
    expect(tester.takeException(), isNull);
  });
}
