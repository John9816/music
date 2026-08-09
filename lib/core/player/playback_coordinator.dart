typedef PlaybackPauseCallback = Future<void> Function();

/// Ensures that only one in-app playback owner is audible at a time.
class PlaybackCoordinator {
  PlaybackCoordinator._();

  static final instance = PlaybackCoordinator._();

  final Map<Object, PlaybackPauseCallback> _pausers = {};

  void register(Object owner, PlaybackPauseCallback pause) {
    _pausers[owner] = pause;
  }

  void unregister(Object owner) {
    _pausers.remove(owner);
  }

  Future<void> activate(Object owner) async {
    final otherPausers = _pausers.entries
        .where((entry) => entry.key != owner)
        .map((entry) => entry.value)
        .toList(growable: false);
    await Future.wait(otherPausers.map(_pauseSafely));
  }

  Future<void> _pauseSafely(PlaybackPauseCallback pause) async {
    try {
      await pause();
    } catch (_) {
      // One broken player must not prevent the requested player from starting.
    }
  }
}
