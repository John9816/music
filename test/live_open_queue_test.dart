import 'dart:async';

import 'package:duck_music/features/live_tv/live_open_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not overlap media open operations', () async {
    final queue = LiveOpenQueue();
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var active = 0;
    var maximumActive = 0;

    Future<void> openFirst() async {
      active++;
      maximumActive = active > maximumActive ? active : maximumActive;
      firstStarted.complete();
      await releaseFirst.future;
      active--;
    }

    Future<void> openSecond() async {
      active++;
      maximumActive = active > maximumActive ? active : maximumActive;
      active--;
    }

    final first = queue.enqueue(openFirst);
    await firstStarted.future;
    final second = queue.enqueue(openSecond);
    await Future<void>.delayed(Duration.zero);

    expect(maximumActive, 1);
    releaseFirst.complete();
    await first;
    await second;
    expect(maximumActive, 1);
  });
}
