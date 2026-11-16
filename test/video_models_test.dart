import 'package:duck_music/core/models/video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  VideoPlayback playback(String url, String? format) => VideoPlayback(
        videoId: '42',
        episodeId: '1',
        lineId: '1',
        playable: true,
        mediaUrl: url,
        format: format,
      );

  test('only accepts supported HTTPS media in the inline player', () {
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
        playback('https://cdn.ncat21.com/poster.jpg', 'mp4').isInlinePlayable,
        isFalse);
  });

  test('accepts containers the backend used to report as HLS', () {
    // The backend collapsed every non-mp4 container to "hls", so the client
    // rejected sources it could actually play.
    expect(playback('https://cdn.ncat21.com/a.mkv', 'mkv').isInlinePlayable,
        isTrue);
    expect(
        playback('https://cdn.ncat21.com/a.ts', 'ts').isInlinePlayable, isTrue);
    expect(playback('https://cdn.ncat21.com/a.flv', 'flv').isInlinePlayable,
        isTrue);
    expect(playback('https://cdn.ncat21.com/a.webm', 'webm').isInlinePlayable,
        isTrue);
    expect(playback('https://cdn.ncat21.com/a.avi', 'avi').isInlinePlayable,
        isTrue);
  });

  test('refuses legacy RealMedia containers', () {
    final wmv = playback('https://cdn.ncat21.com/a.wmv', 'wmv');
    expect(wmv.isInlinePlayable, isFalse);
    expect(wmv.unsupportedReason, isNotEmpty);
    expect(playback('https://cdn.ncat21.com/a.rmvb', 'rmvb').isInlinePlayable,
        isFalse);
  });

  test('trusts the backend when the URL carries no extension', () {
    // Extensionless direct links are common (/duanju/video302 is one), so the
    // backend declaration is the only signal available.
    expect(
        playback(
          'https://dj.youlishipin.com/duanju/video302?episodeId=1',
          'mp4',
        ).isInlinePlayable,
        isTrue);
    expect(
        playback('https://other.example/video302?episodeId=1', 'mp4')
            .isInlinePlayable,
        isTrue);
    expect(playback('https://other.example/video302', 'hls').isInlinePlayable,
        isTrue);
  });

  test('falls back to the URL when the backend could not tell', () {
    expect(
        playback('https://cdn.ncat21.com/video.mp4', 'unknown')
            .isInlinePlayable,
        isTrue);
    expect(
        playback('https://cdn.ncat21.com/video.m3u8', 'unknown')
            .isInlinePlayable,
        isTrue);
    expect(
        playback('https://cdn.ncat21.com/video.exe', 'unknown')
            .isInlinePlayable,
        isFalse);
  });

  test('rejects a container that contradicts the extension', () {
    expect(playback('https://cdn.ncat21.com/video.mkv', 'mp4').isInlinePlayable,
        isFalse);
    expect(playback('https://cdn.ncat21.com/video.mp4', 'hls').isInlinePlayable,
        isFalse);
  });

  test('parses container hints', () {
    expect(MediaContainer.parse('MP4'), MediaContainer.mp4);
    expect(MediaContainer.parse('m3u8'), MediaContainer.hls);
    expect(MediaContainer.parse('mpd'), MediaContainer.dash);
    expect(MediaContainer.parse('m2ts'), MediaContainer.ts);
    expect(MediaContainer.parse('rmvb'), MediaContainer.unsupported);
    expect(MediaContainer.parse(null), MediaContainer.unknown);
    expect(MediaContainer.parse('garbage'), MediaContainer.unknown);
  });
}
