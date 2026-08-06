import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../api/api_client.dart';
import '../api/music_api.dart';
import '../models/song.dart';
import '../services/cache_service.dart';
import '../services/song_download_service.dart';
import '../settings/settings_controller.dart';

enum PlaybackErrorKind { none, generic, loginRequired, membershipRequired }

/// 播放控制，对应 macOS 版 PlaybackCoordinator。
/// 底层使用 just_audio：Android → ExoPlayer、iOS/macOS → AVPlayer、
/// Windows → Media Foundation，一套 API 四平台通用。
class PlayerController extends ChangeNotifier {
  PlayerController({required SettingsController settings})
      : _settings = settings {
    _positionStream = _player.positionStream;
    _playbackSub = _player.playbackEventStream.listen(
      _onPlaybackEvent,
      onError: _onPlaybackError,
    );
    _playingSub = _player.playingStream.distinct().listen((_) {
      notifyListeners();
    });
    // Some streams expose their duration after playback has already started.
    // Notify consumers so progress bars recalculate their denominator.
    _durationSub = _player.durationStream.distinct().listen((_) {
      notifyListeners();
    });
  }

  final SettingsController _settings;
  final AudioPlayer _player = AudioPlayer();
  final MusicApi _api = MusicApi();
  late final Stream<Duration> _positionStream;

  StreamSubscription<PlaybackEvent>? _playbackSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration?>? _durationSub;
  Timer? _seekTimer;
  Duration? _pendingSeek;
  Completer<void>? _seekCompleter;
  bool _seekInFlight = false;
  Timer? _volumeTimer;
  double? _pendingVolume;
  Completer<void>? _volumeCompleter;
  bool _volumeInFlight = false;

  List<Song> _queue = [];
  List<Song>? _queueSnapshot;
  int _index = -1;
  Song? _current;
  String _lyric = '';
  bool _loading = false;
  bool _liked = false;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  String? _error;
  PlaybackErrorKind _errorKind = PlaybackErrorKind.none;

  bool get liked => _liked;
  bool get shuffle => _shuffle;
  LoopMode get loopMode => _loopMode;

  void toggleLike() {
    _liked = !_liked;
    notifyListeners();
  }

  void setLiked(bool value) {
    if (_liked == value) return;
    _liked = value;
    notifyListeners();
  }

  /// 播放请求序号：快速连点时只有最后一次操作生效，
  /// 旧请求即使晚返回也不会覆盖当前状态（彻底消除点歌竞态卡死）。
  int _playSeq = 0;

  /// 播放成功后的回调（用于记录播放历史等副作用）。
  void Function(Song song)? onSongPlayed;

  /// 当前歌曲变化时的回调（用于同步收藏等账号状态）。
  void Function(Song song)? onSongChanged;

  /// 播放接口要求有效会员时通知主界面打开兑换入口。
  VoidCallback? onMembershipRequired;

  // --- getters ---
  List<Song> get queue => _queueSnapshot ??= List.unmodifiable(_queue);
  Song? get current => _current;
  bool get playing => _player.playing;
  Duration get position => _player.position;

  /// Shared for the controller lifetime so widget rebuilds cannot restart the
  /// progress clock before it emits its next value.
  Stream<Duration> get positionStream => _positionStream;
  Duration? get duration {
    final loaded = _player.duration;
    if (loaded != null && loaded > Duration.zero) return loaded;
    final fallbackMs = _current?.durationMs ?? 0;
    return fallbackMs > 0 ? Duration(milliseconds: fallbackMs) : loaded;
  }

  String get lyric => _lyric;
  bool get loading => _loading;
  String? get error => _error;
  PlaybackErrorKind get errorKind => _errorKind;
  bool get requiresLogin => _errorKind == PlaybackErrorKind.loginRequired;
  bool get requiresMembership =>
      _errorKind == PlaybackErrorKind.membershipRequired;
  double get volume => _player.volume;
  Future<void> setVolume(double v) {
    _pendingVolume = v.clamp(0.0, 1.0).toDouble();
    final completer = _volumeCompleter ??= Completer<void>();
    _scheduleVolumeFlush();
    return completer.future;
  }

  int get queueIndex => _index;

  // --- actions ---

  Future<void> playQueue(List<Song> songs, {int index = 0}) async {
    if (songs.isEmpty) return;
    _queue = List.of(songs);
    _queueSnapshot = null;
    await playAt(index);
  }

  /// 将队列中的指定歌曲移到当前歌曲之后，不中断当前播放。
  void moveToNext(int index) {
    if (index < 0 || index >= _queue.length || index == _index) return;
    final song = _queue.removeAt(index);
    if (index < _index) _index--;
    final target = (_index + 1).clamp(0, _queue.length);
    _queue.insert(target, song);
    _queueSnapshot = null;
    notifyListeners();
  }

