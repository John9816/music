import 'song.dart';

enum LyricMatch { exact, unverified }

/// The recording that supplied the audio, independent of the library entry.
class AudioIdentity {
  const AudioIdentity({
    required this.source,
    this.id,
    this.lyricMatch = LyricMatch.unverified,
    this.durationMs = 0,
  });

  final String source;
  final String? id;
  final LyricMatch lyricMatch;
  final int durationMs;

  bool get canLoadLyrics =>
      lyricMatch == LyricMatch.exact &&
      source.isNotEmpty &&
      id != null &&
      id!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'source': source,
        'id': id,
        'lyricMatch': lyricMatch.name,
        'durationMs': durationMs,
      };

  factory AudioIdentity.fromJson(Map<String, dynamic> json) => AudioIdentity(
        source: _text(json['source'])?.toLowerCase() ?? '',
        id: _text(json['id']),
        lyricMatch: json['lyricMatch'] == 'exact'
            ? LyricMatch.exact
            : LyricMatch.unverified,
        durationMs: songDurationMillisecondsFromJson(json),
      );
}

class PlaybackInfo {
  const PlaybackInfo({
    required this.id,
    required this.source,
    required this.playUrl,
    required this.audioIdentity,
  });

  final String id;
  final String source;
  final String? playUrl;
  final AudioIdentity audioIdentity;

  factory PlaybackInfo.fromJson(
    Map<String, dynamic> json, {
    required String id,
    required String source,
  }) {
    final originalId = _text(json['id']) ?? id;
    final originalSource = (_text(json['source']) ?? source).toLowerCase();
    final actualSource =
        (_text(json['actualSource']) ?? originalSource).toLowerCase();
    var actualId = _text(json['actualId']);
    final match = _text(json['lyricMatch']);
    // Old backends did not return a match status. Same-source playback used
    // the requested ID; a cross-source result needs its own recording ID.
    if (match == null && actualSource == originalSource) {
      actualId ??= originalId;
    }
    final exact = actualId != null && (match == 'exact' || match == null);
    return PlaybackInfo(
      id: originalId,
      source: originalSource,
      playUrl: _text(json['playUrl']),
      audioIdentity: AudioIdentity(
        source: actualSource,
        id: actualId,
        lyricMatch: exact ? LyricMatch.exact : LyricMatch.unverified,
        durationMs: songDurationMillisecondsFromJson(json),
      ),
    );
  }
}

String? _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
