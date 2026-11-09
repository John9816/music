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
        expectSync(request.url.queryParameters['pageSize'], '30');
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

  testWidgets('black source includes artists and albums without changing home',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {
      'music_source': 'kuwo',
      'search_music_source': 'qishui',
    });
    _respond = (_) async => _emptyResults();
    await _pumpSearch(tester);
    expect(_requests.map((r) => r.source), everyElement('qishui'));
    expect(_requests.map((r) => r.type).toSet(),
        {'SONG', 'PLAYLIST', 'ARTIST', 'ALBUM'});
    expect(find.text('艺人'), findsOneWidget);
    expect(find.text('专辑'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('music_source'),
        'kuwo');
  });

  testWidgets('switching artist scope to black source preserves artist scope',
      (tester) async {
    _respond = (_) async => _emptyResults();
    await _pumpSearch(tester, size: const Size(390, 844));
    await _tapType(tester, '艺人');
    _requests.clear();
    await _tapSource(tester, 'qishui');
    expect(_requests.map((r) => r.type), ['ARTIST']);
    expect(find.text('艺人'), findsOneWidget);
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

    await _tapSource(tester, 'netease');
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
    await _scrollNearEnd(tester);
    await _tapSource(tester, 'qq', settle: false);
    await _tapSource(tester, 'kuwo');
    green.complete(_songs(1, start: 60, source: 'qq'));
    await tester.pumpAndSettle();

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

  for (final kind in ['艺人', '专辑', '歌单']) {
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
        '艺人' => '歌手 0',
        '专辑' => '搜索专辑',
        _ => '一张适合安静工作时聆听的精选歌单',
      };
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      if (kind == '艺人') {
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

  testWidgets('an empty next batch keeps results and stops further requests',
      (tester) async {
    await _pumpSearch(tester);
    await _scrollNearEnd(tester);
    await _scrollToBottom(tester);
    expect(find.text('已显示全部结果'), findsOneWidget);
    final requestCount = _requests.length;
    await _scrollNearEnd(tester);
    expect(_requests.length, requestCount);
    await _scrollToTop(tester);
    expect(find.text('歌曲 0'), findsOneWidget);
    expect(find.byTooltip('上一页'), findsNothing);
    expect(find.byTooltip('下一页'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('next batch appends asynchronously without duplicate requests',
      (tester) async {
    final next = Completer<http.Response>();
    addTearDown(() {
      if (!next.isCompleted) next.complete(_emptyResults());
    });
    _respond =
        (request) async => request.page == 1 ? _songs(30) : await next.future;
    await _pumpSearch(tester, size: const Size(390, 844));
    await _scrollNearEnd(tester, settle: false);
    await _scrollToBottom(tester, settle: false);
    final position = _resultPosition(tester);
    final offset = position.pixels;
    position.jumpTo(offset - 10);
    position.jumpTo(offset);
    await tester.pump();
    expect(_requests.map((request) => request.page), [1, 2]);
    expect(find.text('歌曲 29'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-load-more-progress')),
        findsOneWidget);
    next.complete(_songs(1, start: 30));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(offset, 1));
    await _scrollToBottom(tester);
    expect(find.text('歌曲 30'), findsOneWidget);
    await _scrollToTop(tester);
    expect(find.text('歌曲 0'), findsOneWidget);
    expect(_requests.map((request) => request.page), [1, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('combined append keeps existing visible songs in place',
      (tester) async {
    final nextSongs = Completer<http.Response>();
    final nextArtists = Completer<http.Response>();
    addTearDown(() {
      if (!nextSongs.isCompleted) nextSongs.complete(_emptyResults());
      if (!nextArtists.isCompleted) nextArtists.complete(_emptyResults());
    });
    _respond = (request) async => switch ((request.type, request.page)) {
          ('SONG', 1) => _songs(30),
          ('ARTIST', 1) => _artists(1),
          ('SONG', 2) => await nextSongs.future,
          ('ARTIST', 2) => await nextArtists.future,
          _ => _emptyResults(),
        };
    await _pumpSearch(tester, size: const Size(390, 844));
    await _tapType(tester, '全部');
    await _scrollNearEnd(tester, settle: false);
    final before = tester.getTopLeft(find.text('歌曲 29')).dy;
    nextSongs.complete(_songs(1, start: 30));
    nextArtists.complete(_artists(1, start: 1));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('歌曲 29')).dy, closeTo(before, 1));
    await _scrollNearEnd(tester);
    await _scrollToBottom(tester);
    expect(find.text('歌曲 30'), findsOneWidget);
    await _scrollToTop(tester);
    expect(find.text('歌手 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final kind in ['艺人', '专辑', '歌单']) {
    testWidgets('$kind appends the next batch and keeps earlier results',
        (tester) async {
      final apiType = {'艺人': 'ARTIST', '专辑': 'ALBUM', '歌单': 'PLAYLIST'}[kind]!;
      _respond = (request) async => request.type == apiType
          ? _namedResults(apiType, request.page == 1 ? 30 : 1,
              start: request.page == 1 ? 0 : 30)
          : _emptyResults();
      await _pumpSearch(tester, size: const Size(390, 844));
      await _tapType(tester, kind);
      await _scrollNearEnd(tester);
      _resultPosition(tester).jumpTo(_resultPosition(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('${kind == '艺人' ? '歌手' : kind} 30'), findsOneWidget);
      await _scrollToTop(tester);
      expect(find.text('${kind == '艺人' ? '歌手' : kind} 0'), findsOneWidget);
      expect(
          _requests
              .where((request) => request.type == apiType)
              .map((request) => request.page),
          [1, 2]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('retry appends the failed batch and preserves earlier results',
      (tester) async {
    var attempts = 0;
    _respond = (request) async {
      if (request.page == 1) return _songs(30);
      if (++attempts == 1) return _unavailable();
      return _songs(1, start: 30);
    };
    await _pumpSearch(tester, size: const Size(390, 844));
    await _scrollNearEnd(tester);
    await _scrollToBottom(tester);
    expect(find.text('加载更多失败，点击重试'), findsOneWidget);
    await _scrollNearEnd(tester);
    expect(_requests.map((request) => request.page), [1, 2]);
    await _scrollToBottom(tester);
    final retry = find.byKey(const ValueKey('search-load-more-retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    await _scrollToBottom(tester);
    expect(find.text('歌曲 30'), findsOneWidget);
    await _scrollToTop(tester);
    expect(find.text('歌曲 0'), findsOneWidget);
    expect(_requests.map((request) => request.page), [1, 2, 2]);
    expect(tester.takeException(), isNull);
  });

  for (final change in ['query', 'type', 'source', 'clear']) {
    testWidgets('pending next batch is discarded after $change changes',
        (tester) async {
      final next = Completer<http.Response>();
      addTearDown(() {
        if (!next.isCompleted) next.complete(_emptyResults());
      });
      _respond = (request) async {
        if (request.page == 2) return await next.future;
        if (request.type == 'ARTIST') return _artists(1, start: 90);
        if (request.keyword == '新查询' || request.source == 'qq') {
          return _songs(1, start: 90, source: request.source);
        }
        return _songs(30);
      };
      await _pumpSearch(tester, size: const Size(390, 844));
      await _scrollNearEnd(tester, settle: false);
      expect(_requests.last.page, 2);
      await _scrollToTop(tester, settle: false);
      switch (change) {
        case 'query':
          await tester.enterText(find.byType(TextField), '新查询');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
        case 'type':
          await _tapType(tester, '艺人');
        case 'source':
          await _tapSource(tester, 'qq');
        case 'clear':
          await tester.tap(find.byTooltip('清除搜索'));
          await tester.pumpAndSettle();
      }
      next.complete(_songs(1, start: 60));
      await tester.pumpAndSettle();
      expect(find.text('歌曲 60'), findsNothing);
      expect(find.text('歌曲 0'), findsNothing);
      expect(
          find.text(change == 'type'
              ? '歌手 90'
              : change == 'clear'
                  ? '搜索推荐'
                  : '歌曲 90'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('search uses the content width inside a wide window',
      (tester) async {
    await _pumpSearch(tester, contentWidth: 390);

    expect(tester.getSize(find.byType(SearchView)).width, 390);
    expect(find.text('歌曲').hitTestable(), findsOneWidget);
    expect(_requests.map((request) => request.type), ['SONG']);
    expect(find.byTooltip('下一页'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'large-text phone scrolls continuously and keeps controls reachable',
      (tester) async {
    _respond = (request) async =>
        _songs(request.page == 1 ? 30 : 1, start: request.page == 1 ? 0 : 30);
    await _pumpSearch(tester, size: const Size(320, 700), textScale: 2);
    await _scrollNearEnd(tester);
    await _scrollToBottom(tester);
    expect(find.text('歌曲 30'), findsOneWidget);
    await _scrollToTop(tester);
    expect(find.text('歌曲 0'), findsOneWidget);
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'phone starts results below compact search, source and category rows',
      (tester) async {
    await _pumpSearch(tester,
        size: const Size(390, 844), platform: TargetPlatform.android);
    expect(find.text('搜索结果'), findsNothing);
    expect(find.byTooltip('下一页'), findsNothing);
    expect(tester.getTopLeft(find.byType(SongRow).first).dy, lessThan(196));
    expect(tester.getSize(find.byType(EditableText)).width,
        greaterThanOrEqualTo(190));
    expect(tester.getSize(find.widgetWithText(GPressScale, '歌曲')).height,
        greaterThanOrEqualTo(48));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('search-source-picker')))
            .shortestSide,
        greaterThanOrEqualTo(48));
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
    await _tapType(tester, '艺人');
    expect(find.text('歌手 0'), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    _requests.clear();
    await _scrollNearEnd(tester);

    await _scrollToBottom(tester);
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

  testWidgets('compact macOS search toolbar avoids native window controls',
      (tester) async {
    await _pumpSearch(tester, size: const Size(700, 700));
    expect(tester.getTopLeft(find.byType(TextField)).dx,
        greaterThanOrEqualTo(100));
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

    final source = find.byKey(const ValueKey('search-source-picker'));
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
    await tester.scrollUntilVisible(song, 100,
        scrollable: find
            .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .first);
    await tester.pumpAndSettle();
    expect(song.hitTestable(), findsOneWidget);
    await _scrollNearEnd(tester);
    await _scrollToBottom(tester);
    expect(find.text('已显示全部结果'), findsOneWidget);
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
  TargetPlatform platform = TargetPlatform.macOS,
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
              platform: platform,
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

ScrollPosition _resultPosition(WidgetTester tester) => tester
    .widget<CustomScrollView>(
      find.byKey(const ValueKey('search-results-scroll')),
    )
    .controller!
    .position;

Future<void> _scrollNearEnd(WidgetTester tester, {bool settle = true}) async {
  final position = _resultPosition(tester);
  position.jumpTo((position.maxScrollExtent - 80).clamp(0, double.infinity));
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

Future<void> _scrollToBottom(WidgetTester tester, {bool settle = true}) async {
  for (var i = 0; i < 3; i++) {
    final position = _resultPosition(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
  }
  if (settle) await tester.pumpAndSettle();
}

Future<void> _scrollToTop(WidgetTester tester, {bool settle = true}) async {
  _resultPosition(tester).jumpTo(0);
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

Future<void> _tapSource(WidgetTester tester, String source,
    {bool settle = true}) async {
  await _scrollToTop(tester, settle: false);
  await tester.tap(find.byKey(ValueKey('search_source_$source')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  if (settle) await tester.pumpAndSettle();
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

http.Response _namedResults(String type, int count, {int start = 0}) {
  if (type == 'ARTIST') return _artists(count, start: start);
  final label = type == 'ALBUM' ? '专辑' : '歌单';
  return _success({
    type == 'ALBUM' ? 'albums' : 'playlists': List.generate(
        count,
        (index) => {
              'id': '${start + index}',
              'name': '$label ${start + index}',
              'source': 'netease',
              'artist': '测试歌手',
              'creatorName': '测试创建者',
              'trackCount': 10,
            }),
  });
}

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
