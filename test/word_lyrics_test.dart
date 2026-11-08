import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/player/lrc_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  var lyricResponse = <String, dynamic>{};
  setUpAll(() {
    http.runWithClient(
      () => ApiClient.instance,
      () => MockClient((request) async {
        expect(request.url.path, '/api/v1/music/lyric');
        expect(request.url.queryParameters['source'], 'netease');
        return http.Response.bytes(
            utf8.encode(jsonEncode({'code': 0, 'data': lyricResponse})), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
  });

  test('API retains usable karaoke timing instead of discarding it', () async {
    const karaoke = '[60000,1800](60000,800,0)晚(60800,1000,0)风';
    lyricResponse = {'lineLyrics': '[01:00.00]晚风', 'karaokeLyrics': karaoke};
    expect(await MusicApi().getLyric('song'), karaoke);
  });

  test('API falls back to line lyrics when karaoke timing is unusable',
      () async {
    for (final karaoke in [null, '', '[60000,1800]晚风', 'unsupported format']) {
      lyricResponse = {
        'lineLyrics': '[01:00.00]晚风',
        'karaokeLyrics': karaoke,
      };
      expect(await MusicApi().getLyric('song'), '[01:00.00]晚风');
    }
  });

  test('YRC preserves absolute word times, spaces and line order', () {
    final lines = parseLrc('''
{"t":0,"c":[{"tx":"metadata"}]}
[62000,1000](62000,1000,0)明天
[60000,1800](60000,800,0)晚(60800,1000,0)风 goes on
''');
    expect(lines.map((line) => line.text), ['晚风 goes on', '明天']);
    expect(lines.first.time, const Duration(seconds: 60));
    expect(lines.first.words[1].time, const Duration(milliseconds: 60800));
    expect(lines.first.words[1].duration, const Duration(seconds: 1));
    expect(lines.first.words[1].progressAt(const Duration(milliseconds: 61300)),
        closeTo(0.5, 0.001));
    expect(lines.first.words[1].progressAt(const Duration(seconds: 59)), 0);
    expect(lines.first.words[1].progressAt(const Duration(seconds: 63)), 1);
  });

  test('malformed karaoke rows cannot create misleading word timing', () {
    expect(parseLrc('[60000,1000](60000,-50,0)坏数据'), isEmpty);
    expect(parseLrc('[60000,1000](61000,500,0)逆(60000,500,0)序'), isEmpty);
    expect(parseLrc('[60000,1000]没有时间'), isEmpty);
    final normal = parseLrc('[00:03.50]普通歌词');
    expect(normal.single.text, '普通歌词');
    expect(normal.single.words, isEmpty);
  });
}
