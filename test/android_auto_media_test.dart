import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:duck_music/core/player/car_media_library.dart';
import 'package:duck_music/core/player/system_media_controller.dart';
import 'package:duck_music/core/services/song_download_service.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'car_media_library_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.751152.duckmusic/system_media'),
            (_) async => null);
  });
  late SystemMediaController handler;
  late fixtures.TestCarPlayer player;
  late CarMediaLibrary library;
  setUp(() async {
    final settings = SettingsController();
    final auth = fixtures.TestCarAuth();
    player = fixtures.TestCarPlayer(settings);
    final dir = await Directory.systemTemp.createTemp('auto-media-');
    final downloads = SongDownloadService.forTesting(
        musicApi: fixtures.TestCarMusicApi(),
        client: MockClient((_) async => http.Response('', 404)),
        downloadsDirectory: () async => dir);
    library = CarMediaLibrary(
        auth: auth,
        player: player,
        settings: settings,
        downloads: downloads,
        userApi: fixtures.TestCarUserApi(),
        musicApi: fixtures.TestCarMusicApi());
    handler = SystemMediaController(isAndroid: () => false)
      ..attach(player)
      ..attachLibrary(library);
    addTearDown(() async {
      handler.detachLibrary(library);
      handler.detach(player);
      library.dispose();
      downloads.dispose();
      auth.dispose();
      player.dispose();
      settings.dispose();
      await dir.delete(recursive: true);
    });
  });

  test('media browser publishes four categories and stable playable IDs',
      () async {
    final root = await handler.getChildren('root');
    expect(root.map((e) => e.id), CarMediaLibrary.categories.keys);
    expect(root.every((e) => !e.playable!), isTrue);
    player.replace(
        [fixtures.carSong('one'), fixtures.carSong('two', source: 'qq')]);
    final rows = await handler.getChildren(CarMediaLibrary.queueId);
    expect(rows.every((e) => e.playable!), isTrue);
    expect(rows.first.artist, '测试歌手');
    expect(rows.first.duration, const Duration(minutes: 3));
    expect(handler.mediaItem.value!.id, rows.first.id);
    player.replace(player.songs.reversed.toList());
    await handler.playFromMediaId(rows.first.id);
    expect(player.current!.id, 'one');
    expect(player.queueIndex, 1);
  });

  test('browser can wait for a cold runtime without needing a widget',
      () async {
    final cold = SystemMediaController(isAndroid: () => false);
    final request = cold.getChildren(CarMediaLibrary.queueId);
    cold.attach(player);
    cold.attachLibrary(library);
    player.replace([fixtures.carSong('cold')]);
    expect((await request).single.title, '车载歌曲 cold');
    cold.detachLibrary(library);
    cold.detach(player);
  });

  test('browser paging is bounded and does not change player queue', () async {
    player.replace(List.generate(250, (i) => fixtures.carSong('$i')));
    final first = await handler.getChildren(CarMediaLibrary.queueId);
    final page = await handler.getChildren(CarMediaLibrary.queueId, {
      'android.media.browse.extra.PAGE': 1,
      'android.media.browse.extra.PAGE_SIZE': 25
    });
    expect(first, hasLength(3));
    expect(first.every((item) => item.playable == false), isTrue);
    final last = await handler.getChildren(first.last.id);
    expect(last, hasLength(50));
    expect(last.first.title, '车载歌曲 200');
    expect(page, hasLength(25));
    expect(page.first.title, '车载歌曲 25');
    expect(player.queue, hasLength(250));
    expect(player.playCalls, 0);
  });

  test('voice search resolves a real song before starting playback', () async {
    await handler.playFromSearch('夜曲');
    expect(player.current!.id, '夜曲');
    expect(player.playing, true);
    expect(handler.playbackState.value.systemActions,
        contains(MediaAction.playFromSearch));
  });

  test('unknown ID reports an actionable error without replacing queue',
      () async {
    player.replace([fixtures.carSong('kept')]);
    await handler.playFromMediaId('unknown');
    expect(player.current!.id, 'kept');
    expect(handler.playbackState.value.errorMessage, contains('重新'));
    expect(player.playCalls, 0);
  });

  test('queue changes notify subscribed hosts without playhead churn',
      () async {
    final stream = handler.subscribeToChildren(CarMediaLibrary.queueId);
    final values = <Map<String, dynamic>>[];
    final sub = stream.listen(values.add);
    await Future<void>.delayed(Duration.zero);
    final baseline = values.length;
    player.tick();
    player.tick();
    await Future<void>.delayed(Duration.zero);
    expect(values, hasLength(baseline));
    player.replace([fixtures.carSong('new')]);
    await Future<void>.delayed(Duration.zero);
    expect(values.length, greaterThan(baseline));
    await sub.cancel();
  });
}
