import '../models/song.dart';
import 'api_client.dart';

class UserApi {
  final ApiClient _client = ApiClient.instance;

  Future<List<Map<String, dynamic>>> getFavorites(String token) async {
    final data = await _client.getJson(
        'api/user/music/favorites?page=0&size=100',
        headers: {'Authorization': 'Bearer $token'});
    return _items(data);
  }

  Future<void> addFavorite(Song song, String token) async {
    await _client.postJson('api/user/music/favorites',
        body: _songBody(song), headers: {'Authorization': 'Bearer $token'});
  }

  Future<void> removeFavorite(
      String songId, String source, String token) async {
    await _client.deleteJson(
      'api/user/music/favorites',
      params: {'source': source, 'songId': songId},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> deleteHistory(String recordId, String token) async {
    await _client.deleteJson(
      'api/user/music/history/${Uri.encodeComponent(recordId)}',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<List<Map<String, dynamic>>> getHistory(String token) async {
    final data = await _client.getJson('api/user/music/history?page=0&size=100',
        headers: {'Authorization': 'Bearer $token'});
    return _items(data);
  }

  Future<void> addHistory(Song song, String token) async {
    await _client.postJson('api/user/music/history',
        body: _songBody(song), headers: {'Authorization': 'Bearer $token'});
  }

  Future<List<Map<String, dynamic>>> getUserPlaylists(String token) async {
    final data = await _client.getJson(
        'api/user/music/playlists?page=0&size=100',
        headers: {'Authorization': 'Bearer $token'});
    return _items(data);
  }

  Future<Map<String, dynamic>> createPlaylist(
      String name, String? description, String token) async {
    final data = await _client.postJson('api/user/music/playlists', body: {
      'name': name,
      if (description != null) 'description': description
    }, headers: {
      'Authorization': 'Bearer $token'
    });
    return data;
  }

  /// 从音乐平台歌单链接导入到当前用户的歌单库。
  Future<Map<String, dynamic>> importPlaylist(String url, String token) async {
    return _client.postJson('api/user/music/playlists/import', body: {
      'url': url,
    }, headers: {
      'Authorization': 'Bearer $token'
    });
  }

  /// 获取用户歌单中的歌曲。
  /// 后端响应为 data.items.items，兼容直接返回 data.items 的旧格式。
  Future<List<Map<String, dynamic>>> getUserPlaylistSongs(
      String playlistId, String token) async {
    final data = await _client.getJson(
      'api/user/music/playlists/${Uri.encodeComponent(playlistId)}',
      params: {'page': '0', 'size': '100'},
      headers: {'Authorization': 'Bearer $token'},
    );
    final page = data['items'];
    if (page is Map<String, dynamic>) {
      return _items(page);
    }
    return _items(data);
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
