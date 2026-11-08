import 'dart:convert';
import 'dart:math' as math;

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/player/queue_view.dart';
import 'package:duck_music/widgets/song_action_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    http.runWithClient(
      () => ApiClient.instance,
      () => MockClient((request) async => http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'items': request.url.path.endsWith('/playlists')
                  ? [
                      {'id': 'owned', 'name': 'My playlist', 'source': 'local'}
                    ]
                  : [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'})),
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final themeId in ['light', 'dark']) {
    testWidgets(
        '$themeId queue keeps titles and artists readable outside player',
        (tester) async {
      await _pumpLauncher(tester, themeId);
      await tester.tap(find.text('Open queue'));
      await tester.pumpAndSettle();
      final title = find.text('Queue song 2');
      final artist = find.text('Queue artist 2');
      final background = _nearestSolidBackground(tester, title);
      expect(_contrast(_textColor(tester, title), background),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(_textColor(tester, artist), background),
          greaterThanOrEqualTo(4.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('$themeId song actions keep icons readable outside player',
        (tester) async {
      await _pumpLauncher(tester, themeId);
      await tester.tap(find.text('Open actions'));
      await tester.pumpAndSettle();
      final icon = find.byIcon(Icons.skip_next_rounded);
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      final scheme = Theme.of(tester.element(icon)).colorScheme;
      final background = sheet.backgroundColor ?? scheme.surfaceContainer;
      final foreground = tester.widget<Icon>(icon).color!;
      expect(_contrast(foreground, background), greaterThanOrEqualTo(3));
      expect(_contrast(_textColor(tester, find.text('下一首播放')), background),
          greaterThanOrEqualTo(4.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('$themeId playlist chooser and create dialog use app surfaces',
        (tester) async {
      await _pumpLauncher(tester, themeId);
      await tester.tap(find.text('Open playlists'));
      await tester.pumpAndSettle();
      final playlist = find.text('My playlist');
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      final theme = Theme.of(tester.element(playlist));
      final background =
          sheet.backgroundColor ?? theme.colorScheme.surfaceContainer;
      expect(_contrast(_textColor(tester, playlist), background),
          greaterThanOrEqualTo(4.5));
      expect(theme.brightness, AppTheme.byId(themeId).data.brightness);
      await tester.tap(find.text('新建歌单'));
      await tester.pumpAndSettle();
      final input = find.byType(TextField);
      final dialogTheme = Theme.of(tester.element(input));
      expect(dialogTheme.brightness, AppTheme.byId(themeId).data.brightness);
      expect(tester.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    testWidgets('selected queue text stays readable with a pale accent ($dark)',
        (tester) async {
      await _pumpLauncher(tester, dark ? 'dark' : 'light',
          theme: AppTheme.forAccent('lakeCyan', dark: dark).data);
      await tester.tap(find.text('Open queue'));
      await tester.pumpAndSettle();
      final title = find.text('Queue song 1');
      final artist = find.text('Queue artist 1');
      var background = _nearestSolidBackground(tester, title);
      final row = tester.widget<AnimatedContainer>(find
          .ancestor(of: title, matching: find.byType(AnimatedContainer))
          .first);
      background = Color.alphaBlend(
          (row.decoration! as BoxDecoration).color!, background);
      expect(_contrast(_textColor(tester, title), background),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(_textColor(tester, artist), background),
          greaterThanOrEqualTo(4.5));
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpLauncher(WidgetTester tester, String themeId,
    {ThemeData? theme}) async {
  final settings = SettingsController();
  final player = _QueuePlayer(settings);
  final auth = _LoggedInAuth();
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
      theme: (theme ?? AppTheme.byId(themeId).data)
          .copyWith(platform: TargetPlatform.android),
      home: Builder(builder: (context) {
        final original = Theme.of(context);
        // Matches the player's local artwork palette: changing foregrounds
        // must not make app-level menus inherit unrelated container colors.
        final immersive = original.copyWith(
          brightness: Brightness.dark,
          colorScheme: original.colorScheme.copyWith(
            brightness: Brightness.dark,
            surface: const Color(0xff16191e),
            onSurface: const Color(0xfff3f5fa),
            onSurfaceVariant: const Color(0xffc1ccd8),
            primary: const Color(0xffc5dcee),
          ),
        );
        return Theme(
          data: immersive,
          child: Builder(
              builder: (context) => Scaffold(
                    body: Column(children: [
                      TextButton(
                          onPressed: () => showQueueSheet(context),
                          child: const Text('Open queue')),
                      TextButton(
                          onPressed: () =>
                              showSongActions(context, song: _song(1)),
                          child: const Text('Open actions')),
                      TextButton(
                          onPressed: () =>
                              showAddSongToPlaylist(context, song: _song(1)),
                          child: const Text('Open playlists')),
                    ]),
                  )),
        );
      }),
    ),
  ));
  await tester.pumpAndSettle();
}

Color _textColor(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)));
  return paragraph.text.style!.color!;
}

Color _nearestSolidBackground(WidgetTester tester, Finder text) {
  Color? color;
  tester.element(text).visitAncestorElements((element) {
    if (element.widget case ColoredBox(color: final background)
        when background.a == 1) {
      color = background;
      return false;
    }
    return true;
  });
  return color!;
}

double _contrast(Color foreground, Color background) {
  final actual = Color.alphaBlend(foreground, background).computeLuminance();
  final base = background.computeLuminance();
  return (math.max(actual, base) + .05) / (math.min(actual, base) + .05);
}

class _LoggedInAuth extends AuthController {
  @override
  String get token => 'overlay-test-token';
}

class _QueuePlayer extends PlayerController {
  _QueuePlayer(SettingsController settings) : super(settings: settings);
  @override
  List<Song> get queue => [_song(1), _song(2)];
  @override
  int get queueIndex => 0;
  @override
  bool get playing => false;
}

Song _song(int number) => Song(
      id: '$number',
      name: 'Queue song $number',
      source: 'netease',
      artists: [Artist(id: number, name: 'Queue artist $number')],
      album: const Album(id: 1, name: 'Album'),
      durationMs: 240000,
    );
