import 'package:duck_music/core/player/playback_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activating one owner pauses every other registered owner', () async {
    final coordinator = PlaybackCoordinator.instance;
    final first = Object();
    final second = Object();
    final paused = <Object>[];
    coordinator.register(first, () async => paused.add(first));
    coordinator.register(second, () async => paused.add(second));

    addTearDown(() {
      coordinator.unregister(first);
      coordinator.unregister(second);
    });

    await coordinator.activate(first);
    expect(paused, [second]);

    await coordinator.activate(second);
    expect(paused, [second, first]);
  });

  test('a pause failure does not prevent activation', () async {
    final coordinator = PlaybackCoordinator.instance;
    final failing = Object();
    final active = Object();
    coordinator.register(failing, () async => throw StateError('failed'));
    coordinator.register(active, () async {});

    addTearDown(() {
      coordinator.unregister(failing);
      coordinator.unregister(active);
    });

    await expectLater(coordinator.activate(active), completes);
  });
}
