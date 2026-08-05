import '../config/app_config.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import 'api_client.dart';

/// 搜索歌手结果（api/v1/music/search type=ARTIST）
class SearchArtist {
  const SearchArtist({
    required this.id,
    required this.name,
    this.coverUrl,
    this.trackCount,
    this.source,
  });

  final String id;
  final String name;
  final String? coverUrl;
  final int? trackCount;
  final String? source;

  factory SearchArtist.fromJson(Map<String, dynamic> json) => SearchArtist(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        coverUrl: _textOrNull(json['coverUrl']),
        trackCount: (json['trackCount'] as num?)?.toInt(),
        source: _textOrNull(json['source']),
      );
}

/// 歌手页使用的专辑及其歌曲。
class ArtistAlbum {
  const ArtistAlbum({required this.album, required this.songs});

  final Album album;
  final List<Song> songs;
}

/// 歌手页音乐目录。当前由歌曲搜索结果聚合，后续可无缝替换专用接口。
class ArtistCatalog {
  const ArtistCatalog({required this.songs, required this.albums});

  final List<Song> songs;
  final List<ArtistAlbum> albums;

  factory ArtistCatalog.fromSongs({
    required String artistName,
    required List<Song> searchedSongs,
  }) {
    final normalizedName = _normalizeArtistName(artistName);
    final songs = searchedSongs.where((song) {
      return song.artists.any(
        (artist) => _normalizeArtistName(artist.name) == normalizedName,
      );
    }).toList();

    final albumGroups = <String, List<Song>>{};
    final albums = <String, Album>{};
    for (final song in songs) {
      final album = song.album;
      if (album.name.trim().isEmpty) continue;
      final key = album.id != 0
          ? 'id:${album.id}'
          : 'name:${album.name.trim().toLowerCase()}';
      albums.putIfAbsent(key, () => album);
      albumGroups.putIfAbsent(key, () => []).add(song);
    }

    return ArtistCatalog(
      songs: List.unmodifiable(songs),
      albums: List.unmodifiable([
        for (final entry in albums.entries)
          ArtistAlbum(
            album: entry.value,
            songs: List.unmodifiable(albumGroups[entry.key]!),
          ),
      ]),
    );
  }
}

/// 本地默认分类目录（与 Android/macOS 版一致）
const List<PlaylistCategoryGroup> kPlaylistCategories =
    kPlaylistCategoryCatalog;

/// 音乐接口，对应 macOS 版 MusicApiService。
class MusicApi {
  final ApiClient _client = ApiClient.instance;

  static const _defaultSource = 'netease';

  /// 每日推荐 / 最新歌曲
  Future<List<Song>> getDailyRecommend({String source = _defaultSource}) async {
    final data = await _client.getJson('api/v1/music/new', params: {
      'source': source,
      'page': '1',
      'pageSize': '30',
    });
    return _songList(data);
  }

  /// 最新专辑
  Future<List<Album>> getNewestAlbums({String source = _defaultSource}) async {
    final data = await _client.getJson('api/v1/music/new', params: {
      'source': source,
      'page': '1',
      'pageSize': '12',
    });
    return _albumList(data);
  }

  /// 热门歌单
  Future<List<Playlist>> getTopPlaylists({
    String source = _defaultSource,
    String? category,
    int offset = 0,
    int limit = 20,
  }) async {
    final data = await _client.getJson('api/v1/music/playlist', params: {
      'source': source,
      'order': 'hot',
      'page': '${(offset ~/ limit) + 1}',
      'pageSize': '$limit',
      if (category != null) 'category': category,
    });
    return _playlistList(data);
  }

  /// 歌单分类目录（本地默认值，不依赖后端）
  List<PlaylistCategoryGroup> getPlaylistCategories() => kPlaylistCategories;

  /// 排行榜列表
  Future<List<Playlist>> getTopLists({String source = _defaultSource}) async {
    final data = await _client.getJson('api/v1/music/toplist', params: {
      'source': source,
    });
    return _playlistList(data);
  }

  /// 歌单详情
  Future<List<Song>> getPlaylistDetail(
    int id, {
    String source = _defaultSource,
  }) async {
    final data = await _client.getJson('api/v1/music/playlist/detail', params: {
      'source': source,
      'page': '1',
      'pageSize': '300',
      'id': '$id',
    });
    return _songList(data);
  }

