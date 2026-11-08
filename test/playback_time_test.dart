import 'package:duck_music/core/player/playback_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('elapsed plus remaining uses one whole-second timeline', () {
    final time = PlaybackTime(
      position: const Duration(milliseconds: 119900),
      duration: const Duration(minutes: 4),
    );
    expect(time.elapsed, '01:59');
    expect(time.remaining, '-02:01');
    expect(time.total, '04:00');
  });

  test('positions stay within the track and unknown duration is explicit', () {
    expect(
        PlaybackTime(
                position: const Duration(seconds: -1),
                duration: const Duration(seconds: 4))
            .elapsed,
        '00:00');
    final ended = PlaybackTime(
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 4));
    expect(ended.elapsed, '00:04');
    expect(ended.remaining, '-00:00');
    final unknown =
        PlaybackTime(position: const Duration(seconds: 12), duration: null);
    expect(unknown.elapsed, '00:12');
    expect(unknown.remaining, '--:--');
    expect(unknown.total, '--:--');
  });

  test('long tracks and compact labels have consistent hour formatting', () {
    final time = PlaybackTime(
        position: const Duration(seconds: 3661),
        duration: const Duration(hours: 2),
        padMinutes: false);
    expect(time.elapsed, '1:01:01');
    expect(time.remaining, '-58:59');
    expect(time.total, '2:00:00');
  });
}
