import 'dart:async';
import 'dart:io';

import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/api/user_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/car_media_library.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/song_download_service.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsController settings;
  late TestCarPlayer player;
  late TestCarAuth auth;
  late TestCarUserApi users;
  late TestCarMusicApi music;
  late SongDownloadService downloads;
  late CarMediaLibrary library;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsController();
    player = TestCarPlayer(settings);
    auth = TestCarAuth();
    users = TestCarUserApi();
    music = TestCarMusicApi();
    final directory = await Directory.systemTemp.createTemp('car-library-');
    downloads = SongDownloadService.forTesting(
      musicApi: music,
      client: MockClient((_) async => http.Response('', 404)),
      downloadsDirectory: () async => directory,
    );
    library = CarMediaLibrary(
        auth: auth,
        player: player,
        settings: settings,
        downloads: downloads,
        userApi: users,
        musicApi: music);
    addTearDown(() async {
      library.dispose();
      downloads.dispose();
      auth.dispose();
      player.dispose();
      settings.dispose();
      await directory.delete(recursive: true);
    });
  });

  test('identity is stable across order and distinguishes sources', () async {
    final a = carSong('a:/中');
    final b = carSong('a:/中', source: 'qq');
    player.replace([a, b]);
    final first = await library.songsFor(CarMediaLibrary.queueId);
    final id = CarMediaLibrary.mediaIdFor(first.first);
    player.replace([b, a]);
    expect(
        CarMediaLibrary.mediaIdFor(
            (await library.songsFor(CarMediaLibrary.queueId)).last),
        id);
    expect(CarMediaLibrary.mediaIdFor(b), isNot(id));
    expect(await library.songForMediaId(id), same(a));
    expect(await library.songForMediaId('unknown'), isNull);
  });

  test('old account response cannot populate new account catalog', () async {
    final held = Completer<List<Map<String, dynamic>>>();
    users.held = held;
    final pending = library.songsFor(CarMediaLibrary.favoritesId);
    final rejected =
        expectLater(pending, throwsA(isA<CarMediaLibraryException>()));
    auth.switchAccount();
    users.held = null;
    held.complete([
      {'songId': 'old', 'name': '旧账号歌曲', 'source': 'netease'}
    ]);
    await rejected;
    final result = await library.songsFor(CarMediaLibrary.favoritesId);
    expect(result.single.id, 'new');
    expect(
        await library
            .songForMediaId(CarMediaLibrary.mediaIdFor(carSong('old'))),
        isNull);
  });

  test(
      'library refresh rejects obsolete data and preserves the replacement request',
      () async {
    final held = Completer<List<Map<String, dynamic>>>();
    users.held = held;
    final old = library.songsFor(CarMediaLibrary.favoritesId);
    final rejected = expectLater(old, throwsA(isA<CarMediaLibraryException>()));
    library.refresh(categoryId: CarMediaLibrary.favoritesId);
    users.held = null;
    expect(
        (await library.songsFor(CarMediaLibrary.favoritesId)).single.id, 'new');
    held.complete([
      {'songId': 'stale', 'name': '旧收藏', 'source': 'netease'}
    ]);
    await rejected;
    expect(
        (await library.songsFor(CarMediaLibrary.favoritesId)).single.id, 'new');
  });

  test('credential rotation preserves an in-flight same-account request',
      () async {
    final held = Completer<List<Map<String, dynamic>>>();
    users.held = held;
    final pending = library.songsFor(CarMediaLibrary.favoritesId);
    auth.rotateToken();
    held.complete([
      {'songId': 'kept', 'name': '同一账号', 'source': 'qq'}
    ]);
    expect((await pending).single.id, 'kept');
  });

  test('search uses independent provider and exposes failures', () async {
    await settings.setSource('kuwo');
    await settings.setSearchSource('qq');
    expect((await library.search('歌手')).single.source, 'qq');
    expect(music.source, 'qq');
    expect(settings.source, 'kuwo');
    music.fail = true;
    await expectLater(
        library.search('other'), throwsA(isA<CarMediaLibraryException>()));
  });

  test('clock ticks do not reload catalog; queue and auth changes do',
      () async {
    var changes = 0;
    library.addListener(() => changes++);
    player.tick();
    player.tick();
    expect(changes, 0);
    player.replace([carSong('one')]);
    expect(changes, 1);
    auth.switchAccount();
    expect(changes, 2);
  });

  test('restoring and signed-out accounts have explicit errors, downloads work',
      () async {
    auth.ready = false;
    await expectLater(
        library.songsFor(CarMediaLibrary.favoritesId),
        throwsA(isA<CarMediaLibraryException>()
            .having((e) => e.message, 'message', contains('恢复'))));
    auth.ready = true;
    auth.signedIn = false;
    await expectLater(
        library.songsFor(CarMediaLibrary.recentId),
        throwsA(isA<CarMediaLibraryException>()
            .having((e) => e.message, 'message', contains('登录'))));
    expect(await library.songsFor(CarMediaLibrary.downloadsId), isEmpty);
  });
}

