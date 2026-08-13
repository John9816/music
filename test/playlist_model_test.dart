import 'package:duck_music/core/models/playlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Playlist.fromV1 cover URL', () {
    test('falls back to picUrl', () {
      final playlist = Playlist.fromV1({
        'id': 1,
        'name': 'Red source playlist',
        'picUrl': 'https://example.com/pic.jpg',
      });

      expect(playlist.coverUrl, 'https://example.com/pic.jpg');
    });

    test('falls back to coverImgUrl after blank fields', () {
      final playlist = Playlist.fromV1({
        'id': 1,
        'name': 'Red source playlist',
        'coverUrl': ' ',
        'picUrl': '',
        'coverImgUrl': 'https://example.com/cover-img.jpg',
      });

      expect(playlist.coverUrl, 'https://example.com/cover-img.jpg');
    });

    test('prefers canonical coverUrl', () {
      final playlist = Playlist.fromV1({
        'id': 1,
        'name': 'Playlist',
        'coverUrl': 'https://example.com/canonical.jpg',
        'picUrl': 'https://example.com/fallback.jpg',
      });

      expect(playlist.coverUrl, 'https://example.com/canonical.jpg');
    });
  });
}
