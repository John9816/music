import 'package:flutter/foundation.dart';

import '../api/music_api.dart';
import '../api/user_api.dart';
import '../auth/auth_controller.dart';
import '../models/song.dart';
import '../services/song_download_service.dart';
import '../services/user_playlist_library.dart';
import '../settings/settings_controller.dart';
import 'player_controller.dart';

class CarMediaLibraryException implements Exception {
  const CarMediaLibraryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One catalog for the standalone car screen and Android's media browser.
/// Account generations protect responses without treating token refresh as logout.
class CarMediaLibrary extends ChangeNotifier {
  CarMediaLibrary(
      {required AuthController auth,
      required PlayerController player,
      required SettingsController settings,
      required SongDownloadService downloads,
      UserApi? userApi,
      MusicApi? musicApi})
      : _auth = auth,
        _player = player,
        _settings = settings,
        _downloads = downloads,
        _userApi = userApi ?? UserApi(),
        _musicApi = musicApi ?? MusicApi() {
    _session = auth.sessionGeneration;
    _ready = auth.initialized;
    _signedIn = auth.isLoggedIn;
    _source = settings.searchSource;
    _queue = player.queue;
    _downloadKeys = _downloadSnapshot();
    auth.addListener(_authChanged);
    player.addListener(_playerChanged);
    settings.addListener(_settingsChanged);
    downloads.addListener(_downloadsChanged);
    UserPlaylistLibrary.instance.addListener(_libraryChanged);
  }

  static const rootId = 'root';
  static const queueId = 'car:queue';
  static const favoritesId = 'car:favorites';
  static const recentId = 'car:recent';
  static const downloadsId = 'car:downloads';
  static const categories = <String, String>{
    queueId: '播放队列',
    favoritesId: '喜欢的音乐',
    recentId: '最近播放',
    downloadsId: '已下载',
  };

  final AuthController _auth;
  final PlayerController _player;
  final SettingsController _settings;
  final SongDownloadService _downloads;
  final UserApi _userApi;
  final MusicApi _musicApi;
  final _requests = <String, Future<List<Song>>>{};
  final _revisions = <String, int>{};
  final _known = <String, Song>{};
  final _contexts = <String, List<Song>>{};
  int get sessionGeneration => _session;
  late int _session;
  late bool _ready, _signedIn;
  late String _source;
  late List<Song> _queue;
  late List<String> _downloadKeys;
  int _epoch = 0;
  int _searchRequest = 0;
  String? changedCategory;
  bool _disposed = false;

  static String mediaIdFor(Song song) =>
      'song:${Uri.encodeComponent(song.source)}:${Uri.encodeComponent(song.id)}';

  Future<List<Song>> songsFor(String parentId) async {
    if (_disposed) throw const CarMediaLibraryException('媒体目录已关闭');
    final session = _session;
    if (parentId == queueId) return _remember(_player.queue);
    if (parentId == downloadsId) {
      await _downloads.initialize();
      _checkSession(session);
      final songs = _remember(_downloads.downloads.map((entry) => entry.song));
      _contexts[downloadsId] = songs;
      return songs;
    }
    if (parentId != favoritesId && parentId != recentId) return const [];
    _requireAccount();
    return _requests.putIfAbsent(parentId, () {
      final epoch = _epoch;
      final revision = _revisions[parentId] ?? 0;
      final token = _auth.token!;
      return (parentId == favoritesId
              ? _userApi.getFavorites(token)
              : _userApi.getHistory(token))
          .then((rows) {
        _checkSession(session);
        if (epoch != _epoch || revision != (_revisions[parentId] ?? 0)) {
          throw const CarMediaLibraryException('内容已更新，请重试');
        }
        final songs = _remember(rows.map(Song.fromUserLibraryItem));
        _contexts[parentId] = songs;
        return songs;
      }).catchError((Object error) {
        if (session == _session &&
            epoch == _epoch &&
            revision == (_revisions[parentId] ?? 0)) {
          _requests.remove(parentId);
        }
        if (error is CarMediaLibraryException) throw error;
        throw const CarMediaLibraryException('加载失败，请检查网络后重试');
      });
    });
  }

