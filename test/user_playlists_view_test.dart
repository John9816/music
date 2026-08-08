import 'package:duck_music/core/api/user_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/features/profile/user_library_view.dart';
import 'package:duck_music/features/profile/user_playlists_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
