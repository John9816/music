// Offline layout fixtures. To export review PNGs, run this test with
// --dart-define=DUCKMUSIC_EXPORT_QA=true and
// --dart-define=DUCKMUSIC_QA_FONT=/absolute/path/to/a/Chinese/font.ttf.
// Fixtures never sign in to a real account or call the production service.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/desktop_integration_service.dart';
import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/home/home_shell.dart';
import 'package:duck_music/features/player/player_view.dart';
import 'package:duck_music/features/settings/settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _exportImages = bool.fromEnvironment('DUCKMUSIC_EXPORT_QA');
const _fontPath = String.fromEnvironment('DUCKMUSIC_QA_FONT');
const _captureKey = ValueKey('production-qa-capture');

void main() {
  setUpAll(() async {
    http.runWithClient(() => ApiClient.instance, () => MockClient(_respond));
    if (_exportImages && _fontPath.isNotEmpty) {
      final font = File(_fontPath).readAsBytes().then(ByteData.sublistView);
      await (FontLoader('DuckMusicQA')..addFont(font)).load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')
            ..addFont(rootBundle
                .load('packages/cupertino_icons/assets/CupertinoIcons.ttf')))
          .load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  for (final fixture in [
    (name: 'library-phone', size: const Size(390, 844), macOS: false),
    (name: 'library-mac-compact', size: const Size(700, 700), macOS: true),
    (name: 'library-desktop', size: const Size(1440, 900), macOS: true),
  ]) {
    testWidgets('visual QA ${fixture.name}', (tester) async {
      await _pump(tester,
          size: fixture.size,
          platform:
              fixture.macOS ? TargetPlatform.macOS : TargetPlatform.android,
          child: const HomeShell());
      await tester.tap(find.text('资料库').last);
      await tester.pumpAndSettle();
      expect(find.text('下班后的慢时光'), findsWidgets);
      if (fixture.size.width > 1000) {
        await tester.tap(find.byTooltip('歌词'));
        await tester.pumpAndSettle();
      }
      await _verifyAndCapture(tester, fixture.name);
    });
  }

  testWidgets('visual QA desktop search results', (tester) async {
    await _pump(tester,
        size: const Size(1440, 900),
        platform: TargetPlatform.macOS,
        child: const HomeShell());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '晚风');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('晚风轻轻'), findsWidgets);
    await _verifyAndCapture(tester, 'search-desktop');
  });

  testWidgets('visual QA search in a short landscape shell', (tester) async {
    await _pump(tester,
        size: const Size(812, 375), scale: 1.5, child: const HomeShell());
    await tester.tap(find.text('搜索').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '晚风');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _verifyAndCapture(tester, 'search-landscape');
    await tester.ensureVisible(find.text('留一点时间给自己'));
    await tester.pumpAndSettle();
    expect(find.text('留一点时间给自己').hitTestable(), findsOneWidget);
    await _verifyAndCapture(tester, 'search-landscape-results');
  });

  for (final fixture in [
    (name: 'player-phone', size: const Size(390, 844), scale: 1.0),
    (name: 'player-small-large-text', size: const Size(320, 700), scale: 1.5),
    (name: 'player-landscape', size: const Size(812, 375), scale: 1.5),
  ]) {
    testWidgets('visual QA ${fixture.name}', (tester) async {
      await _pump(tester,
          size: fixture.size,
          dark: true,
          scale: fixture.scale,
          child: const PlayerView());
      expect(find.byTooltip('播放'), findsOneWidget);
      await _verifyAndCapture(tester, fixture.name);
    });
  }

  testWidgets('visual QA settings large text', (tester) async {
    await _pump(tester,
        size: const Size(390, 844), scale: 1.5, child: const SettingsView());
    expect(find.text('减弱动态效果'), findsOneWidget);
    await _verifyAndCapture(tester, 'settings-large-text');
  });
}

