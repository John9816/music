import 'package:duck_music/core/api/video_api.dart';
import 'package:duck_music/core/models/video.dart';
import 'package:duck_music/core/services/video_history_service.dart';
import 'package:duck_music/features/videos/video_detail_view.dart';
import 'package:duck_music/features/videos/videos_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeVideoApi extends VideoApi {
  @override
  Future<List<VideoCategory>> categories({String? source}) async => const [
        VideoCategory(id: '1', name: '电影', url: '/channel/1.html'),
      ];

  @override
  Future<VideoFilter> filters({String? source}) async => const VideoFilter(
        years: ['2026'],
        regions: ['中国大陆'],
        genres: ['悬疑'],
        orders: ['最新'],
      );

  @override
  Future<VideoPage> discover({
    String? source,
    String? category,
    String? year,
    String? region,
    String? genre,
    String? order,
    int page = 1,
    int pageSize = 20,
  }) async =>
      const VideoPage(
        list: [
          VideoItem(id: '42', title: '消失的人', status: '正片'),
        ],
        total: 1,
      );

  @override
  Future<VideoDetail> detail(String id, {String? source}) async => const VideoDetail(
        id: '42',
        title: '消失的人',
        description: '简介',
        episodes: [VideoEpisode(id: '1', name: '1080P', url: '')],
        lines: [VideoLine(id: '1', name: '超清2')],
      );
}

class _FakeVideoHistoryService extends VideoHistoryService {
  @override
  Future<VideoHistoryEntry?> load(String source, String videoId) async {
    return const VideoHistoryEntry(
      source: 'ncat21',
      videoId: '42',
      episodeId: '1',
      lineId: '1',
      position: Duration(minutes: 12),
    );
  }
}

void main() {
  testWidgets('renders video catalog and opens detail', (tester) async {
    final api = _FakeVideoApi();
    await tester.pumpWidget(MaterialApp(home: VideosView(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('影视'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('消失的人'), findsOneWidget);

    await tester.tap(find.text('消失的人'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoDetailView), findsOneWidget);
    expect(find.text('1080P'), findsOneWidget);
  });

  testWidgets('shows the last watched episode as a continue action',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: VideoDetailView(
        api: _FakeVideoApi(),
        videoId: '42',
        historyService: _FakeVideoHistoryService(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('继续播放 1080P'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);
  });
}
