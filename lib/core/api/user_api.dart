import '../models/song.dart';
import '../services/user_playlist_library.dart';
import 'api_client.dart';

class UserApi {
  final ApiClient _client = ApiClient.instance;

  Future<List<Map<String, dynamic>>> getFavorites(String token) async {
    return _getAllPages('api/user/music/favorites', token);
  }

  Future<void> addFavorite(Song song, String token) async {
    await _client.postJson('api/user/music/favorites',
        body: _songBody(song), headers: {'Authorization': 'Bearer $token'});
    UserPlaylistLibrary.instance.markChanged();
  }

  Future<void> removeFavorite(
      String songId, String source, String token) async {
    await _client.deleteJson(
      'api/user/music/favorites',
      params: {'source': source, 'songId': songId},
      headers: {'Authorization': 'Bearer $token'},
    );
    UserPlaylistLibrary.instance.markChanged();
  }

  Future<Map<String, dynamic>> getPlaylistFavoriteStatus(
    String source,
    String playlistId,
    String token,
  ) async {
    return _client.getJson(
      'api/user/music/playlist-favorites/status',
      params: {'source': source, 'playlistId': playlistId},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<Map<String, dynamic>> addPlaylistFavorite(
    String source,
    String playlistId,
    String token,
  ) async {
    final playlist = await _client.postJson(
      'api/user/music/playlist-favorites',
      body: {'source': source, 'playlistId': playlistId},
      headers: {'Authorization': 'Bearer $token'},
    );
    UserPlaylistLibrary.instance.markChanged();
    return playlist;
  }

  Future<void> removePlaylistFavorite(
    String source,
    String playlistId,
    String token,
  ) async {
    await _client.deleteJson(
      'api/user/music/playlist-favorites',
      params: {'source': source, 'playlistId': playlistId},
      headers: {'Authorization': 'Bearer $token'},
    );
    UserPlaylistLibrary.instance.markChanged();
  }

  Future<void> deleteHistory(String recordId, String token) async {
    await _client.deleteJson(
      'api/user/music/history/${Uri.encodeComponent(recordId)}',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<List<Map<String, dynamic>>> getHistory(String token) async {
    return _getAllPages('api/user/music/history', token);
  }

  Future<void> addHistory(Song song, String token) async {
    await _client.postJson('api/user/music/history',
        body: _songBody(song), headers: {'Authorization': 'Bearer $token'});
  }

  Future<List<Map<String, dynamic>>> getUserPlaylists(String token) async {
    return _getAllPages('api/user/music/playlists', token);
  }

  /// The backend stores local/ imported playlists and remote favorites in the
  /// same collection. Remote favorites have no source URL; local and imported
  /// playlists do. Keep the split here so every screen uses the same meaning.
  Future<List<Map<String, dynamic>>> getOwnedPlaylists(String token) async {
    final items = await getUserPlaylists(token);
    return items.where(isOwnedPlaylist).toList();
  }

  Future<List<Map<String, dynamic>>> getFavoritePlaylists(String token) async {
    final items = await getUserPlaylists(token);
    return items.where(isFavoritePlaylist).toList();
  }

  static bool isOwnedPlaylist(Map<String, dynamic> item) {
    final source = item['source']?.toString().trim().toLowerCase();
    final sourceUrl = item['sourceUrl']?.toString().trim();
    return source == null ||
        source.isEmpty ||
        source == 'local' ||
        (sourceUrl != null && sourceUrl.isNotEmpty);
  }

  static bool isFavoritePlaylist(Map<String, dynamic> item) {
    final source = item['source']?.toString().trim().toLowerCase();
    final sourceUrl = item['sourceUrl']?.toString().trim();
    return source != null &&
        source.isNotEmpty &&
        source != 'local' &&
        (sourceUrl == null || sourceUrl.isEmpty);
  }

  Future<Map<String, dynamic>> createPlaylist(
      String name, String? description, String token) async {
    final data = await _client.postJson('api/user/music/playlists', body: {
      'name': name,
      if (description != null) 'description': description
    }, headers: {
      'Authorization': 'Bearer $token'
    });
    UserPlaylistLibrary.instance.markChanged();
    return data;
  }

  /// 从音乐平台歌单链接导入到当前用户的歌单库。
  Future<Map<String, dynamic>> importPlaylist(String url, String token) async {
    final playlist =
        await _client.postJson('api/user/music/playlists/import', body: {
      'url': url,
    }, headers: {
      'Authorization': 'Bearer $token'
    });
    UserPlaylistLibrary.instance.markChanged();
    return playlist;
  }

  Future<void> addSongToPlaylist(
    String playlistId,
    Song song,
    String token,
  ) async {
    final id = Uri.encodeComponent(playlistId);
    await _client.postJson(
      'api/user/music/playlists/$id/items',
      body: _songBody(song),
      headers: {'Authorization': 'Bearer $token'},
    );
    UserPlaylistLibrary.instance.markChanged();
  }

  /// 获取用户歌单中的歌曲。
  /// 后端响应为 data.items.items，兼容直接返回 data.items 的旧格式。
  Future<List<Map<String, dynamic>>> getUserPlaylistSongs(
      String playlistId, String token) async {
    const pageSize = 100;
    const maxPages = 50;
    final result = <Map<String, dynamic>>[];
    final path = 'api/user/music/playlists/'
        '${Uri.encodeComponent(playlistId)}';

    for (var pageNumber = 0; pageNumber < maxPages; pageNumber++) {
      final data = await _client.getJson(
        path,
        params: {'page': '$pageNumber', 'size': '$pageSize'},
        headers: {'Authorization': 'Bearer $token'},
      );
      final page = data['items'];
      final pageData = page is Map
          ? Map<String, dynamic>.from(page)
          : <String, dynamic>{'items': page};
      final items = _items(pageData);
      result.addAll(items);
      final total = (pageData['total'] as num?)?.toInt();
      if (items.isEmpty || items.length < pageSize) break;
      if (total != null && result.length >= total) break;
    }
    return result;
  }

  Map<String, dynamic> _songBody(Song s) => {
        'source': s.source,
        'songId': s.id,
        'name': s.name,
        'artist': s.artistNames,
        'album': s.album.name,
        'coverUrl': s.album.picUrl ?? '',
        'durationSec': s.durationMs > 0 ? (s.durationMs / 1000).round() : null,
      };

  Future<List<Map<String, dynamic>>> _getAllPages(
    String path,
    String token,
  ) async {
    const pageSize = 100;
    const maxPages = 50;
    final result = <Map<String, dynamic>>[];

    for (var page = 0; page < maxPages; page++) {
      final data = await _client.getJson(
        path,
        params: {'page': '$page', 'size': '$pageSize'},
        headers: {'Authorization': 'Bearer $token'},
      );
      final items = _items(data);
      result.addAll(items);
      final total = (data['total'] as num?)?.toInt();
      if (items.isEmpty || items.length < pageSize) break;
      if (total != null && result.length >= total) break;
    }
    return result;
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> data) {
    final raw = data['items'] ?? data['content'] ?? data['list'];
    if (raw is Map) return _items(Map<String, dynamic>.from(raw));
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}
