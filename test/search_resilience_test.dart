import 'dart:async';
import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/search/search_view.dart';
import 'package:duck_music/features/search/artist_detail_view.dart';
import 'package:duck_music/features/playlists/playlist_detail_view.dart';
import 'package:duck_music/widgets/song_row.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _SearchRequest = ({
  String keyword,
  String type,
  int page,
  String source
});

late Future<http.Response> Function(_SearchRequest) _respond;
final _requests = <_SearchRequest>[];
final _detailRequests = <Uri>[];

void main() {
  setUpAll(() {
    http.runWithClient(
      () => ApiClient.instance,
      () => MockClient((request) {
        if (request.url.path != '/api/v1/music/search') {
          _detailRequests.add(request.url);
          return Future.value(_emptyResults());
        }
        expect(request.url.queryParameters['pageSize'], '30');
        final search = (
          keyword: request.url.queryParameters['keyword']!,
          type: request.url.queryParameters['type']!,
          page: int.parse(request.url.queryParameters['page']!),
          source: request.url.queryParameters['source']!,
        );
        _requests.add(search);
        return _respond(search);
      }),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    _requests.clear();
    _detailRequests.clear();
    _respond = (request) async => request.type == 'SONG' && request.page == 1
        ? _songs(30)
        : _emptyResults();
  });

  testWidgets('saved search source remains separate from the browsing source',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {
      'music_source': 'kuwo',
      'search_music_source': 'qq',
    });
    await _pumpSearch(tester);
    expect(_requests.map((request) => request.source), everyElement('qq'));
    expect(_requests, hasLength(4));

    await tester.tap(find.byKey(const ValueKey('search_source_netease')));
    await tester.pumpAndSettle();
    expect(_requests, hasLength(8));
    expect(_requests.skip(4).map((request) => request.source),
        everyElement('netease'));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('music_source'), 'kuwo');
    expect(preferences.getString('search_music_source'), 'netease');
    final restored = SettingsController();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.source, 'kuwo');
    expect(restored.searchSource, 'netease');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid source changes reset pages and reject stale results',
      (tester) async {
    final green = Completer<http.Response>();
    _respond = (request) async => switch (request.source) {
          'qq' => await green.future,
          'kuwo' => _songs(1, start: 90, source: 'kuwo'),
          _ => _songs(30, start: (request.page - 1) * 30),
        };
    await _pumpSearch(tester, size: const Size(390, 844));
    await _tapPagination(tester, '下一页');
    expect(find.text('第 2 页'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('search_source_qq')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search_source_kuwo')));
    await tester.pumpAndSettle();
    green.complete(_songs(1, start: 60, source: 'qq'));
    await tester.pumpAndSettle();

    expect(find.text('第 1 页'), findsOneWidget);
    expect(find.text('歌曲 90'), findsOneWidget);
    expect(find.text('歌曲 60'), findsNothing);
    expect(tester.widget<SongRow>(find.byType(SongRow)).song.source, 'kuwo');
    expect(_requests.map((request) => (request.source, request.page)),
        [('netease', 1), ('netease', 2), ('qq', 1), ('kuwo', 1)]);
    expect(
        tester
            .element(find.byType(SearchView))
            .read<SettingsController>()
            .source,
        'netease');
    expect(tester.takeException(), isNull);
  });

  for (final kind in ['歌手', '专辑', '歌单']) {
    testWidgets(
        '$kind details inherit the search source when metadata omits it',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {
        'music_source': 'netease',
        'search_music_source': 'qq',
      });
      _respond = (request) async => switch (request.type) {
            'ARTIST' => _artists(1, source: null),
            'ALBUM' => _success(const {
                'albums': [
                  {'id': '22', 'name': '搜索专辑', 'artist': '测试歌手'}
                ],
              }),
            'PLAYLIST' => _playlists(source: null),
            _ => _emptyResults(),
          };
      await _pumpSearch(tester, size: const Size(390, 844));
      await _tapType(tester, kind);
      final title = switch (kind) {
        '歌手' => '歌手 0',
        '专辑' => '搜索专辑',
        _ => '一张适合安静工作时聆听的精选歌单',
      };
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      if (kind == '歌手') {
        expect(
            tester
                .widget<ArtistDetailView>(find.byType(ArtistDetailView))
                .source,
            'qq');
      } else {
        expect(
            tester
                .widget<PlaylistDetailView>(find.byType(PlaylistDetailView))
                .playlist
                .source,
            'qq');
      }
      expect(_detailRequests, isNotEmpty);
      expect(_detailRequests.map((uri) => uri.queryParameters['source']),
          everyElement('qq'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an empty desktop next page retains the last successful results',
      (tester) async {
    await _pumpSearch(tester);
    expect(find.text('歌曲 0'), findsOneWidget);

    await _tapPagination(tester, '下一页');

    expect(find.text('第 1 页'), findsOneWidget);
    expect(find.text('歌曲 0'), findsOneWidget);
    expect(find.byTooltip('上一页'), findsOneWidget);
    final requestCount = _requests.length;
    await _tapPagination(tester, '下一页');
    expect(_requests.length, requestCount,
        reason: 'An empty next page must disable further next-page requests.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry requests the failed page and preserves usable old results',
      (tester) async {
    var secondPageAttempts = 0;
    _respond = (request) async {
      if (request.page == 1) return _songs(30);
      if (++secondPageAttempts == 1) return _unavailable();
      return _songs(1, start: 30);
    };
    await _pumpSearch(tester, size: const Size(390, 844));

    await _tapPagination(tester, '下一页');
    expect(find.text('歌曲 0'), findsOneWidget);
    expect(find.text('第 1 页'), findsOneWidget);
    expect(find.textContaining('第 2 页加载失败'), findsOneWidget);
    final retry = find.byTooltip(RegExp('重试'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(find.text('歌曲 30'), findsOneWidget);
    expect(find.text('第 2 页'), findsOneWidget);
    expect(_requests.map((request) => request.page), [1, 2, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search uses the content width inside a wide window',
      (tester) async {
    await _pumpSearch(tester, contentWidth: 390);

    expect(tester.getSize(find.byType(SearchView)).width, 390);
    expect(find.text('单曲').hitTestable(), findsOneWidget);
    expect(_requests.map((request) => request.type), ['SONG']);
    expect(find.byTooltip('下一页').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large-text phone pagination keeps both directions usable',
      (tester) async {
    _respond = (request) async =>
        _songs(request.page == 1 ? 30 : 1, start: request.page == 1 ? 0 : 30);
    await _pumpSearch(tester, size: const Size(320, 700), textScale: 2);
    final initialRequests = _requests.length;
    await _tapPagination(tester, '上一页');
    expect(_requests.length, initialRequests);
    await _tapPagination(tester, '下一页');
    expect(find.text('第 2 页'), findsOneWidget);
    expect(find.text('歌曲 30'), findsOneWidget);
    await _tapPagination(tester, '上一页');
    expect(find.text('第 1 页'), findsOneWidget);
    expect(find.text('歌曲 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shrinking completed combined results keeps artists visible',
      (tester) async {
    _respond = (request) async =>
        request.type == 'ARTIST' ? _artists(2) : _emptyResults();
    await _pumpSearch(tester);
    expect(find.text('歌手 0'), findsOneWidget);
    final requestCount = _requests.length;

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    expect(find.text('歌手 0').hitTestable(), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '测试');
    expect(_requests.length, requestCount,
        reason: 'Changing the window size must not issue a different search.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanding an artist search keeps its scope on the next page',
      (tester) async {
    _respond = (request) async => request.type == 'ARTIST'
        ? _artists(request.page == 1 ? 30 : 1,
            start: request.page == 1 ? 0 : 30)
        : _emptyResults();
    await _pumpSearch(tester, size: const Size(390, 844));
    await _tapType(tester, '歌手');
    expect(find.text('歌手 0'), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    _requests.clear();
    await _tapPagination(tester, '下一页');

    expect(find.text('歌手 30'), findsOneWidget);
    expect(_requests,
        [(keyword: '测试', type: 'ARTIST', page: 2, source: 'netease')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a response arriving after shrinking keeps the requested scope',
      (tester) async {
    final artists = Completer<http.Response>();
    addTearDown(() {
      if (!artists.isCompleted) artists.complete(_emptyResults());
    });
    _respond = (request) async =>
        request.type == 'ARTIST' ? await artists.future : _emptyResults();
    await _pumpSearch(tester, settle: false);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    artists.complete(_artists(1));
    await tester.pumpAndSettle();

    expect(find.text('歌手 0').hitTestable(), findsOneWidget);
    expect(_requests.length, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('playlist results fit narrow content with large text',
      (tester) async {
    _respond = (request) async =>
        request.type == 'PLAYLIST' ? _playlists() : _emptyResults();
    await _pumpSearch(tester, contentWidth: 320, textScale: 2);
    await _tapType(tester, '歌单');

    expect(find.text('一张适合安静工作时聆听的精选歌单').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('combined playlist cards expand for large text', (tester) async {
    _respond = (request) async =>
        request.type == 'PLAYLIST' ? _playlists() : _emptyResults();
    await _pumpSearch(tester, textScale: 2);

    expect(find.text('一张适合安静工作时聆听的精选歌单').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact macOS search title avoids native window controls',
      (tester) async {
    await _pumpSearch(tester, size: const Size(700, 700));
    expect(tester.getTopLeft(find.text('搜索结果')).dx, greaterThanOrEqualTo(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading frames fit a height-constrained search pane',
      (tester) async {
    final songs = Completer<http.Response>();
    addTearDown(() {
      if (!songs.isCompleted) songs.complete(_emptyResults());
    });
    _respond = (request) async =>
        request.type == 'SONG' ? await songs.future : _emptyResults();
    await _pumpSearch(
      tester,
      contentWidth: 1017.6,
      contentHeight: 700,
      initialQuery: '',
      settle: false,
    );

    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump();
    expect(find.byType(GSkeletonList), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'The immediate loading frame must fit before debounce ends.');

    await tester.pump(const Duration(milliseconds: 400));
    expect(_requests.length, 4);
    expect(find.byType(GSkeletonList), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'Loading must still fit while the HTTP response is pending.');

    songs.complete(_songs(1));
    await tester.pumpAndSettle();
    expect(find.text('歌曲 0'), findsOneWidget);
    expect(find.byType(GSkeletonList), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short landscape keeps search controls and results reachable',
      (tester) async {
    await _pumpSearch(
      tester,
      size: const Size(812, 375),
      contentHeight: 230,
      textScale: 1.5,
      initialQuery: '',
    );
    expect(tester.takeException(), isNull);

    await _tapType(tester, '单曲');
    final source = find.byKey(const ValueKey('search_source_netease'));
    await tester.ensureVisible(source);
    await tester.pumpAndSettle();
    expect(source.hitTestable(), findsOneWidget);

    final field = find.byType(TextField);
    await tester.scrollUntilVisible(
      field,
      -180,
      scrollable: find
          .byWidgetPredicate((widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down)
          .first,
    );
    await tester.enterText(field, '测试');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final song = find.text('歌曲 0');
    await tester.ensureVisible(song);
    await tester.pumpAndSettle();
    expect(song.hitTestable(), findsOneWidget);
    await _tapPagination(tester, '下一页');
    expect(find.text('第 1 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSearch(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  double? contentWidth,
  double? contentHeight,
  double textScale = 1,
  String initialQuery = '测试',
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final settings = SettingsController();
  await settings.load();
  final player = PlayerController(settings: settings);
  final auth = AuthController();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
    settings.dispose();
    auth.dispose();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<AuthController>.value(value: auth),
      ],
      child: MaterialApp(
        theme: AppTheme.byId('dark').data.copyWith(
              platform: TargetPlatform.macOS,
            ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: contentWidth,
            height: contentHeight,
            child: SearchView(initialQuery: initialQuery),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _tapPagination(WidgetTester tester, String label) async {
  final button = find.byTooltip(label);
  if (button.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      button,
      400,
      scrollable: find
          .byWidgetPredicate((widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down)
          .first,
    );
  }
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _tapType(WidgetTester tester, String label) async {
  final button = find.widgetWithText(GPressScale, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

http.Response _songs(int count, {int start = 0, String source = 'netease'}) =>
    _success({
      'list': List.generate(count, (index) {
        final id = start + index;
        return {
          'id': '$id',
          'name': '歌曲 $id',
          'source': source,
          'artist': '测试歌手',
          'artistId': '10',
          'artistIds': ['10'],
          'albumId': '20',
          'album': '测试专辑',
          'coverUrl': null,
          'durationMs': 180000,
          'availableQualities': ['standard'],
        };
      }),
    });

http.Response _artists(int count,
        {int start = 0, String? source = 'netease'}) =>
    _success({
      'artists': List.generate(count, (index) {
        final id = start + index;
        return {
          'id': '$id',
          'name': '歌手 $id',
          'source': source,
          'coverUrl': null,
          'trackCount': 10,
        };
      }),
    });

http.Response _emptyResults() => _success(const {
      'list': [],
      'playlists': [],
      'albums': [],
      'artists': [],
    });

http.Response _playlists({String? source = 'netease'}) => _success({
      'playlists': [
        {
          'id': '42',
          'name': '一张适合安静工作时聆听的精选歌单',
          'source': source,
          'coverUrl': null,
          'description': '适合专注与放松的音乐',
          'creatorName': '测试歌单创建者',
          'trackCount': 15,
          'playCount': 0,
        },
      ],
    });

http.Response _success(Map<String, dynamic> data) => http.Response(
      jsonEncode({'code': 0, 'message': 'ok', 'data': data}),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _unavailable() => http.Response(
      jsonEncode({'code': 503, 'message': '服务暂时不可用', 'data': null}),
      503,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