  /// 将任意歌曲插入当前歌曲之后，用于各端统一的“下一首播放”。
  void playNext(Song song, {int? queueIndex}) {
    if (_current == null || _queue.isEmpty) {
      unawaited(playQueue([song]));
      return;
    }
    if (song.id == _current!.id && song.source == _current!.source) return;
    if (queueIndex != null &&
        queueIndex >= 0 &&
        queueIndex < _queue.length &&
        _queue[queueIndex].id == song.id &&
        _queue[queueIndex].source == song.source) {
      moveToNext(queueIndex);
      return;
    }

    final existing = _queue.indexWhere(
      (item) => item.id == song.id && item.source == song.source,
    );
    if (existing >= 0) {
      _queue.removeAt(existing);
      if (existing < _index) _index--;
    }
    _queue.insert((_index + 1).clamp(0, _queue.length), song);
    _queueSnapshot = null;
    notifyListeners();
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final seq = ++_playSeq;
    _index = index;
    _current = _queue[index];
    _liked = false;
    _loading = true;
    _error = null;
    _errorKind = PlaybackErrorKind.none;
    _lyric = '';
    notifyListeners();
    onSongChanged?.call(_current!);
    try {
      await _player.stop();
      if (seq != _playSeq) return;
      final song = _current!;
      final downloadedFile =
          await SongDownloadService.instance.localFileFor(song);
      if (seq != _playSeq) return; // 已被更新的操作取代
      final mediaItem = MediaItem(
        id: song.id,
        title: song.name,
        artist: song.artistNames,
        album: song.album.name,
        artUri:
            song.album.picUrl != null ? Uri.tryParse(song.album.picUrl!) : null,
        duration: song.durationMs > 0
            ? Duration(milliseconds: song.durationMs)
            : null,
      );
      final AudioSource source;
      final audioHeaders = _audioHeadersFor(song.source);
      if (downloadedFile != null) {
        source = AudioSource.uri(downloadedFile.uri, tag: mediaItem);
      } else {
        final url = await _api
            .getSongUrl(
              song.id,
              source: song.source,
              quality: _settings.quality,
            )
            .timeout(const Duration(seconds: 22));
        if (seq != _playSeq) return;
        if (url == null || url.isEmpty) {
          throw Exception('未获取到播放地址，请切换音乐源后重试');
        }
        if (_settings.automaticAudioCache) {
          final cacheFile = await CacheService.instance.audioFileFor(
            song,
            _settings.quality,
          );
          // just_audio still marks its disk-backed cache source experimental,
          // but it is the package's supported API for progressive audio caching.
          // ignore: experimental_member_use
          source = LockCachingAudioSource(
            Uri.parse(url),
            cacheFile: cacheFile,
            headers: audioHeaders,
            tag: mediaItem,
          );
        } else {
          source = AudioSource.uri(
            Uri.parse(url),
            headers: audioHeaders,
            tag: mediaItem,
          );
        }
      }
      // 带 MediaItem 标签：系统通知栏/锁屏显示歌名、歌手、封面。
      await _player.setAudioSource(source).timeout(const Duration(seconds: 20));
      if (seq != _playSeq) return;
      _loadLyric(seq);
      _loading = false;
      notifyListeners();

      // just_audio 的 play Future 在暂停或播放结束后才完成，不能在这里
      // await，否则整首歌期间都会被误判为“正在加载”。
      final playback = _player.play();
      notifyListeners();
      unawaited(CacheService.instance.maintainAudioCache(_settings));
      if (seq == _playSeq) onSongPlayed?.call(song);
      unawaited(playback.catchError((Object error, StackTrace stackTrace) {
        _setPlaybackError(seq, error);
      }));
    } catch (e) {
      _setPlaybackError(seq, e);
    } finally {
      if (seq == _playSeq) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Map<String, String> _audioHeadersFor(String source) {
    final referer = switch (source.toLowerCase()) {
      'qq' => 'https://y.qq.com/',
      'kuwo' => 'https://www.kuwo.cn/',
      _ => 'https://music.163.com/',
    };
    return {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/537.36',
      'Referer': referer,
      'Accept': 'audio/*,*/*;q=0.8',
    };
  }

  void _loadLyric(int seq) {
    final song = _current;
    if (song == null) return;
    _api.getLyric(song.id, source: song.source).then((lrc) {
      if (seq != _playSeq) return;
      if (lrc != null && lrc.isNotEmpty && identical(_current, song)) {
        _lyric = lrc;
        notifyListeners();
      }
    }).catchError((_) {});
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    // 播放完毕自动切下一首
    if (event.processingState == ProcessingState.completed &&
        _queue.isNotEmpty) {
      unawaited(next());
      return;
    }
    notifyListeners();
  }

  void _onPlaybackError(Object error, StackTrace stackTrace) {
    _setPlaybackError(_playSeq, error);
  }

  void _setPlaybackError(int seq, Object error) {
    if (seq != _playSeq) return;
    _loading = false;
    final apiError = error is ApiException ? error : null;
    final rawMessage = apiError?.message ?? error.toString();
    final message = rawMessage.replaceFirst(RegExp(r'^Exception: '), '');
    if (apiError?.unauthorized == true) {
      _errorKind = PlaybackErrorKind.loginRequired;
      _error = '登录已失效，请重新登录';
    } else if (apiError?.statusCode == 403 || _looksLikeMembership(message)) {
      _errorKind = PlaybackErrorKind.membershipRequired;
      _error = '需要有效会员才能播放，请先兑换会员卡';
    } else {
      _errorKind = PlaybackErrorKind.generic;
      _error = message.isEmpty ? '播放失败，请重试' : message;
    }
    notifyListeners();
    if (_errorKind == PlaybackErrorKind.membershipRequired) {
      onMembershipRequired?.call();
    }
  }

  bool _looksLikeMembership(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('vip') ||
        normalized.contains('会员') ||
        normalized.contains('订阅') ||
        normalized.contains('权限') ||
        normalized.contains('开通');
  }

  Future<void> pause() async {
    if (_player.playing) {
      await _player.pause();
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    if (_current == null || _loading) return;
    if (_error != null || _player.processingState == ProcessingState.idle) {
      await playAt(_index);
      return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      final seq = _playSeq;
      unawaited(
          _player.play().catchError((Object error, StackTrace stackTrace) {
        _setPlaybackError(seq, error);
      }));
    }
    notifyListeners();
  }

  Future<void> retry() async {
    if (_index >= 0) await playAt(_index);
  }

  Future<void> stopAndClear() async {
    ++_playSeq;
    await _player.stop();
    _queue = [];
    _queueSnapshot = null;
    _index = -1;
    _current = null;
    _lyric = '';
    _loading = false;
    _liked = false;
    _error = null;
    _errorKind = PlaybackErrorKind.none;
    notifyListeners();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_shuffle && _queue.length > 1) {
      var nextIndex = _index;
      while (nextIndex == _index) {
        nextIndex = Random().nextInt(_queue.length);
      }
      await playAt(nextIndex);
      return;
    }
    await playAt((_index + 1) % _queue.length);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    await playAt((_index - 1 + _queue.length) % _queue.length);
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    notifyListeners();
  }

  Future<void> cycleLoopMode() async {
    _loopMode = switch (_loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(
      _loopMode == LoopMode.one ? LoopMode.one : LoopMode.off,
    );
    notifyListeners();
  }

  Future<void> seek(Duration position) {
    _pendingSeek = position;
    final completer = _seekCompleter ??= Completer<void>();
    _scheduleSeekFlush();
    return completer.future;
  }

  void _scheduleSeekFlush() {
    if (_seekTimer != null || _seekInFlight || _pendingSeek == null) return;
    _seekTimer = Timer(const Duration(milliseconds: 16), () {
      _seekTimer = null;
      unawaited(_flushSeek());
    });
  }

  Future<void> _flushSeek() async {
    if (_seekInFlight) return;
    final target = _pendingSeek;
    _pendingSeek = null;
    if (target == null) {
      _completeSeek();
      return;
    }
    _seekInFlight = true;
    try {
      await _player.seek(target);
      _seekInFlight = false;
      if (_pendingSeek != null) {
        _scheduleSeekFlush();
      } else {
        _completeSeek();
      }
    } catch (error, stackTrace) {
      _seekInFlight = false;
      _pendingSeek = null;
      _seekCompleter?.completeError(error, stackTrace);
      _seekCompleter = null;
    }
  }

  void _completeSeek() {
    final completer = _seekCompleter;
    _seekCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _scheduleVolumeFlush() {
    if (_volumeTimer != null || _volumeInFlight || _pendingVolume == null) {
      return;
    }
    _volumeTimer = Timer(const Duration(milliseconds: 16), () {
      _volumeTimer = null;
      unawaited(_flushVolume());
    });
  }

  Future<void> _flushVolume() async {
    if (_volumeInFlight) return;
    final value = _pendingVolume;
    _pendingVolume = null;
    if (value == null) {
      _completeVolume();
      return;
    }
    _volumeInFlight = true;
    try {
      await _player.setVolume(value);
      notifyListeners();
      _volumeInFlight = false;
      if (_pendingVolume != null) {
        _scheduleVolumeFlush();
      } else {
        _completeVolume();
      }
    } catch (error, stackTrace) {
      _volumeInFlight = false;
      _pendingVolume = null;
      _volumeCompleter?.completeError(error, stackTrace);
      _volumeCompleter = null;
    }
  }

  void _completeVolume() {
    final completer = _volumeCompleter;
    _volumeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    _playingSub?.cancel();
    _durationSub?.cancel();
    _seekTimer?.cancel();
    _volumeTimer?.cancel();
    _seekCompleter?.complete();
    _volumeCompleter?.complete();
    _player.dispose();
    super.dispose();
  }
}
