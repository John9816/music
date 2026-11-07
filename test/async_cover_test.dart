import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/playlist.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/core/utils/image_cache_manager.dart';
import 'package:duck_music/features/playlists/playlist_detail_view.dart';
import 'package:duck_music/features/profile/user_library_view.dart';
import 'package:duck_music/widgets/async_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as cache;
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client = _CoverClient();
  late Directory directory;
  late Uint8List artwork;
  late Uint8List wideArtwork;
  late Uint8List smallArtwork;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void coverTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await _cleanUp(tester, client);
      }
    });
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('async-cover-states-');
    artwork = await File('assets/branding/app_icon.png').readAsBytes();
    wideArtwork = await _artworkAtSize(artwork, 1024, 512);
    smallArtwork = await _artworkAtSize(artwork, 16, 8);
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    final coverCache =
        http.runWithClient(() => ImageCacheManager.instance, () => client);
    await coverCache.getFileFromCache('initialize-test-cache');
  });

  tearDownAll(() async {
    await ImageCacheManager.instance.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  coverTest('missing artwork has a music fallback without a retry action',
      (tester) async {
    await tester.pumpWidget(_coverApp(url: ' '));
    expect(find.bySemanticsLabel('暂无封面'), findsOneWidget);
    expect(find.byIcon(Icons.music_note), findsOneWidget);
    expect(find.bySemanticsLabel('重新加载封面'), findsNothing);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(tester.getSize(find.byType(AsyncCover)), const Size(88, 88));
  });

  for (final fill in [false, true]) {
    coverTest('pending artwork keeps a quiet stable placeholder (fill: $fill)',
        (tester) async {
      final url = 'https://example.com/cover-pending-$fill.png';
      await tester.pumpWidget(_coverApp(url: url, fill: fill));
      await _pumpUntil(tester, () => client.requestsFor(url).isNotEmpty);
      expect(find.bySemanticsLabel('封面加载中'), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.bySemanticsLabel('重新加载封面'), findsNothing);
      expect(tester.getSize(find.byType(AsyncCover)),
          fill ? const Size(144, 144) : const Size(88, 88));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  coverTest(
      'failed cover retries through the real cache without tapping its parent',
      (tester) async {
    const url = 'https://p4.music.126.net/retry-cover.png';
    var parentTaps = 0;
    Widget app() => _coverApp(
          url: 'http://p4.music.126.net/retry-cover.png',
          onTap: () => parentTaps++,
        );
    await tester.pumpWidget(app());
    await _pumpUntil(tester, () => client.requestsFor(url).length == 1);
    final first = client.requestsFor(url).single;
    first.complete(status: 503);
    await _pumpUntil(
        tester, () => find.bySemanticsLabel('重新加载封面').evaluate().isNotEmpty);
    expect(find.byIcon(Icons.music_note), findsNothing);
    final before = tester.getRect(find.byType(AsyncCover));

    await tester.tap(find.bySemanticsLabel('重新加载封面'));
    await _pumpUntil(tester, () => client.requestsFor(url).length == 2);
    expect(parentTaps, 0);
    expect(tester.getRect(find.byType(AsyncCover)), before);
    final second = client.requestsFor(url).last;
    expect(second.request.headers['Referer'], 'https://music.163.com/');
    expect(second.request.headers, first.request.headers);
    second.complete(bytes: artwork);
    await _pumpUntil(tester, () => _loadedImages(tester).isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('重新加载封面'), findsNothing);
    expect(tester.getRect(find.byType(AsyncCover)), before);

    final loaded = _loadedImages(tester).single.image!;
    await tester.pumpWidget(app());
    expect(_loadedImages(tester).single.image!.isCloneOf(loaded), isTrue);
    expect(find.bySemanticsLabel('封面加载中'), findsNothing);
    expect(client.requestsFor(url), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  coverTest('changing cover URL removes the previous artwork while loading',
      (tester) async {
    const firstUrl = 'https://example.com/first-cover.png';
    const secondUrl = 'https://example.com/second-cover.png';
    await tester.pumpWidget(_coverApp(url: firstUrl));
    await _pumpUntil(tester, () => client.requestsFor(firstUrl).isNotEmpty);
    client.requestsFor(firstUrl).single.complete(bytes: artwork);
    await _pumpUntil(tester, () => _loadedImages(tester).isNotEmpty);
    await tester.pumpAndSettle();

    await tester.pumpWidget(_coverApp(url: secondUrl));
    await _pumpUntil(tester, () => client.requestsFor(secondUrl).isNotEmpty);
    expect(_loadedImages(tester), isEmpty);
    expect(find.bySemanticsLabel('封面加载中'), findsOneWidget);
    client.requestsFor(secondUrl).single.complete(bytes: artwork);
    await _pumpUntil(tester, () => _loadedImages(tester).isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  coverTest('invalid PNG becomes retryable and recovers from a valid response',
      (tester) async {
    const url = 'https://example.com/invalid-cover.png';
    await tester.pumpWidget(_coverApp(url: url));
    await _pumpUntil(tester, () => client.requestsFor(url).isNotEmpty);
    client.requestsFor(url).single.complete(bytes: const [1, 2, 3, 4]);
    await _pumpUntil(
        tester, () => find.bySemanticsLabel('重新加载封面').evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('重新加载封面'));
    await _pumpUntil(tester, () => client.requestsFor(url).length == 2);
    client.requestsFor(url).last.complete(bytes: artwork);
    await _pumpUntil(tester, () => _loadedImages(tester).isNotEmpty);
    expect(find.bySemanticsLabel('重新加载封面'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  coverTest('stale artwork survives a corrupt refresh', (tester) async {
    const url = 'https://example.com/stale-corrupt-cover.png';
    await tester.runAsync(() => ImageCacheManager.instance.putFile(
          url,
          wideArtwork,
          key: 'resized_w512_h512_$url',
          maxAge: const Duration(days: -1),
          fileExtension: 'png',
        ));
    await tester.pumpWidget(_coverApp(url: url, fill: true));
    await _pumpUntil(tester, () => _loadedImages(tester).isNotEmpty);
    final cached = _loadedImages(tester).single.image!;
    final refreshErrors = <Object>[];
    var refreshDone = false;
    final observer = _imageFiles(url).listen(
      (_) {},
      onError: (Object error) => refreshErrors.add(error),
      onDone: () => refreshDone = true,
    );
    try {
      await _pumpUntil(tester, () => client.requestsFor(url).isNotEmpty);
      client.requestsFor(url).single.complete(bytes: const [1, 2, 3, 4]);
      await _pumpUntil(tester, () => refreshDone);
      await tester.pumpAndSettle();
      expect(refreshErrors, isEmpty);
      expect(_loadedImages(tester).single.image!.isCloneOf(cached), isTrue);
      expect(find.bySemanticsLabel('重新加载封面'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      unawaited(observer.cancel());
    }
  });

  coverTest('late cover subscribers receive cached artwork during refresh',
      (tester) async {
    const url = 'https://example.com/stale-shared-cover.png';
    await tester.runAsync(() => ImageCacheManager.instance.putFile(
          url,
          wideArtwork,
          key: 'resized_w512_h512_$url',
          maxAge: const Duration(days: -1),
          fileExtension: 'png',
        ));
    final firstEvents = <cache.FileResponse>[];
    final secondEvents = <cache.FileResponse>[];
    final first = _imageFiles(url).listen(firstEvents.add, onError: (_) {});
    StreamSubscription<cache.FileResponse>? second;
    try {
      await _pumpUntil(tester,
          () => firstEvents.isNotEmpty && client.requestsFor(url).isNotEmpty);
      second = _imageFiles(url).listen(secondEvents.add, onError: (_) {});
      await _pumpUntil(tester, () => secondEvents.isNotEmpty);
      expect(secondEvents.single, isA<cache.FileInfo>());
      expect(client.requestsFor(url), hasLength(1));
      client.requestsFor(url).single.complete(bytes: artwork);
    } finally {
      unawaited(first.cancel());
      unawaited(second?.cancel());
    }
  });

  coverTest(
      'small cached artwork reaches different-size subscribers during refresh',
      (tester) async {
    const url = 'https://example.com/stale-small-cover.png';
    await tester.runAsync(() => ImageCacheManager.instance.putFile(
          url,
          smallArtwork,
          maxAge: const Duration(days: -1),
          fileExtension: 'png',
        ));
    Widget app({bool showSecond = false}) => MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Row(children: [
                const AsyncCover(url: url, size: 88),
                if (showSecond) const AsyncCover(url: url, size: 144),
              ]),
            ),
          ),
        );
    await tester.pumpWidget(app());
    await _pumpUntil(
        tester,
        () =>
            _loadedImages(tester).length == 1 &&
            client.requestsFor(url).length == 1);
    await tester.pumpWidget(app(showSecond: true));
    await _pumpUntil(tester, () => _loadedImages(tester).length == 2);
    expect(find.bySemanticsLabel('封面加载中'), findsNothing);
    expect(client.requestsFor(url), hasLength(1));
    final before = _loadedImages(tester).map((image) => image.image!).toList();
    final errors = <Object>[];
    var refreshDone = false;
    final observer = _imageFiles(url).listen(
      (_) {},
      onError: (Object error) => errors.add(error),
      onDone: () => refreshDone = true,
    );
    try {
      client.requestsFor(url).single.complete(bytes: const [1, 2, 3, 4]);
      await _pumpUntil(tester, () => refreshDone);
      await tester.pumpAndSettle();
      expect(errors, isEmpty);
      final after = _loadedImages(tester);
      expect(after, hasLength(2));
      for (var index = 0; index < after.length; index++) {
        expect(after[index].image!.isCloneOf(before[index]), isTrue);
      }
      expect(find.bySemanticsLabel('重新加载封面'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      unawaited(observer.cancel());
    }
  });

  coverTest(
      'animated artwork preserves bytes for late subscribers during refresh',
      (tester) async {
    const url = 'https://example.com/stale-animated-cover.gif';
    // Two 2×2 frames, red then blue, with an infinite animation loop.
    final animated = base64Decode(
      'R0lGODlhAgACAIEAAP8AAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQA'
      'CgAAACwAAAAAAgACAAAIBgABCAQQEAAh+QQBCgABACwAAAAAAgACAIEAAP8AAAAA'
      'AAAAAAAIBgABCAQQEAA7',
    );
    await tester.runAsync(() => ImageCacheManager.instance.putFile(
          url,
          animated,
          maxAge: const Duration(days: -1),
          fileExtension: 'gif',
        ));
    final firstEvents = <cache.FileResponse>[];
    final secondEvents = <cache.FileResponse>[];
    final errors = <Object>[];
    var firstDone = false;
    var secondDone = false;
    final first = _imageFiles(url).listen(
      firstEvents.add,
      onError: (Object error) => errors.add(error),
      onDone: () => firstDone = true,
    );
    StreamSubscription<cache.FileResponse>? second;
    try {
      await _pumpUntil(tester,
          () => firstEvents.isNotEmpty && client.requestsFor(url).length == 1);
      second = _imageFiles(url).listen(
        secondEvents.add,
        onError: (Object error) => errors.add(error),
        onDone: () => secondDone = true,
      );
      await _pumpUntil(tester, () => secondEvents.isNotEmpty);
      expect(client.requestsFor(url), hasLength(1));
      final cached = secondEvents.single as cache.FileInfo;
      final before = await tester.runAsync(cached.file.readAsBytes);
      expect(before, orderedEquals(animated));
      expect(cached.file.path, endsWith('.gif'));
      final codec =
          await tester.runAsync(() => ui.instantiateImageCodec(before!));
      expect(codec!.frameCount, 2);
      codec.dispose();

      client
          .requestsFor(url)
          .single
          .complete(bytes: const [1, 2, 3, 4], contentType: 'image/gif');
      await _pumpUntil(tester, () => firstDone && secondDone);
      expect(errors, isEmpty);
      expect(firstEvents, hasLength(1));
      expect(secondEvents, hasLength(1));
      expect(await tester.runAsync(cached.file.readAsBytes),
          orderedEquals(animated));
      expect(tester.takeException(), isNull);
    } finally {
      unawaited(first.cancel());
      unawaited(second?.cancel());
    }
  });

  for (final library in [false, true]) {
    for (final landscape in [false, true]) {
      coverTest(
          'hero cover retries through its overlay (library: $library, '
          'landscape: $landscape)', (tester) async {
        final size = landscape ? const Size(568, 320) : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = SettingsController();
        final player = PlayerController(settings: settings);
        final auth = AuthController();
        final url = 'https://example.com/hero-$library-$landscape.png';
        const title = '夜晚散步时听的音乐';
        final songs = [
          Song(
              id: 'hero',
              name: '散步',
              source: 'netease',
              artists: const [Artist(id: 1, name: '歌手')],
              album: Album(id: 1, name: '专辑', picUrl: url),
              durationMs: 180000)
        ];
        try {
          await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<PlayerController>.value(value: player),
              ChangeNotifierProvider<SettingsController>.value(value: settings),
              ChangeNotifierProvider<AuthController>.value(value: auth),
            ],
            child: MaterialApp(
              theme: AppTheme.byId('light')
                  .data
                  .copyWith(platform: TargetPlatform.android),
              home: MediaQuery(
                data: MediaQueryData(
                    size: size,
                    disableAnimations: true,
                    textScaler: TextScaler.linear(landscape ? 2 : 1)),
                child: library
                    ? UserLibraryView(title: title, loader: () async => songs)
                    : PlaylistDetailView(
                        playlist:
                            Playlist(id: 7711, name: title, coverUrl: url),
                        loader: () async => []),
              ),
            ),
          ));
          await _pumpUntil(tester, () => client.requestsFor(url).isNotEmpty);
          client.requestsFor(url).single.complete(status: 503);
          final hero = find
              .byWidgetPredicate((widget) =>
                  widget is AsyncCover && widget.size == double.infinity)
              .first;
          final retryIcon = find.descendant(
              of: hero, matching: find.byIcon(Icons.refresh_rounded));
          await _pumpUntil(tester, () => retryIcon.evaluate().isNotEmpty);
          final heroTitle = library
              ? find.text(title).last
              : find.byKey(const ValueKey('mobile-playlist-hero-title'));
          expect(tester.getBottomLeft(retryIcon).dy,
              lessThanOrEqualTo(tester.getTopLeft(heroTitle).dy),
              reason: 'The retry icon must remain above the title.');
          await tester.tap(retryIcon);
          await _pumpUntil(tester, () => client.requestsFor(url).length == 2);
          client.requestsFor(url).last.complete(bytes: artwork);
          await _pumpUntil(
              tester,
              () => tester
                  .widgetList<RawImage>(find.descendant(
                      of: hero, matching: find.byType(RawImage)))
                  .any((image) => image.image != null));
          expect(player.current, isNull);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          player.dispose();
          settings.dispose();
          auth.dispose();
        }
      });
    }
  }

  for (final large in [true, false]) {
    coverTest(
        'cover resize preserves aspect ratio without upscaling (large: $large)',
        (tester) async {
      final url = 'https://example.com/cover-dimensions-$large.png';
      await tester.pumpWidget(_coverApp(url: url, fill: true));
      await _pumpUntil(tester, () => client.requestsFor(url).isNotEmpty);
      client
          .requestsFor(url)
          .single
          .complete(bytes: large ? wideArtwork : smallArtwork);
      await _pumpUntil(tester, () => _loadedImages(tester).isNotEmpty);
      final decoded = _loadedImages(tester).single.image!;
      expect(decoded.width, large ? 512 : 16);
      expect(decoded.height, large ? 256 : 8);
      expect(tester.takeException(), isNull);
    });
  }
}

Stream<cache.FileResponse> _imageFiles(String url) =>
    (ImageCacheManager.instance as cache.ImageCacheManager).getImageFile(
      url,
      maxWidth: 512,
      maxHeight: 512,
    );

Future<Uint8List> _artworkAtSize(Uint8List bytes, int width, int height) async {
  final codec = await ui.instantiateImageCodec(bytes,
      targetWidth: width, targetHeight: height);
  final frame = await codec.getNextFrame();
  try {
    return (await frame.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    frame.image.dispose();
    codec.dispose();
  }
}

Widget _coverApp(
        {required String? url, bool fill = false, VoidCallback? onTap}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox.square(
              dimension: fill ? 144 : 88,
              child: AsyncCover(
                url: url,
                size: fill ? double.infinity : 88,
                heroTag: 'test-cover',
              ),
            ),
          ),
        ),
      ),
    );

List<RawImage> _loadedImages(WidgetTester tester) => tester
    .widgetList<RawImage>(find.byType(RawImage))
    .where((image) => image.image != null)
    .toList();

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 150 && !ready(); attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'Artwork did not reach its expected state.');
}

Future<void> _cleanUp(WidgetTester tester, _CoverClient client) async {
  for (final request in client.requests) {
    if (!request.response.isCompleted) request.complete(status: 503);
  }
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  for (var attempt = 0; attempt < 6; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 4));
  }
  (ImageCacheManager.instance.config.repo as cache.JsonCacheInfoRepository)
      .timer
      ?.cancel();
}

class _CoverClient extends http.BaseClient {
  final requests = <_CoverRequest>[];

  List<_CoverRequest> requestsFor(String url) =>
      requests.where((entry) => entry.request.url.toString() == url).toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final entry = _CoverRequest(request);
    requests.add(entry);
    return entry.response.future;
  }
}

class _CoverRequest {
  _CoverRequest(this.request);

  final http.BaseRequest request;
  final response = Completer<http.StreamedResponse>();

  void complete(
      {int status = 200,
      List<int> bytes = const [],
      String contentType = 'image/png'}) {
    response.complete(http.StreamedResponse(
      Stream.value(bytes),
      status,
      contentLength: bytes.length,
      headers: {
        'content-type': contentType,
        'cache-control': 'max-age=86400',
      },
    ));
  }
}
