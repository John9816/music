import 'dart:async';
import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/qishui_feed_api.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/player/roaming_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends AuthController {
  int generation = 0;
  @override
  bool get isLoggedIn => true;
  @override
  int get sessionGeneration => generation;
  void changeAccount() {
    generation++;
    notifyListeners();
  }
}

class _Player extends PlayerController {
  _Player(SettingsController settings) : super(settings: settings);
  int generation = 0;
  List<Song> songs = [];
  @override
  int get queueGeneration => generation;
  @override
  List<Song> get queue => songs;
  @override
  int get queueIndex => 0;
  @override
  Future<void> setPlaybackMode(PlaybackMode mode) async {}
  @override
  Future<void> playQueue(List<Song> values, {int index = 0}) async {
    generation++;
    songs = values;
    loadMoreQueue = null;
    notifyListeners();
  }
}

class _Api extends QishuiFeedApi {
  final pending = Completer<RoamingPage>();
  @override
  Future<RoamingPage> start({String? modeId}) => pending.future;
  @override
  Future<void> close(String id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final action in ['manual', 'account', 'stop', 'failure']) {
    test('pending roaming respects $action and preserves an actionable error',
        () async {
      final settings = SettingsController();
      final player = _Player(settings);
      final auth = _Auth();
      final api = _Api();
      final roaming = RoamingController(player: player, auth: auth, api: api);
      addTearDown(() {
        roaming.dispose();
        player.dispose();
        auth.dispose();
        settings.dispose();
      });
      final pending = roaming.start();
      await Future<void>.delayed(Duration.zero);
      final manual = Song.fromV1({'id': 'manual', 'name': 'manual'});
      if (action == 'manual') await player.playQueue([manual]);
      if (action == 'account') auth.changeAccount();
      if (action == 'stop') await roaming.stop();
      if (action == 'failure') {
        api.pending.completeError(ApiException('Please bind account'));
      } else {
        api.pending.complete(RoamingPage.fromJson({
          'sessionId': 'feed',
          'nextSequence': 1,
          'hasMore': true,
          'list': [
            {'id': 'feed-song', 'name': 'feed', 'source': 'qishui'}
          ],
        }));
      }
      expect(await pending, isFalse);
      expect(roaming.active, isFalse);
      expect(player.loadMoreQueue, isNull);
      expect(player.queue.map((s) => s.id),
          action == 'manual' ? ['manual'] : isEmpty);
      if (action == 'failure') expect(roaming.error, contains('扫码绑定'));
    });
  }
}
