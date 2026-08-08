import 'dart:async';
import 'dart:convert';

import 'package:duck_music/core/api/live_tv_api.dart';
import 'package:duck_music/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _validM3u = '#EXTM3U\n'
    '#EXTINF:-1 tvg-name="CCTV1" group-title="央视频道",CCTV1\n'
    'http://stream.test/cctv1.m3u8\n';

class _MemoryLiveTvCacheStore implements LiveTvCacheStore {
  String? rawM3u;
  var writes = 0;

  @override
  Future<String?> read() async => rawM3u;

  @override
  Future<void> write(String value) async {
    writes++;
    rawM3u = value;
  }
}

void main() {
  test('refreshes the exact Danbo source and caches parsed UTF-8 content',
      () async {
    final cache = _MemoryLiveTvCacheStore();
    http.Request? request;
    final api = LiveTvApi(
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response.bytes(utf8.encode(_validM3u), 200);
      }),
      cacheStore: cache,
    );

    final catalog = await api.refresh();

    expect(request?.url, Uri.parse(AppConfig.liveTvM3uUrl));
    expect(request?.method, 'GET');
    expect(catalog.groups.single.name, '央视频道');
    expect(cache.rawM3u, _validM3u);
    expect(cache.writes, 1);
  });

  test('reads and parses the last-known-good cached document', () async {
    final cache = _MemoryLiveTvCacheStore()..rawM3u = _validM3u;
    final api = LiveTvApi(
      client: MockClient((_) async => throw StateError('network not expected')),
      cacheStore: cache,
    );

    final catalog = await api.readCached();

    expect(catalog?.channelCount, 1);
    expect(cache.writes, 0);
  });

  test('does not replace valid cache after a non-200 or invalid response',
      () async {
    final cache = _MemoryLiveTvCacheStore()..rawM3u = _validM3u;
    final responses = <http.Response>[
      http.Response('unavailable', 503),
      http.Response('#EXTM3U\n#EXTINF:-1,broken\n/path', 200),
    ];
    final api = LiveTvApi(
      client: MockClient((_) async => responses.removeAt(0)),
      cacheStore: cache,
    );

    await expectLater(api.refresh(), throwsA(isA<LiveTvLoadException>()));
    await expectLater(api.refresh(), throwsA(isA<LiveTvLoadException>()));

    expect(cache.rawM3u, _validM3u);
    expect(cache.writes, 0);
  });

  test('maps a request timeout to a stable load exception', () async {
    final completer = Completer<http.Response>();
    final api = LiveTvApi(
      client: MockClient((_) => completer.future),
      cacheStore: _MemoryLiveTvCacheStore(),
      requestTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      api.refresh(),
      throwsA(
        isA<LiveTvLoadException>().having(
          (error) => error.message,
          'message',
          '直播源请求超时',
        ),
      ),
    );
  });

  test('returns null for missing or malformed cached content', () async {
    final cache = _MemoryLiveTvCacheStore();
    final api = LiveTvApi(
      client: MockClient((_) async => http.Response('', 500)),
      cacheStore: cache,
    );

    expect(await api.readCached(), isNull);
    cache.rawM3u = '#EXTM3U\ninvalid';
    expect(await api.readCached(), isNull);
  });
}
