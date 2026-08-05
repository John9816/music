import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../api/api_client.dart';
import '../api/music_api.dart';
import '../models/song.dart';
import '../services/cache_service.dart';
import '../settings/settings_controller.dart';

enum PlaybackErrorKind { none, generic, loginRequired, membershipRequired }

/// 播放控制，对应 macOS 版 PlaybackCoordinator。
/// 底层使用 just_audio：Android → ExoPlayer、iOS/macOS → AVPlayer、
/// Windows → Media Foundation，一套 API 四平台通用。
class PlayerController extends ChangeNotifier {
  PlayerController({required SettingsController settings})
      : _settings = settings {
    _playbackSub = _player.playbackEventStream.listen(
      _onPlaybackEvent,
      onError: _onPlaybackError,
    );
  }

  final SettingsController _settings;
  final AudioPlayer _player = AudioPlayer();
  final MusicApi _api = MusicApi();

  StreamSubscription<PlaybackEvent>? _playbackSub;
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

  /// 播放请求序号：快速连点时只有最后一次操作生效，
  /// 旧请求即使晚返回也不会覆盖当前状态（彻底消除点歌竞态卡死）。
  int _playSeq = 0;

  /// 播放成功后的回调（用于记录播放历史等副作用）。
  void Function(Song song)? onSongPlayed;

  /// 播放接口要求有效会员时通知主界面打开兑换入口。
  VoidCallback? onMembershipRequired;

  // --- getters ---
  List<Song> get queue => _queueSnapshot ??= List.unmodifiable(_queue);
  Song? get current => _current;
  bool get playing => _player.playing;
  Duration get position => _player.position;
  Stream<Duration> get positionStream => _player.positionStream;
  Duration? get duration => _player.duration;
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

  Future<void> playAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final seq = ++_playSeq;
    _index = index;
    _current = _queue[index];
    _loading = true;
    _error = null;
    _errorKind = PlaybackErrorKind.none;
    _lyric = '';
    notifyListeners();
    try {
      await _player.stop();
      if (seq != _playSeq) return;
      final song = _current!;
      final url = await _api
          .getSongUrl(
            song.id,
            source: song.source,
            quality: _settings.quality,
          )
          .timeout(const Duration(seconds: 22));
      if (seq != _playSeq) return; // 已被更新的操作取代
      if (url == null || url.isEmpty) {
        throw Exception('未获取到播放地址，请切换音乐源后重试');
      }
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
          tag: mediaItem,
        );
      } else {
        source = AudioSource.uri(Uri.parse(url), tag: mediaItem);
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
    _seekTimer?.cancel();
    _volumeTimer?.cancel();
    _seekCompleter?.complete();
    _volumeCompleter?.complete();
    _player.dispose();
    super.dispose();
  }
}