Song carSong(String id, {String source = 'netease'}) => Song(
    id: id,
    name: '车载歌曲 $id',
    source: source,
    artists: const [Artist(id: 1, name: '测试歌手')],
    album: const Album(id: 1, name: '旅途专辑'),
    durationMs: 180000);

class TestCarAuth extends AuthController {
  int generation = 1;
  bool ready = true, signedIn = true;
  String credential = 'test';
  @override
  int get sessionGeneration => generation;
  @override
  bool get initialized => ready;
  @override
  bool get isLoggedIn => signedIn;
  @override
  String? get token => signedIn ? credential : null;
  void switchAccount() {
    generation++;
    notifyListeners();
  }

  void rotateToken() {
    credential = 'rotated';
    notifyListeners();
  }
}

class TestCarPlayer extends PlayerController {
  TestCarPlayer(SettingsController settings) : super(settings: settings);
  List<Song> songs = [];
  int selected = 0, playCalls = 0;
  bool isPlaying = false;
  Duration progress = Duration.zero;
  @override
  List<Song> get queue => songs;
  @override
  int get queueIndex => songs.isEmpty ? -1 : selected;
  @override
  Song? get current => songs.isEmpty ? null : songs[selected];
  @override
  bool get playing => isPlaying;
  @override
  Duration get position => progress;
  @override
  Duration? get duration =>
      current == null ? null : Duration(milliseconds: current!.durationMs);
  void replace(List<Song> values) {
    songs = values;
    selected = 0;
    notifyListeners();
  }

  void tick() => notifyListeners();
  @override
  Future<void> playQueue(List<Song> values, {int index = 0}) async {
    songs = values;
    selected = index;
    isPlaying = true;
    playCalls++;
    notifyListeners();
  }

  @override
  Future<void> playAt(int index) async {
    selected = index;
    isPlaying = true;
    playCalls++;
    notifyListeners();
  }

  @override
  Future<void> togglePlay() async {
    isPlaying = !isPlaying;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    progress = value;
    notifyListeners();
  }

  @override
  Future<void> next() async {
    if (songs.isNotEmpty) await playAt((selected + 1) % songs.length);
  }

  @override
  Future<void> previous() async {
    if (songs.isNotEmpty) {
      await playAt((selected - 1 + songs.length) % songs.length);
    }
  }

  @override
  Future<void> restoreLastPlayback(
      {Future<Song?> Function()? preferredLoader}) async {}
}

class TestCarUserApi extends UserApi {
  Completer<List<Map<String, dynamic>>>? held;
  @override
  Future<List<Map<String, dynamic>>> getFavorites(String token) async =>
      held != null
          ? await held!.future
          : [
              {'songId': 'new', 'name': '我的收藏', 'source': 'netease'}
            ];
  @override
  Future<List<Map<String, dynamic>>> getHistory(String token) async => [];
}

class TestCarMusicApi extends MusicApi {
  String? source;
  bool fail = false;
  @override
  Future<List<Song>> searchSongs(String keyword,
      {String source = 'netease', int offset = 0, int limit = 30}) async {
    this.source = source;
    if (fail) throw Exception('offline');
    return [carSong(keyword, source: source)];
  }
}
