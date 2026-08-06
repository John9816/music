import 'package:duck_music/core/api/user_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('user playlist classification', () {
    test('local playlists belong to my playlists', () {
      final playlist = {
        'id': 1,
        'source': 'local',
        'sourceId': 'local-1',
        'sourceUrl': null,
      };

      expect(UserApi.isOwnedPlaylist(playlist), isTrue);
      expect(UserApi.isFavoritePlaylist(playlist), isFalse);
    });

    test('URL imports belong to my playlists', () {
      final playlist = {
        'id': 2,
        'source': 'qq',
        'sourceId': 'remote-2',
        'sourceUrl': 'https://y.qq.com/n/ryqq/playlist/remote-2',
      };

      expect(UserApi.isOwnedPlaylist(playlist), isTrue);
      expect(UserApi.isFavoritePlaylist(playlist), isFalse);
    });

    test('remote favorites without a source URL are favorite playlists', () {
      final playlist = {
        'id': 3,
        'source': 'netease',
        'sourceId': 'remote-3',
        'sourceUrl': null,
      };

      expect(UserApi.isOwnedPlaylist(playlist), isFalse);
      expect(UserApi.isFavoritePlaylist(playlist), isTrue);
    });
  });
}