Future<void> _pump(WidgetTester tester,
    {required Size size,
    required Widget child,
    bool dark = false,
    double scale = 1,
    TargetPlatform platform = TargetPlatform.android}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final settings = SettingsController();
  final player = _PreviewPlayer(settings);
  final auth = _PreviewAuth();
  final timer = SleepTimer();
  final desktop = DesktopIntegrationService(settings: settings, player: player);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
    settings.dispose();
    auth.dispose();
    timer.dispose();
    desktop.dispose();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  var theme = AppTheme.forAccent('forestGreen', dark: dark)
      .data
      .copyWith(platform: platform);
  if (_exportImages && _fontPath.isNotEmpty) {
    theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'DuckMusicQA'),
        primaryTextTheme:
            theme.primaryTextTheme.apply(fontFamily: 'DuckMusicQA'));
  }
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<PlayerController>.value(value: player),
      ChangeNotifierProvider<SettingsController>.value(value: settings),
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ChangeNotifierProvider<SleepTimer>.value(value: timer),
      ChangeNotifierProvider<DesktopIntegrationService>.value(value: desktop),
    ],
    child: MaterialApp(
      theme: theme,
      builder: (context, child) => RepaintBoundary(
        key: _captureKey,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: platform == TargetPlatform.macOS
                ? EdgeInsets.zero
                : const EdgeInsets.only(top: 24, bottom: 24),
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
      ),
      home: child,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _verifyAndCapture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (!_exportImages) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final frame = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/qa/production-readiness');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      frame.dispose();
    }
  });
}

class _PreviewAuth extends AuthController {
  @override
  String get token => 'offline-visual-fixture';
  @override
  String get username => '音乐爱好者';
  @override
  bool get isLoggedIn => true;
}

class _PreviewPlayer extends PlayerController {
  _PreviewPlayer(SettingsController settings) : super(settings: settings);
  final _songs = _songData.map(Song.fromV1).toList();
  @override
  Song get current => _songs.first;
  @override
  List<Song> get queue => _songs;
  @override
  int get queueIndex => 0;
  @override
  bool get playing => false;
  @override
  Duration get position => const Duration(seconds: 68);
  @override
  Duration get duration => const Duration(seconds: 238);
  @override
  String get lyric => '[00:00.00]沿着街角慢慢走\n[00:30.00]把忙碌留在身后\n'
      '[01:00.00]让晚风把心事带走\n[01:30.00]听见生活温柔的节奏';
  @override
  Future<void> restoreLastPlayback({
    Future<Song?> Function()? preferredLoader,
  }) async {}
}

const _songData = [
  {
    'id': 'preview-song-1',
    'name': '晚风轻轻',
    'source': 'netease',
    'artist': '城市漫游者',
    'album': '日落以后',
    'albumId': '12',
    'durationMs': 238000,
    'availableQualities': ['standard', 'exhigh'],
  },
  {
    'id': 'preview-song-2',
    'name': '留一点时间给自己',
    'source': 'netease',
    'artist': '缓慢乐队',
    'album': '明天也要好好生活',
    'albumId': '13',
    'durationMs': 196000,
  },
  {
    'id': 'preview-song-3',
    'name': '微光',
    'source': 'netease',
    'artist': '城市漫游者',
    'album': '日落以后',
    'albumId': '12',
    'durationMs': 217000,
  },
];
const _playlistData = [
  {
    'id': 'evening',
    'name': '下班后的慢时光',
    'source': 'local',
    'songCount': 24,
  },
  {
    'id': 'weekend',
    'name': '周末出发 · 沿途有音乐',
    'source': 'local',
    'songCount': 36,
  },
];

Future<http.Response> _respond(http.Request request) async {
  final path = request.url.path;
  final data = switch (path) {
    '/api/user/music/playlists' => {'items': _playlistData},
    '/api/user/music/favorites' => {'items': _songData},
    '/api/v1/music/new' => {'list': _songData},
    '/api/v1/music/search' => switch (request.url.queryParameters['type']) {
        'ARTIST' => {
            'artists': [
              {'id': '31', 'name': '城市漫游者', 'trackCount': 28},
              {'id': '32', 'name': '缓慢乐队', 'trackCount': 16},
            ],
          },
        'ALBUM' => {
            'albums': [
              {
                'id': '12',
                'name': '日落以后',
                'artist': '城市漫游者',
                'trackCount': 12,
              },
            ],
          },
        'PLAYLIST' => {
            'list': [
              {
                'id': 42,
                'name': '让音乐陪你度过每一个日落',
                'source': 'netease',
                'trackCount': 36,
              },
            ],
          },
        _ => {'list': _songData},
      },
    _ => <String, dynamic>{},
  };
  return http.Response(jsonEncode({'code': 0, 'data': data}), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
}
