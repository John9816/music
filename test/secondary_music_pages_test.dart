import 'dart:convert';
import 'dart:io';

import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/api/user_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/artist_info.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/song_download_service.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/library/downloads_view.dart';
import 'package:duck_music/features/profile/user_playlists_view.dart';
import 'package:duck_music/features/search/artist_names_link.dart';
import 'package:duck_music/widgets/async_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('playlist search keeps a full text line at twice the text size',
      (tester) async {
    final api = _PlaylistApi();
    await _pumpPlaylists(tester, api: api, textScale: 2);
    final field = find.byType(TextField);
    await tester.enterText(field, '夜晚');
    await tester.pumpAndSettle();

    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(editable.size.height,
        greaterThanOrEqualTo(editable.preferredLineHeight));
    expect(find.text('夜晚歌单'), findsOneWidget);
    expect(find.text('清晨歌单'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'playlist artwork aligns with search and deletion stays confirmed',
      (tester) async {
    final api = _PlaylistApi();
    await _pumpPlaylists(tester, api: api);

    final artwork = find.byType(AsyncCover);
    expect(artwork, findsNWidgets(2));
    final artworkRect = tester.getRect(artwork.first);
    expect(artworkRect.width, artworkRect.height);
    expect(artworkRect.left, tester.getRect(find.byType(TextField)).left);

    await tester.tap(find.byTooltip('删除歌单').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('夜晚歌单'), findsOneWidget);
    expect(api.deleted, isEmpty);

    await tester.tap(find.byTooltip('删除歌单').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(api.deleted, ['1']);
    expect(find.text('夜晚歌单'), findsNothing);
    expect(find.text('清晨歌单'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'download artwork aligns with its summary and deletion removes the file',
      (tester) async {
    _configureView(tester);
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('secondary-downloads-'),
    );
    final audio = File('${directory!.path}/saved.mp3');
    final entry = DownloadedSong(
      song: Song(
        id: 'saved',
        name: '下载歌曲',
        source: 'qq',
        artists: const [Artist(id: 1, name: '歌手')],
        album: const Album(id: 1, name: '专辑'),
        durationMs: 180000,
      ),
      path: audio.path,
      quality: 'exhigh',
      sizeBytes: 8388608,
      downloadedAt: DateTime(2026, 11, 7),
    );
    final client = MockClient((_) async => http.Response('', 500));
    final downloads = SongDownloadService.forTesting(
      musicApi: MusicApi(),
      client: client,
      downloadsDirectory: () async => directory,
    );
    await tester.runAsync(() async {
      await audio.writeAsBytes([1, 2, 3, 4]);
      await File('${directory.path}/.downloads.json').writeAsString(
        jsonEncode([entry.toJson()]),
      );
      await downloads.initialize();
    });
    final settings = SettingsController();
    final player = PlayerController(settings: settings);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      downloads.dispose();
      player.dispose();
      settings.dispose();
      client.close();
      await directory.delete(recursive: true);
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SongDownloadService>.value(value: downloads),
        ChangeNotifierProvider<PlayerController>.value(value: player),
      ],
      child: _app(const DownloadsView()),
    ));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(AsyncCover)).left,
        tester.getRect(find.textContaining('已下载 1 首')).left);
    await tester.tap(find.byTooltip('清空下载'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(downloads.downloads, hasLength(1));

    await tester.tap(find.byTooltip('删除 下载歌曲'));
    for (var attempt = 0;
        attempt < 100 && find.text('还没有下载的歌曲').evaluate().isEmpty;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('还没有下载的歌曲'), findsOneWidget);
    expect(await tester.runAsync(audio.exists), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'artist selection can reach the final collaborator with large text',
      (tester) async {
    _configureView(tester, size: const Size(320, 568));
    await tester.pumpWidget(_app(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => openArtistInfo(
              context,
              artists: [
                for (var index = 0; index < 12; index++)
                  Artist(id: index + 1, name: '合作歌手 $index', picUrl: ' '),
              ],
              loader: () async => const ArtistInfo(
                name: '合作歌手 11',
                profile: '最后一位歌手的简介',
              ),
              catalogLoader: () async =>
                  const ArtistCatalog(songs: [], albums: []),
            ),
            child: const Text('选择合作歌手'),
          ),
        ),
      ),
      textScale: 2,
    ));
    await tester.tap(find.text('选择合作歌手'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('合作歌手 11'),
      180,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('合作歌手 11'));
    await tester.pumpAndSettle();
    expect(find.text('合作歌手 11').hitTestable(), findsOneWidget);
    await tester.tap(find.text('合作歌手 11'));
    await tester.pumpAndSettle();
    expect(find.text('最后一位歌手的简介'), findsOneWidget);
    expect(find.text('选择歌手'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget home, {double textScale = 1}) => MaterialApp(
      theme:
          AppTheme.byId('dark').data.copyWith(platform: TargetPlatform.android),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

void _configureView(WidgetTester tester, {Size size = const Size(320, 700)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _pumpPlaylists(
  WidgetTester tester, {
  required _PlaylistApi api,
  double textScale = 1,
}) async {
  _configureView(tester);
  SharedPreferences.setMockInitialValues(
      const {'auth_token': 'playlist-token'});
  final auth = AuthController();
  await auth.load();
  addTearDown(auth.dispose);
  await tester.pumpWidget(ChangeNotifierProvider<AuthController>.value(
    value: auth,
    child: _app(UserPlaylistsView(api: api), textScale: textScale),
  ));
  await tester.pumpAndSettle();
}

class _PlaylistApi extends UserApi {
  final deleted = <String>[];

  @override
  Future<List<Map<String, dynamic>>> getUserPlaylists(String token) async => [
        if (!deleted.contains('1'))
          {'id': 1, 'name': '夜晚歌单', 'source': 'local', 'trackCount': 20},
        {'id': 2, 'name': '清晨歌单', 'source': 'local', 'trackCount': 8},
      ];

  @override
  Future<void> deleteUserPlaylist(String playlistId, String token) async {
    expect(token, 'playlist-token');
    deleted.add(playlistId);
  }
}
