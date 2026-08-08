import 'package:duck_music/core/services/video_history_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  test('persists the last watched episode and playback position', () async {
    final service = VideoHistoryService();

    await service.save(
      const VideoHistoryEntry(
        source: 'ncat21',
        videoId: '333692',
        episodeId: '41',
        lineId: '3537870',
        position: Duration(minutes: 18, seconds: 7),
      ),
    );

    final restored = await service.load('ncat21', '333692');
    expect(restored, isNotNull);
    expect(restored!.episodeId, '41');
    expect(restored.lineId, '3537870');
    expect(restored.position, const Duration(minutes: 18, seconds: 7));
  });

  test('ignores corrupt or unrelated saved progress', () async {
    SharedPreferences.setMockInitialValues(const {
      'videos.history.ncat21.333692': '{not-json',
    });
    final service = VideoHistoryService();

    expect(await service.load('ncat21', '333692'), isNull);
    expect(await service.load('ncat21', 'another-video'), isNull);
  });
}