  Future<List<Song>> search(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];
    _requireAccount();
    final session = _session;
    final source = _settings.searchSource;
    final request = ++_searchRequest;
    try {
      final result =
          await _musicApi.searchSongs(keyword, source: source, limit: 50);
      _checkSession(session);
      if (request != _searchRequest) {
        throw const CarMediaLibraryException('搜索已更新');
      }
      if (source != _settings.searchSource) {
        throw const CarMediaLibraryException('搜索源已切换，请重新搜索');
      }
      final songs = _remember(result);
      _contexts['search'] = songs;
      return songs;
    } on CarMediaLibraryException {
      rethrow;
    } catch (_) {
      throw const CarMediaLibraryException('搜索失败，请检查网络后重试');
    }
  }

  Future<Song?> songForMediaId(String id) async {
    for (final song in _player.queue) {
      if (mediaIdFor(song) == id) return song;
    }
    if (_known.containsKey(id)) return _known[id];
    // A host may restore a previously browsed ID after process recreation.
    // Resolve only songs actually in this account's library, never fabricate metadata.
    for (final category in [downloadsId, favoritesId, recentId]) {
      try {
        for (final song in await songsFor(category)) {
          if (mediaIdFor(song) == id) return song;
        }
      } on CarMediaLibraryException {
        continue;
      }
    }
    return null;
  }

  List<Song> playbackQueueFor(Song song) {
    final id = mediaIdFor(song);
    for (final songs in [_player.queue, ..._contexts.values]) {
      if (songs.any((entry) => mediaIdFor(entry) == id)) return songs;
    }
    return [song];
  }

  List<Song> _remember(Iterable<Song> songs) {
    final result =
        List<Song>.unmodifiable(songs.where((song) => song.id.isNotEmpty));
    for (final song in result) {
      final key = mediaIdFor(song);
      _known.remove(key);
      _known[key] = song;
    }
    while (_known.length > 2000) {
      _known.remove(_known.keys.first);
    }
    return result;
  }

  void _requireAccount() {
    if (!_auth.initialized) {
      throw const CarMediaLibraryException('正在恢复账号，请稍后重试');
    }
    if (!_auth.isLoggedIn || _auth.token == null) {
      throw const CarMediaLibraryException('请先在应用中登录账号');
    }
  }

  void _checkSession(int session) {
    if (_disposed || session != _session) {
      throw const CarMediaLibraryException('账号已切换，请重新加载');
    }
  }

  void _authChanged() {
    if (_session == _auth.sessionGeneration &&
        _ready == _auth.initialized &&
        _signedIn == _auth.isLoggedIn) {
      return;
    }
    _session = _auth.sessionGeneration;
    _ready = _auth.initialized;
    _signedIn = _auth.isLoggedIn;
    _known.clear();
    _contexts.clear();
    _requests.clear();
    _epoch++;
    _searchRequest++;
    changedCategory = null;
    notifyListeners();
  }

  void _playerChanged() {
    final songs = _player.queue;
    if (identical(_queue, songs)) return;
    final changed = !listEquals(
        _queue.map(mediaIdFor).toList(), songs.map(mediaIdFor).toList());
    _queue = songs;
    if (changed) {
      changedCategory = queueId;
      notifyListeners();
    }
  }

  void _settingsChanged() {
    if (_source == _settings.searchSource) return;
    _source = _settings.searchSource;
    _known.clear();
    _contexts.clear();
    _searchRequest++;
    changedCategory = null;
    notifyListeners();
  }

  List<String> _downloadSnapshot() =>
      _downloads.downloads.map((entry) => mediaIdFor(entry.song)).toList();
  void _downloadsChanged() {
    final keys = _downloadSnapshot();
    if (listEquals(keys, _downloadKeys)) return;
    _downloadKeys = keys;
    changedCategory = downloadsId;
    notifyListeners();
  }

  void _libraryChanged() => refresh();

  void refresh({String? categoryId}) {
    for (final id
        in categoryId == null ? [favoritesId, recentId] : [categoryId]) {
      _revisions[id] = (_revisions[id] ?? 0) + 1;
      _requests.remove(id);
      _contexts.remove(id);
    }
    changedCategory = categoryId;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_authChanged);
    _player.removeListener(_playerChanged);
    _settings.removeListener(_settingsChanged);
    _downloads.removeListener(_downloadsChanged);
    UserPlaylistLibrary.instance.removeListener(_libraryChanged);
    _known.clear();
    _contexts.clear();
    _requests.clear();
    super.dispose();
  }
}
