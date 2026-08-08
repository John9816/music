import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/video_api.dart';
import 'package:duck_music/core/models/video_source.dart';
import 'package:duck_music/core/services/video_source_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  test('parses source capabilities and keeps the server default', () async {
    final client = ApiClient.forTesting(MockClient((request) async {
      expect(request.url.path, '/api/v1/videos/sources');
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': [
            {
              'id': 'ngzmods::剧和短剧',
              'name': '剧和短剧',
              'capability': 'TVBOX_JS',
              'enabled': true,
              'defaultSource': true,
              'status': 'ready',
            },
            {
              'id': 'newwex::全量',
              'name': '全量',
              'capability': 'ANDROID_DEX',
              'enabled': true,
              'defaultSource': false,
              'reason': 'Android Provider 不能在当前设备执行',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

    final sources = await VideoApi(client: client).sources();

    expect(sources, hasLength(2));
    expect(sources.first.id, 'ngzmods::剧和短剧');
    expect(sources.first.isExecutable, isTrue);
    expect(sources.first.defaultSource, isTrue);
    expect(sources.last.capability, VideoSourceCapability.androidDex);
    expect(sources.last.isExecutable, isFalse);
    expect(sources.last.reason, contains('Android'));
  });

  test('adds selected source to every source-aware video request', () async {
    final paths = <String>[];
    final client = ApiClient.forTesting(MockClient((request) async {
      paths.add('${request.url.path}?${request.url.query}');
      final path = request.url.path;
      final body = path.endsWith('/detail')
          ? {
              'id': '42',
              'title': '源视频',
              'sourceId': 'ngzmods::剧和短剧',
              'sourceName': '剧和短剧',
              'episodes': [],
            }
          : path.endsWith('/play')
              ? {
                  'videoId': '42',
                  'episodeId': '1',
                  'lineId': '1',
                  'sourceId': 'ngzmods::剧和短剧',
                  'sourceName': '剧和短剧',
                  'playable': false,
                  'message': '该源不支持直链',
                }
              : {
                  'list': [],
                  'page': 1,
                  'pageSize': 20,
                  'total': 0,
                };
      return http.Response(
        jsonEncode({'code': 0, 'data': body}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));
    final api = VideoApi(client: client);

    await api.categories(source: 'ngzmods::剧和短剧');
    await api.filters(source: 'ngzmods::剧和短剧');
    await api.discover(source: 'ngzmods::剧和短剧');
    await api.search('短剧', source: 'ngzmods::剧和短剧');
    final detail = await api.detail('42', source: 'ngzmods::剧和短剧');
    final play = await api.play('42', source: 'ngzmods::剧和短剧');

    expect(paths, hasLength(6));
    expect(paths.every((path) => path.contains('source=ngzmods%3A%3A%E5%89%A7%E5%92%8C%E7%9F%AD%E5%89%A7')), isTrue);
    expect(detail.sourceId, 'ngzmods::剧和短剧');
    expect(play.sourceName, '剧和短剧');
  });

  test('falls back from a removed selection to the enabled server default',
      () async {
    SharedPreferences.setMockInitialValues(
        const {VideoSourcePreferences.key: 'removed::site'});
    final prefs = VideoSourcePreferences();

    final resolved = await prefs.resolve(const [
      VideoSource(
        id: 'android::site',
        name: 'Android',
        capability: VideoSourceCapability.androidDex,
        enabled: true,
      ),
      VideoSource(
        id: 'cms::site',
        name: 'CMS',
        capability: VideoSourceCapability.cmsHttp,
        enabled: true,
        defaultSource: true,
      ),
      VideoSource(
        id: 'disabled::site',
        name: 'Disabled',
        capability: VideoSourceCapability.cmsHttp,
        enabled: false,
      ),
    ]);

    expect(resolved?.id, 'cms::site');
  });
}
