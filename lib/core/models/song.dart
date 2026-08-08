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
    final durationMs = (json['durationMs'] as num?)?.toInt() ??
        ((json['durationSec'] as num?)?.toInt() ?? 0) * 1000;
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
