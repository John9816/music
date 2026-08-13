/// 歌曲模型（对应 macOS 版 Song / V1SongItem）。
class Song {
  Song({
    required this.id,
    required this.name,
    required this.source,
    required this.artists,
    required this.album,
    required this.durationMs,
    this.libraryId,
    this.playedAt,
    this.availableQualities = const [],
  });

  final String id;
  final String name;
  final String source;
  final List<Artist> artists;
  final Album album;
  final int durationMs;
  final String? libraryId;
  final DateTime? playedAt;
  final List<String> availableQualities;

  String get artistNames => artists.map((a) => a.name).join(' / ');

  /// 解析 api/v1/music 系列接口的 V1SongItem JSON。
  factory Song.fromV1(Map<String, dynamic> json) {
    final id = _stringValue(json['id']);
    final name = _stringValue(json['name']);
    final artistRaw = _stringValue(json['artist']);
    final names = artistRaw
        .split(RegExp(r'[,/]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final ids = (json['artistIds'] is List
            ? (json['artistIds'] as List)
                .map((e) => e?.toString() ?? '')
                .toList()
            : <String>[])
        .where((e) => e.isNotEmpty)
        .toList();
    final primaryArtistId = json['artistId']?.toString();
    final artists = [
      for (var index = 0; index < names.length; index++)
        Artist(
          id: int.tryParse(
                index < ids.length
                    ? ids[index]
                    : (index == 0 ? primaryArtistId : null) ?? '',
              ) ??
              0,
          name: names[index],
        ),
    ];
    final durationMs = songDurationMillisecondsFromJson(json);
    final albumSourceId = _stringValue(json['albumId']);
    return Song(
      id: id,
      name: name,
      source: _stringValue(json['source'], fallback: 'netease'),
      artists: artists.isEmpty ? const [Artist(id: 0, name: '未知歌手')] : artists,
      album: Album(
        id: _intValue(albumSourceId),
        sourceId: albumSourceId.isEmpty ? null : albumSourceId,
        name: _stringValue(json['album']),
        picUrl: _nullableString(json['coverUrl']),
      ),
      durationMs: durationMs,
      availableQualities: (json['availableQualities'] is List
              ? (json['availableQualities'] as List)
                  .map((e) => e?.toString() ?? '')
              : const <String>[])
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
    );
  }

  /// Parses songs stored by the user favorites, history, and playlist APIs.
  factory Song.fromUserLibraryItem(Map<String, dynamic> json) {
    final artistNames = _stringValue(json['artistName'] ?? json['artist']);
    final artists = artistNames
        .split(RegExp(r'[,/]'))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .map((name) => Artist(id: 0, name: name))
        .toList(growable: false);
    return Song(
      id: _stringValue(json['songId'] ?? json['id']),
      name: _stringValue(json['name'] ?? json['songName']),
      source: _stringValue(json['source'], fallback: 'netease'),
      artists: artists.isEmpty ? const [Artist(id: 0, name: '未知歌手')] : artists,
      album: Album(
        id: 0,
        name: _stringValue(json['album']),
        picUrl: _nullableString(json['coverUrl'] ?? json['albumCover']),
      ),
      durationMs: songDurationMillisecondsFromJson(json),
      libraryId: _nullableString(json['id']),
      playedAt: DateTime.tryParse(_stringValue(json['playedAt'])),
    );
  }
}

String _stringValue(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String? _nullableString(Object? value) {
  final text = _stringValue(value);
  return text.isEmpty ? null : text;
}

int _intValue(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int songDurationMillisecondsFromJson(Map<String, dynamic> json) {
  final milliseconds = _numericValue(json['durationMs']);
  if (milliseconds != null && milliseconds > 0) return milliseconds.round();

  final seconds = _numericValue(json['durationSec']);
  if (seconds != null && seconds > 0) return (seconds * 1000).round();

  final netEaseMilliseconds = _numericValue(json['dt']);
  if (netEaseMilliseconds != null && netEaseMilliseconds > 0) {
    return netEaseMilliseconds.round();
  }

  final sourceSeconds = _numericValue(json['interval']);
  if (sourceSeconds != null && sourceSeconds > 0) {
    return (sourceSeconds * 1000).round();
  }

  final generic = _numericValue(json['duration']);
  if (generic == null || generic <= 0) return 0;
  // Aggregated source APIs commonly expose `duration` in either seconds or
  // milliseconds. Normal songs are well below 10,000 seconds.
  return generic >= 10000 ? generic.round() : (generic * 1000).round();
}

double? _numericValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().trim() ?? '');
}

class Artist {
  const Artist({required this.id, required this.name, this.picUrl});

  final int id;
  final String name;
  final String? picUrl;
}

class Album {
  const Album({
    required this.id,
    required this.name,
    this.sourceId,
    this.picUrl,
  });

  final int id;
  final String name;
  final String? sourceId;
  final String? picUrl;

  String get detailId => sourceId ?? id.toString();
}
