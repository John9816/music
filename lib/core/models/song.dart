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
  });

  final String id;
  final String name;
  final String source;
  final List<Artist> artists;
  final Album album;
  final int durationMs;
  final String? libraryId;
  final DateTime? playedAt;

  String get artistNames => artists.map((a) => a.name).join(' / ');

  /// 解析 api/v1/music 系列接口的 V1SongItem JSON。
  factory Song.fromV1(Map<String, dynamic> json) {
    final id = _stringValue(json['id']);
    final name = _stringValue(json['name']);
    final artistRaw = _stringValue(json['artist']);
    final artists = artistRaw
        .split(RegExp(r'[,/]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => Artist(id: 0, name: e))
        .toList();
    final durationMs = (json['durationMs'] as num?)?.toInt() ??
        ((json['durationSec'] as num?)?.toInt() ?? 0) * 1000;
    return Song(
      id: id,
      name: name,
      source: _stringValue(json['source'], fallback: 'netease'),
      artists: artists.isEmpty ? const [Artist(id: 0, name: '未知歌手')] : artists,
      album: Album(
        id: _intValue(json['albumId']),
        name: _stringValue(json['album']),
        picUrl: _nullableString(json['coverUrl']),
      ),
      durationMs: durationMs,
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
    this.picUrl,
  });

  final int id;
  final String name;
  final String? picUrl;
}
