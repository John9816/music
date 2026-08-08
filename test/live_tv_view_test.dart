import 'dart:async';

import 'package:duck_music/core/api/live_tv_api.dart';
import 'package:duck_music/core/models/live_tv.dart';
import 'package:duck_music/features/live_tv/live_tv_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LiveTvCatalog _catalog({String suffix = ''}) => LiveTvCatalog(
      groups: [
        LiveChannelGroup(
          id: 'group-cctv',
          name: '央视频道',
          channels: [
            LiveChannel(
              id: 'cctv1',
              name: 'CCTV1综合$suffix',
              groupName: '央视频道',
              tvgId: 'cctv1',
              lines: [
                LiveLine(
                  id: 'cctv1-line-1',
                  name: '线路 1',
                  uri: Uri.parse('http://stream.test/cctv1-a.m3u8'),
                ),
                LiveLine(
                  id: 'cctv1-line-2',
                  name: '线路 2',
                  uri: Uri.parse('https://stream.test/cctv1-b.m3u8'),
                ),
              ],
            ),
          ],
        ),
        LiveChannelGroup(
          id: 'group-satellite',
          name: '卫视频道',
          channels: [
            LiveChannel(
              id: 'hunan',
              name: '湖南卫视$suffix',
              groupName: '卫视频道',
              tvgId: 'hunan',
              lines: [
                LiveLine(
                  id: 'hunan-line-1',
                  name: '线路 1',
                  uri: Uri.parse('http://stream.test/hunan.m3u8'),
                ),
              ],
            ),
          ],
        ),
      ],
    );

class _FakeLiveTvApi extends LiveTvApi {
  LiveTvCatalog? cached;
  Future<LiveTvCatalog> Function()? onRefresh;
  var cacheReads = 0;
  var refreshes = 0;

  @override
  Future<LiveTvCatalog?> readCached() async {
    cacheReads++;
    return cached;
  }

  @override
  Future<LiveTvCatalog> refresh() {
    refreshes++;
    return onRefresh?.call() ?? Future.value(_catalog());
  }
}

void main() {
  testWidgets('shows cached channels before the background refresh completes',
      (tester) async {
    final refresh = Completer<LiveTvCatalog>();
    final api = _FakeLiveTvApi()
      ..cached = _catalog(suffix: '（缓存）')
      ..onRefresh = () => refresh.future;

    await tester.pumpWidget(MaterialApp(home: LiveTvView(api: api)));
    await tester.pump();
    await tester.pump();

    expect(find.text('CCTV1综合（缓存）'), findsOneWidget);
    expect(find.text('2 个分组 · 2 个频道 · 3 条线路'), findsOneWidget);
    expect(api.cacheReads, 1);
    expect(api.refreshes, 1);

    refresh.complete(_catalog(suffix: '（最新）'));
    await tester.pumpAndSettle();
    expect(find.text('CCTV1综合（最新）'), findsOneWidget);
  });

  testWidgets('switches source groups and filters all channels locally',
      (tester) async {
    final api = _FakeLiveTvApi()..onRefresh = () async => _catalog();
    await tester.pumpWidget(MaterialApp(home: LiveTvView(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('CCTV1综合'), findsOneWidget);
    expect(find.text('2 条线路'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-group-group-satellite')));
    await tester.pumpAndSettle();
    expect(find.text('湖南卫视'), findsOneWidget);
    expect(find.text('CCTV1综合'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('live-search-field')),
      'cctv1',
    );
    await tester.pump();
    expect(find.text('CCTV1综合'), findsOneWidget);
    expect(find.text('湖南卫视'), findsNothing);
  });

  testWidgets('keeps cached catalog visible when background refresh fails',
      (tester) async {
    final api = _FakeLiveTvApi()
      ..cached = _catalog()
      ..onRefresh = () async => throw const LiveTvLoadException('offline');

    await tester.pumpWidget(MaterialApp(home: LiveTvView(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('CCTV1综合'), findsOneWidget);
    expect(find.text('当前显示缓存，刷新失败'), findsOneWidget);
  });

  testWidgets('retries after initial cache and network loading both fail',
      (tester) async {
    final api = _FakeLiveTvApi()
      ..onRefresh = () async => throw const LiveTvLoadException('offline');
    await tester.pumpWidget(MaterialApp(home: LiveTvView(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('直播源加载失败'), findsOneWidget);

    api.onRefresh = () async => _catalog();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('CCTV1综合'), findsOneWidget);
  });

  testWidgets('opens a channel with every original source line',
      (tester) async {
    final api = _FakeLiveTvApi()..onRefresh = () async => _catalog();
    LiveChannel? opened;
    await tester.pumpWidget(MaterialApp(
      home: LiveTvView(api: api, onOpenChannel: (channel) => opened = channel),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('live-channel-cctv1')));
    await tester.pumpAndSettle();

    expect(opened?.name, 'CCTV1综合');
    expect(opened?.lines, hasLength(2));
  });

  testWidgets('pauses music before opening a channel', (tester) async {
    final api = _FakeLiveTvApi()..onRefresh = () async => _catalog();
    final events = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: LiveTvView(
        api: api,
        onBeforeOpenChannel: () async => events.add('pause'),
        onOpenChannel: (_) => events.add('open'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('live-channel-cctv1')));
    await tester.pumpAndSettle();

    expect(events, ['pause', 'open']);
  });
}