  /// 排行榜详情
  Future<List<Song>> getTopListDetail(
    int id, {
    String source = _defaultSource,
  }) async {
    final data = await _client.getJson('api/v1/music/toplist/detail', params: {
      'source': source,
      'page': '1',
      'pageSize': '300',
      'id': '$id',
    });
    return _songList(data);
  }

  /// 搜索歌曲
  Future<List<Song>> searchSongs(
    String keyword, {
    String source = _defaultSource,
    int offset = 0,
    int limit = 30,
  }) async {
    final data = await _client.getJson('api/v1/music/search', params: {
      'source': source,
      'keyword': keyword,
      'type': 'SONG',
      'page': '${(offset ~/ limit) + 1}',
      'pageSize': '$limit',
    });
    return _songList(data);
  }

  /// 搜索歌单
  Future<List<Playlist>> searchPlaylists(
    String keyword, {
    String source = _defaultSource,
    int offset = 0,
    int limit = 30,
  }) async {
    final data = await _client.getJson('api/v1/music/search', params: {
      'source': source,
      'keyword': keyword,
      'type': 'PLAYLIST',
      'page': '${(offset ~/ limit) + 1}',
      'pageSize': '$limit',
    });
    return _playlistList(data);
  }

  /// 搜索歌手（返回歌手列表，点击后可用歌手名再搜歌曲）
  Future<List<SearchArtist>> searchArtists(
    String keyword, {
    String source = _defaultSource,
    int offset = 0,
    int limit = 30,
  }) async {
    final data = await _client.getJson('api/v1/music/search', params: {
      'source': source,
      'keyword': keyword,
      'type': 'ARTIST',
      'page': '${(offset ~/ limit) + 1}',
      'pageSize': '$limit',
    });
    return _jsonList(data['artists'])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map(SearchArtist.fromJson)
        .toList();
  }

  /// 获取歌手歌曲与专辑目录。
  ///
  /// 现有 V1 API 暂无歌手专辑端点，因此先按歌手名搜索歌曲、精确匹配
  /// 歌手字段，再按 albumId（缺失时按专辑名）聚合专辑。
  Future<ArtistCatalog> getArtistCatalog(
    String artistName, {
    String source = _defaultSource,
    String? artistId,
    int limit = 100,
  }) async {
    final searched = await searchSongs(
      artistName,
      source: source,
      limit: limit,
    );
    return ArtistCatalog.fromSongs(
      artistName: artistName,
      searchedSongs: searched,
    );
  }

  /// 获取播放地址（字段 playUrl）
  Future<String?> getSongUrl(
    String id, {
    String source = _defaultSource,
    String quality = 'exhigh',
  }) async {
    final data = await _client.getJson('api/v1/music/play', params: {
      'source': source,
      'id': id,
      'quality': AppConfig.qualityValues[quality] ?? '320k',
    });
    return _textOrNull(data['playUrl']);
  }

  /// 获取歌词（字段 lineLyrics）
  Future<String?> getLyric(
    String id, {
    String source = _defaultSource,
  }) async {
    final data = await _client.getJson('api/v1/music/lyric', params: {
      'source': source,
      'id': id,
      'timestamp': '${DateTime.now().millisecondsSinceEpoch}',
    });
    return _textOrNull(data['lineLyrics']);
  }

  List<Song> _songList(Map<String, dynamic> data) {
    return _jsonList(data['list'])
        .map((e) => Song.fromV1(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  List<Playlist> _playlistList(Map<String, dynamic> data) {
    return _jsonList(data['playlists'] ?? data['list'])
        .map((e) => Playlist.fromV1(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  List<Album> _albumList(Map<String, dynamic> data) {
    return _jsonList(data['list'])
        .map((e) => _albumFromSong(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Album _albumFromSong(Map<String, dynamic> json) {
    final id = json['albumId'] is num
        ? (json['albumId'] as num).toInt()
        : int.tryParse(json['albumId']?.toString() ?? '') ?? 0;
    final albumName = json['album']?.toString() ?? '';
    return Album(
      id: id,
      name: albumName.isEmpty ? (json['name']?.toString() ?? '') : albumName,
      picUrl: _textOrNull(json['coverUrl']),
    );
  }
}

Iterable<dynamic> _jsonList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>();
}

String? _textOrNull(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String _normalizeArtistName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
