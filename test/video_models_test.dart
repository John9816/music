import 'package:duck_music/core/models/video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only accepts supported HTTPS media in the inline player', () {
    VideoPlayback playback(String url, String? format) => VideoPlayback(
          videoId: '42',
          episodeId: '1',
          lineId: '1',
          playable: true,
          mediaUrl: url,
          format: format,
        );

    expect(playback('https://cdn.ncat21.com/video.mp4', 'mp4').isInlinePlayable,
        isTrue);
    expect(
        playback('https://cdn.ncat21.com/video.m3u8', 'hls').isInlinePlayable,
        isTrue);
    expect(
        playback('https://cdn.ncat21.com/video.mpd', 'dash').isInlinePlayable,
        isTrue);
    expect(playback('http://cdn.ncat21.com/video.mp4', 'mp4').isInlinePlayable,
        isFalse);
    expect(playback('https://cdn.ncat21.com/video.exe', 'mp4').isInlinePlayable,
        isFalse);
    expect(
        playback(
          'https://dj.youlishipin.com/duanju/video302?episodeId=1',
          'mp4',
        ).isInlinePlayable,
        isTrue);
    expect(
        playback('https://other.example/video302?episodeId=1', 'mp4')
            .isInlinePlayable,
        isFalse);
    expect(
        playback('https://cdn.ncat21.com/video.mp4', 'unknown')
            .isInlinePlayable,
        isFalse);
  });
}
