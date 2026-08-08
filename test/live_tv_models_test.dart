import 'dart:io';

import 'package:duck_music/core/services/live_m3u_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses metadata and preserves group, channel, and line order', () {
    const source = '\ufeff#EXTM3U x-tvg-url="https://example.test/epg.xml" '
        'catchup="append" catchup-source="?start=\${start}"\n'
        '#EXTINF:-1 tvg-id="cctv1" tvg-name="CCTV1综合" '
        'tvg-logo="http://img.test/cctv1.webp" group-title="央视频道",CCTV1\n'
        'http://stream.test/cctv1-a.m3u8\n'
        '#EXTINF:-1 tvg-id="cctv1" tvg-name="CCTV1综合" '
        'group-title="央视频道",CCTV1 backup\n'
        'https://stream.test/cctv1-b.m3u8\n'
        '#EXTINF:-1 tvg-id="hunan" group-title="卫视频道",湖南卫视\n'
        'https://stream.test/hunan.m3u8\n'
        '#EXTINF:-1 group-title="卫视频道",东方卫视\n'
        'http://stream.test/dragon.flv\n'
        '#EXTINF:-1 tvg-name="invalid" group-title="卫视频道",invalid\n'
        'relative/path.m3u8\n';

    final catalog = const LiveM3uParser().parse(source);

    expect(catalog.epgUrls, ['https://example.test/epg.xml']);
    expect(catalog.catchup, 'append');
    expect(catalog.catchupSource, '?start=\${start}');
    expect(catalog.groups.map((group) => group.name), ['央视频道', '卫视频道']);
    expect(catalog.channelCount, 3);
    expect(catalog.lineCount, 4);

    final cctv1 = catalog.groups.first.channels.single;
    expect(cctv1.name, 'CCTV1综合');
    expect(cctv1.tvgId, 'cctv1');
    expect(cctv1.logoUrl, 'http://img.test/cctv1.webp');
    expect(cctv1.lines.map((line) => line.name), ['线路 1', '线路 2']);
    expect(cctv1.lines.map((line) => line.uri.toString()), [
      'http://stream.test/cctv1-a.m3u8',
      'https://stream.test/cctv1-b.m3u8',
    ]);
    expect(catalog.groups[1].channels.map((channel) => channel.name),
        ['hunan', '东方卫视']);
  });

  test('keeps duplicate playback entries as separate Danbo lines', () {
    const source = '#EXTM3U\n'
        '#EXTINF:-1 tvg-name="CCTV1" group-title="央视",CCTV1\n'
        'http://stream.test/same.m3u8\n'
        '#EXTINF:-1 tvg-name="CCTV1" group-title="央视",CCTV1\n'
        'http://stream.test/same.m3u8\n';

    final channel =
        const LiveM3uParser().parse(source).groups.single.channels.single;

    expect(channel.lines, hasLength(2));
    expect(channel.lines[0].id, isNot(channel.lines[1].id));
  });

  test('rejects a document without playable entries', () {
    expect(
      () => const LiveM3uParser().parse('#EXTM3U\n#EXTINF:-1,broken\n/path'),
      throwsFormatException,
    );
  });

  test('matches the captured Danbo catalog counts and line aggregation', () {
    final source = File('test/fixtures/danbo-interface.txt').readAsStringSync();

    final catalog = const LiveM3uParser().parse(source);

    expect(catalog.groups, hasLength(14));
    expect(catalog.channelCount, 261);
    expect(catalog.lineCount, 352);
    expect(catalog.groups.map((group) => group.name), [
      '央视频道',
      '卫视频道',
      '广东地区',
      '湖南地区',
      '浙江地区',
      '江苏地区',
      '黑龙江地区',
      '江西地区',
      '陕西地区',
      '河北地区',
      '福建地区',
      '河南地区',
      '甘肃地区',
      '超清频道',
    ]);

    final channels = catalog.groups.expand((group) => group.channels);
    expect(channels.singleWhere((channel) => channel.name == 'CCTV1综合').lines,
        hasLength(7));
    expect(channels.singleWhere((channel) => channel.name == 'CCTV5体育').lines,
        hasLength(3));
  });
}
