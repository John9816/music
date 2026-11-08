/// Both labels use the same whole-second timeline. Rounding elapsed and the
/// millisecond remainder independently can otherwise lose a displayed second.
class PlaybackTime {
  PlaybackTime({
    required Duration position,
    required Duration? duration,
    this.padMinutes = true,
  })  : _total = duration != null && duration > Duration.zero ? duration : null,
        _position = position < Duration.zero ? Duration.zero : position;

  final Duration? _total;
  final Duration _position;
  final bool padMinutes;

  Duration get position =>
      _total != null && _position > _total ? _total : _position;

  String get elapsed =>
      formatPlaybackDuration(position, padMinutes: padMinutes);

  String get remaining => _total == null
      ? '--:--'
      : '-${formatPlaybackDuration(Duration(seconds: _total.inSeconds - position.inSeconds), padMinutes: padMinutes)}';

  String get total => _total == null
      ? '--:--'
      : formatPlaybackDuration(_total, padMinutes: padMinutes);
}

String formatPlaybackDuration(Duration value, {bool padMinutes = true}) {
  final seconds = value < Duration.zero ? 0 : value.inSeconds;
  final tail = (seconds % 60).toString().padLeft(2, '0');
  final minutes = seconds ~/ 60;
  if (minutes >= 60) {
    return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:$tail';
  }
  return '${minutes.toString().padLeft(padMinutes ? 2 : 1, '0')}:$tail';
}
