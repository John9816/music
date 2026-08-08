import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/video_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads categories and parses video search pages', () async {
    final client = ApiClient.forTesting(MockClient((request) async {
      expect(request.url.path, '/api/v1/videos/search');
      expect(request.url.queryParameters['keyword'], '消失的人');
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            'list': [
              {
                'id': '333692',
                'title': '消失的人',
                'posterUrl': 'https://www.ncat21.com/poster.jpg',
                'detailUrl': 'https://www.ncat21.com/detail/333692.html',
                'status': '正片',
                'description': '悬疑犯罪',
              }
            ],
            'page': 1,
            'pageSize': 20,
            'total': 1,
            'hasMore': false,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

    final api = VideoApi(client: client);
    final page = await api.search('消失的人');

    expect(page.list.single.title, '消失的人');
    expect(page.list.single.id, '333692');
    expect(page.hasMore, isFalse);
  });

  test('parses detail episodes and keeps unavailable playback explicit',
      () async {
    final client = ApiClient.forTesting(MockClient((request) async {
      if (request.url.path.endsWith('/detail')) {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'id': '333692',
              'title': '消失的人',
              'posterUrl': null,
              'description': '简介',
              'tags': [],
              'lines': [
                {'id': '1', 'name': '超清2', 'description': '4K'},
              ],
              'episodes': [
                {
                  'id': '1',
                  'name': '1080P',
                  'url': 'https://www.ncat21.com/play/1'
                },
              ],
              'detailUrl': 'https://www.ncat21.com/detail/333692.html',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            'videoId': '333692',
            'episodeId': '1',
            'lineId': '1',
            'mediaUrl': null,
            'format': null,
            'embedUrl': 'https://player.ncat21.com/embed/333692',
            'upstreamUrl': 'https://www.ncat21.com/play/333692-1-1.html',
            'playable': false,
            'message': '上游未暴露直链，请打开播放页',
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

    final api = VideoApi(client: client);
    final detail = await api.detail('333692');
    final play = await api.play('333692', episode: '1', line: '1');

    expect(detail.episodes.single.name, '1080P');
    expect(play.playable, isFalse);
    expect(play.upstreamUrl, contains('/play/'));
  });
}
