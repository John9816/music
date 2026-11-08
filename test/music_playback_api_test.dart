import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/music_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('download prefetch reaches the play endpoint through both API methods',
      () async {
    final api =
        MusicApi(client: ApiClient.forTesting(MockClient((request) async {
      expect(request.url.path, '/api/v1/music/play');
      expect(request.url.queryParameters['prefetch'], 'true');
      return http.Response(
          jsonEncode({
            'code': 0,
            'data': {'playUrl': 'https://audio.example/song.mp3'},
          }),
          200);
    })));
    expect((await api.getPlaybackInfo('selected', prefetch: true)).playUrl,
        'https://audio.example/song.mp3');
    expect(await api.getSongUrl('selected', prefetch: true),
        'https://audio.example/song.mp3');
  });

  test(
      'playback rejects explicit unverified lyric timing and accepts legacy lyrics',
      () async {
    var data = <String, dynamic>{
      'official': false,
      'lineLyrics': '[00:01.00]fallback',
      'karaokeLyrics': '[1000,1000](1000,1000,0)fallback',
    };
    final api =
        MusicApi(client: ApiClient.forTesting(MockClient((request) async {
      expect(request.url.path, '/api/v1/music/lyric');
      return http.Response(jsonEncode({'code': 0, 'data': data}), 200);
    })));
    expect(await api.getLyric('recording', requireVerified: true), isNull);
    expect(await api.getLyric('recording'), contains('fallback'));
    data = {'lineLyrics': '[00:01.00]legacy'};
    expect(await api.getLyric('recording', requireVerified: true),
        '[00:01.00]legacy');
    data = {'official': true, 'lineLyrics': '[00:01.00]official'};
    expect(await api.getLyric('recording', requireVerified: true),
        '[00:01.00]official');
  });

  test('play response preserves selected song and actual audio identity',
      () async {
    final api =
        MusicApi(client: ApiClient.forTesting(MockClient((request) async {
      expect(request.url.path, '/api/v1/music/play');
      expect(request.url.queryParameters['id'], 'selected');
      expect(request.url.queryParameters['source'], 'netease');
      expect(request.url.queryParameters['quality'], '320k');
      expect(request.url.queryParameters.containsKey('prefetch'), isFalse);
      return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'id': 'selected',
              'source': 'netease',
              'actualSource': 'kuwo',
              'actualId': 'audio-recording',
              'lyricMatch': 'exact',
              'durationSec': 181,
              'playUrl': 'https://audio.example/song.mp3',
            },
          }),
          200);
    })));

    final info = await api.getPlaybackInfo('selected');
    expect(info.id, 'selected');
    expect(info.source, 'netease');
    expect(info.playUrl, 'https://audio.example/song.mp3');
    expect(info.audioIdentity.source, 'kuwo');
    expect(info.audioIdentity.id, 'audio-recording');
    expect(info.audioIdentity.canLoadLyrics, isTrue);
    expect(info.audioIdentity.durationMs, 181000);
    expect(await api.getSongUrl('selected'), 'https://audio.example/song.mp3');
  });

  for (final fixture
      in <({String name, Map<String, dynamic> data, String? id, bool safe})>[
    (name: 'legacy same source', data: {}, id: 'selected', safe: true),
    (
      name: 'legacy cross source without id',
      data: {'actualSource': 'qq'},
      id: null,
      safe: false
    ),
    (
      name: 'legacy cross source with id',
      data: {'actualSource': 'qq', 'actualId': 'qq-recording'},
      id: 'qq-recording',
      safe: true
    ),
    (
      name: 'explicitly unverified same source',
      data: {'lyricMatch': 'unverified'},
      id: null,
      safe: false
    ),
    (
      name: 'exact payload missing actual id',
      data: {'lyricMatch': 'exact'},
      id: null,
      safe: false
    ),
    (
      name: 'unknown match status',
      data: {'lyricMatch': 'future-status', 'actualId': 'candidate'},
      id: 'candidate',
      safe: false
    ),
  ]) {
    test('${fixture.name} applies safe lyric compatibility', () async {
      final api = MusicApi(client: ApiClient.forTesting(MockClient((_) async {
        return http.Response(
            jsonEncode({
              'code': 0,
              'data': {
                'playUrl': 'https://audio.example/song.mp3',
                ...fixture.data
              },
            }),
            200);
      })));

      final info = await api.getPlaybackInfo('selected', source: 'netease');
      expect(info.audioIdentity.id, fixture.id);
      expect(info.audioIdentity.canLoadLyrics, fixture.safe);
    });
  }
}
