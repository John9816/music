import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../api/api_client.dart';
import '../api/music_api.dart';
import '../models/song.dart';
import '../models/playback_info.dart';
import '../network/image_request_policy.dart';
import '../services/cache_service.dart';
import '../services/song_download_service.dart';
import '../settings/settings_controller.dart';
import 'audio_source_policy.dart';
import 'last_playback_store.dart';
import 'playback_coordinator.dart';

enum PlaybackErrorKind { none, generic, loginRequired, membershipRequired }

enum PlaybackMode { listLoop, singleLoop, shuffle }

/// 播放控制，对应 macOS 版 PlaybackCoordinator。
/// 底层使用 just_audio：Android → ExoPlayer、iOS/macOS → AVPlayer、
/// Windows → Media Foundation，一套 API 四平台通用。
class PlayerController extends ChangeNotifier with WidgetsBindingObserver {
  PlayerController({
    required SettingsController settings,
    AudioPlayer? audioPlayer,
    MusicApi? musicApi,
    Future<File?> Function(Song song)? localFileFor,
    Future<LocalAudio?> Function(Song song)? localAudioFor,
    CacheService? cacheService,
    Future<void> Function(SettingsController settings)? maintainAudioCache,
    LastPlaybackStore? lastPlaybackStore,
    Future<void> Function()? beforePlayback,
  })  : _settings = settings,
        _player = audioPlayer ??
            AudioPlayer(
              useProxyForRequestHeaders:
                  !usesNativeAudioHeaders(defaultTargetPlatform),
            ),
        _api = musicApi ?? MusicApi(),
        _localFileFor = localFileFor,
        _localAudioFor =
            localAudioFor ?? SongDownloadService.instance.localAudioFor,
        _cacheService = cacheService ?? CacheService.instance,
        _maintainAudioCache = maintainAudioCache ??
            ((settings) => (cacheService ?? CacheService.instance)
                .maintainAudioCache(settings)),
        _lastPlaybackStore =
            lastPlaybackStore ?? SharedPreferencesLastPlaybackStore(),
        _beforePlayback = beforePlayback {
    PlaybackCoordinator.instance.register(this, pause);
    _positionController = StreamController<Duration>.broadcast(
      sync: true,
    );
    _positionStream = _positionController.stream;
    WidgetsBinding.instance.addObserver(this);
    _playbackSub = _player.playbackEventStream.listen(
      _onPlaybackEvent,
      onError: _onPlaybackError,
    );
    // Forward just_audio's source-aware clock. The sampler below is retained
    // as a watchdog because mobile platforms may temporarily pause Dart stream
    // delivery around background/foreground transitions.
    _nativePositionSub = _player.positionStream.listen(
      _onNativePosition,
      onError: (Object error, StackTrace stackTrace) {},
    );
    _playingSub = _player.playingStream.distinct().listen((playing) {
      if (playing) {
        _resumeGuardUntil = _lastEmittedPosition == null
            ? null
            : DateTime.now().add(const Duration(milliseconds: 250));
        _startPositionSampling();
      } else {
        _resumeGuardUntil = null;
        _stopPositionSampling();
        _emitNativePosition(force: true);
      }
      notifyListeners();
    });
    // Some streams expose their duration after playback has already started.
    // Notify consumers so progress bars recalculate their denominator.
    _durationSub = _player.durationStream.distinct().listen((duration) {
      notifyListeners();
    });
  }

  final SettingsController _settings;
  final AudioPlayer _player;
  final MusicApi _api;
  final Future<File?> Function(Song song)? _localFileFor;
  final Future<LocalAudio?> Function(Song song) _localAudioFor;
  final CacheService _cacheService;
  final Future<void> Function(SettingsController settings) _maintainAudioCache;
  final LastPlaybackStore _lastPlaybackStore;
  final Future<void> Function()? _beforePlayback;
  late final StreamController<Duration> _positionController;
  late final Stream<Duration> _positionStream;

  StreamSubscription<PlaybackEvent>? _playbackSub;
  StreamSubscription<Duration>? _nativePositionSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration?>? _durationSub;
  Timer? _positionSampler;
  Duration? _lastEmittedPosition;
  DateTime? _resumeGuardUntil;
  Timer? _seekTimer;
  Duration? _pendingSeek;
  Duration? _deferredSeek;
  Completer<void>? _seekCompleter;
  bool _seekInFlight = false;
  Future<void>? _activeSeek;
  Timer? _volumeTimer;
  double? _pendingVolume;
  Completer<void>? _volumeCompleter;
  bool _volumeInFlight = false;
  bool _positionSourceReady = false;
  Future<void>? _restoreLastPlaybackFuture;

  List<Song> _queue = [];
  List<Song>? _queueSnapshot;
  int _index = -1;
  Song? _current;
  String _lyric = '';
  String? _effectiveQuality;
  AudioIdentity? _audioIdentity;
  bool _loading = false;
  bool _liked = false;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.all;
  VoidCallback? _onSleepTrackEnd;
  int? _sleepCompletedPlaySeq;

  Future<void> setStopAtTrackEnd(VoidCallback? onEnd) async {
    _onSleepTrackEnd = onEnd;
    await _player.setLoopMode(onEnd == null && _loopMode == LoopMode.one
        ? LoopMode.one
        : LoopMode.off);
  }

  String? _error;
  PlaybackErrorKind _errorKind = PlaybackErrorKind.none;

  bool get liked => _liked;
  bool get shuffle => _shuffle;
  LoopMode get loopMode => _loopMode;
  PlaybackMode get playbackMode => _shuffle
      ? PlaybackMode.shuffle
      : _loopMode == LoopMode.one
          ? PlaybackMode.singleLoop
          : PlaybackMode.listLoop;

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

  /// Native session for Android playback visualization; null until available.
  int? get audioSessionId => _player.androidAudioSessionId;
  Stream<int?> get audioSessionIdStream => _player.androidAudioSessionIdStream;
  Duration get position {
    if (!_positionSourceReady) return Duration.zero;
    return _guardPosition(_player.position);
  }

  /// Shared for the controller lifetime so widget rebuilds cannot restart the
  /// progress clock before it emits its next value.
  Stream<Duration> get positionStream => _positionStream;

  /// 已缓冲进度，供系统媒体控件绘制缓冲条。与 [position] 一样在音源就绪前返回零。
  Duration get bufferedPosition {
    if (!_positionSourceReady) return Duration.zero;
    return _player.bufferedPosition;
  }

  Duration? get duration =>
      _effectiveDuration(_positionSourceReady ? _player.duration : null);

  Duration? _effectiveDuration(Duration? loaded) {
    if (loaded != null && loaded > Duration.zero) return loaded;
    final actualMs = _audioIdentity?.durationMs ?? 0;
    final fallbackMs = actualMs > 0 ? actualMs : _current?.durationMs ?? 0;
    return fallbackMs > 0 ? Duration(milliseconds: fallbackMs) : loaded;
  }

  void _emitNativePosition({bool force = false}) {
    if (_positionController.isClosed) return;
    final nativePosition = position;
    _emitPosition(nativePosition, force: force);
  }

  void _onNativePosition(Duration nativePosition) {
    if (!_positionSourceReady) return;
    _emitPosition(_guardPosition(nativePosition));
  }

  Duration _guardPosition(Duration nativePosition) {
    final total = duration;
    final clamped = nativePosition < Duration.zero
        ? Duration.zero
        : total != null && nativePosition > total
            ? total
            : nativePosition;
    final previous = _lastEmittedPosition;
    final guardUntil = _resumeGuardUntil;
    // A resume can briefly report the old zero anchor. Hold the last observed
    // position for at most 250ms; never invent progress. Buffering, paused seeks
    // and persistent native resets must immediately use the actual timeline.
    if (previous != null &&
        clamped < previous &&
        _player.playing &&
        _player.processingState == ProcessingState.ready &&
        !_seekInFlight &&
        guardUntil != null &&
        DateTime.now().isBefore(guardUntil)) {
      return total != null && previous > total ? total : previous;
    }
    return clamped;
  }

  void _emitPosition(Duration nativePosition, {bool force = false}) {
    if (_positionController.isClosed) return;
    if (!force && nativePosition == _lastEmittedPosition) return;
    _lastEmittedPosition = nativePosition;
    _positionController.add(nativePosition);
  }

  void _startPositionSampling() {
    _emitNativePosition(force: true);
    _positionSampler ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _emitNativePosition(),
    );
  }

  void _stopPositionSampling() {
    _positionSampler?.cancel();
    _positionSampler = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _stopPositionSampling();
    if (_player.playing) _startPositionSampling();
    _emitNativePosition(force: true);
  }

  Future<void>? _resetSeekSession() {
    final activeSeek = _activeSeek;
    _seekTimer?.cancel();
    _seekTimer = null;
    _pendingSeek = null;
    _deferredSeek = null;
    _completeSeek();
    return activeSeek;
  }

  String get lyric => _lyric;
  String? get effectiveQuality => _effectiveQuality;
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

  Future<void> restoreLastPlayback({
    Future<Song?> Function()? preferredLoader,
  }) {
    return _restoreLastPlaybackFuture ??=
        _restoreLastPlayback(preferredLoader: preferredLoader);
  }

  Future<void> _restoreLastPlayback({
    Future<Song?> Function()? preferredLoader,
  }) async {
    final restoreSeq = _playSeq;
    Song? song;
    var loadedFromHistory = false;
    if (preferredLoader != null) {
      try {
        song = await preferredLoader();
        loadedFromHistory = true;
      } catch (_) {
        song = await _lastPlaybackStore.load();
      }
    } else {
      song = await _lastPlaybackStore.load();
    }
    if (song == null) {
      if (loadedFromHistory && _current == null && restoreSeq == _playSeq) {
        try {
          await _lastPlaybackStore.clear();
        } catch (_) {}
      }
      return;
    }
    if (_current != null || restoreSeq != _playSeq) return;
    _queue = [song];
    _queueSnapshot = null;
    _index = 0;
    _current = song;
    _clearResolvedAudio();
    _loading = false;
    _positionSourceReady = false;
    _lastEmittedPosition = null;
    _resumeGuardUntil = null;
    _emitNativePosition(force: true);
    notifyListeners();
    onSongChanged?.call(song);
    if (loadedFromHistory) {
      unawaited(_lastPlaybackStore.save(song).catchError((_) {}));
    }
  }

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
    final previousSeek = _resetSeekSession();
    _index = index;
    _current = _queue[index];
    _liked = false;
    _loading = true;
    _error = null;
    _errorKind = PlaybackErrorKind.none;
    _clearResolvedAudio();
    _positionSourceReady = false;
    _lastEmittedPosition = null;
    _resumeGuardUntil = null;
    _emitNativePosition(force: true);
    notifyListeners();
    onSongChanged?.call(_current!);
    try {
      await PlaybackCoordinator.instance.activate(this);
      if (seq != _playSeq) return;
      // Do not let a seek issued for the previous source overlap stop/load for
      // this source. A late native seek can otherwise target the new song.
      if (previousSeek != null) {
        try {
          await previousSeek;
        } catch (_) {}
        if (seq != _playSeq) return;
      }
      await _player.stop();
      if (seq != _playSeq) return;
      final song = _current!;
      final LocalAudio? downloaded;
      if (_localFileFor != null) {
        final file = await _localFileFor(song);
        downloaded = file == null
            ? null
            : LocalAudio(
                file: file,
                identity: AudioIdentity(source: song.source),
                quality: _settings.qualityForSource(song.source),
              );
      } else {
        downloaded = await _localAudioFor(song);
      }
      if (seq != _playSeq) return; // 已被更新的操作取代
      late AudioIdentity identity;
      late Uri audioUri;
      File? cacheFile;
      if (downloaded != null) {
        identity = downloaded.identity;
        audioUri = downloaded.file.uri;
        _effectiveQuality = downloaded.quality;
      } else {
        final resolved = await _resolveAudioUrl(song);
        if (seq != _playSeq) return;
        identity = resolved.info.audioIdentity;
        audioUri = Uri.parse(resolved.url);
        _effectiveQuality = resolved.quality;
        if (_settings.automaticAudioCache &&
            CacheService.supportsAutomaticAudioCache(identity.source)) {
          final file = await _cacheService.audioFileFor(
            song,
            resolved.quality,
            identity: identity,
          );
          if (await file.exists() && await file.length() > 0) {
            // The cached bytes determine their lyric identity, even if a new
            // play response now resolves to another recording.
            identity = await _cacheService.audioIdentityFor(file) ??
                AudioIdentity(source: identity.source);
            cacheFile = file;
          } else {
            try {
              await _cacheService.saveAudioIdentity(file, identity);
              cacheFile = file;
            } catch (_) {
              // Streaming can proceed when persistence is unavailable.
            }
          }
        }
      }
      if (seq != _playSeq) return;
      _audioIdentity = identity;
      final artworkUrl = normalizeRemoteImageUrl(song.album.picUrl);
      final artworkHeaders = imageRequestHeaders(artworkUrl);
      final metadataDurationMs =
          identity.durationMs > 0 ? identity.durationMs : song.durationMs;
      final mediaItem = MediaItem(
        id: song.id,
        title: song.name,
        artist: song.artistNames,
        album: song.album.name,
        artUri: artworkUrl == null ? null : Uri.tryParse(artworkUrl),
        artHeaders: artworkHeaders.isEmpty ? null : artworkHeaders,
        duration: metadataDurationMs > 0
            ? Duration(milliseconds: metadataDurationMs)
            : null,
      );
      final AudioSource source;
      final audioHeaders = audioHeadersFor(identity.source);
      if (cacheFile != null) {
        // just_audio's supported progressive audio cache API.
        // ignore: experimental_member_use
        source = LockCachingAudioSource(
          audioUri,
          cacheFile: cacheFile,
          headers: audioHeaders,
          tag: mediaItem,
        );
      } else {
        source = AudioSource.uri(
          audioUri,
          headers: audioUri.scheme == 'file' ? null : audioHeaders,
          tag: mediaItem,
        );
      }
      // 带 MediaItem 标签：系统通知栏/锁屏显示歌名、歌手、封面。
      await _player.setAudioSource(source).timeout(const Duration(seconds: 20));
      if (seq != _playSeq) return;
      _positionSourceReady = true;
      while (seq == _playSeq && _deferredSeek != null) {
        final deferredSeek = _deferredSeek!;
        _deferredSeek = null;
        await _seekNative(deferredSeek, seq);
      }
      if (seq != _playSeq) return;
      _loadLyric(seq, identity);
      _loading = false;
      _emitNativePosition(force: true);
      notifyListeners();

      await _prepareForPlayback();
      if (seq != _playSeq) return;
      // just_audio 的 play Future 在暂停或播放结束后才完成，不能在这里
      // await，否则整首歌期间都会被误判为“正在加载”。
      final playback = _player.play();
      notifyListeners();
      unawaited(_lastPlaybackStore.save(song).catchError((_) {}));
      unawaited(_maintainAudioCache(_settings));
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

  Future<ResolvedPlaybackInfo> _resolveAudioUrl(Song song) async {
    Object? lastError;
    final requestedQuality = _settings.qualityForSource(song.source);
    try {
      final resolved = await resolvePlaybackInfo(
        source: song.source,
        requestedQuality: requestedQuality,
        loadInfo: (quality) => _api
            .getPlaybackInfo(song.id, source: song.source, quality: quality)
            .timeout(const Duration(seconds: 12)),
      );
      if (resolved != null) return resolved;
    } on ApiException catch (error) {
      if (error.unauthorized || error.statusCode == 403) rethrow;
      lastError = error;
    } catch (error) {
      lastError = error;
    }
    if (lastError is ApiException) throw lastError;
    if (song.source.trim().toLowerCase() == 'qq') {
      throw Exception('当前 QQ 音乐播放地址不可用，请稍后重试');
    }
    throw Exception('未获取到播放地址，请切换音乐源后重试');
  }

  void _loadLyric(int seq, AudioIdentity identity) {
    final song = _current;
    if (song == null || !identity.canLoadLyrics) return;
    _api
        .getLyric(identity.id!, source: identity.source, requireVerified: true)
        .then((lrc) {
      if (seq != _playSeq || !identical(_audioIdentity, identity)) return;
      if (lrc != null && lrc.isNotEmpty && identical(_current, song)) {
        _lyric = lrc;
        notifyListeners();
      }
    }).catchError((_) {});
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    if (_positionSourceReady) _emitNativePosition();
    if (_positionSourceReady &&
        !_loading &&
        event.processingState != ProcessingState.loading &&
        _deferredSeek != null &&
        !_seekInFlight) {
      final deferredSeek = _deferredSeek!;
      _deferredSeek = null;
      _enqueueSeek(deferredSeek);
    }
    // 播放完毕自动切下一首（除非循环模式为 off 且当前为队列最后一首）
    if (_positionSourceReady &&
        !_loading &&
        event.processingState == ProcessingState.completed &&
        _queue.isNotEmpty) {
      if (_sleepCompletedPlaySeq == _playSeq) return;
      final sleepCallback = _onSleepTrackEnd;
      if (sleepCallback != null) {
        final completedSeq = _playSeq;
        _sleepCompletedPlaySeq = completedSeq;
        _onSleepTrackEnd = null;
        unawaited(Future<void>.microtask(() async {
          if (completedSeq != _playSeq) return;
          await _player.pause();
          if (completedSeq != _playSeq) return;
          await _player.setLoopMode(
              _loopMode == LoopMode.one && _onSleepTrackEnd == null
                  ? LoopMode.one
                  : LoopMode.off);
        }));
        sleepCallback();
        notifyListeners();
        return;
      }
      // 如果是"不循环"模式且播完最后一首，停在末尾不再自动播放
      if (_loopMode == LoopMode.off &&
          _index == _queue.length - 1 &&
          !_shuffle) {
        unawaited(_player.pause());
        unawaited(_player.seek(Duration.zero));
        notifyListeners();
        return;
      }
      unawaited(next());
      return;
    }
    notifyListeners();
  }

  void _onPlaybackError(Object error, StackTrace stackTrace) {
    // setAudioSource/play futures report errors with their own play sequence.
    // A shared stream error arriving during replacement may belong to the old
    // source and must not poison the newly selected song.
    if (_loading || !_positionSourceReady) return;
    _setPlaybackError(_playSeq, error);
  }

  void _setPlaybackError(int seq, Object error) {
    if (seq != _playSeq) return;
    _clearResolvedAudio();
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
    if (_error != null ||
        _player.processingState == ProcessingState.idle ||
        _sleepCompletedPlaySeq == _playSeq) {
      await playAt(_index);
      return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      await PlaybackCoordinator.instance.activate(this);
      final seq = _playSeq;
      await _prepareForPlayback();
      if (seq != _playSeq) return;
      unawaited(
          _player.play().catchError((Object error, StackTrace stackTrace) {
        _setPlaybackError(seq, error);
      }));
    }
    notifyListeners();
  }

  Future<void> _prepareForPlayback() async {
    try {
      await _beforePlayback?.call();
    } catch (_) {
      // A notification permission failure must never prevent audio playback.
    }
  }

  Future<void> retry() async {
    if (_index >= 0) await playAt(_index);
  }

  Future<void> stopAndClear({bool clearSavedPlayback = false}) async {
    ++_playSeq;
    _restoreLastPlaybackFuture = null;
    final previousSeek = _resetSeekSession();
    _clearResolvedAudio();
    _positionSourceReady = false;
    _lastEmittedPosition = null;
    _resumeGuardUntil = null;
    _emitNativePosition(force: true);
    if (previousSeek != null) {
      try {
        await previousSeek;
      } catch (_) {}
    }
    await _player.stop();
    _queue = [];
    _queueSnapshot = null;
    _index = -1;
    _current = null;
    _loading = false;
    _liked = false;
    _error = null;
    _errorKind = PlaybackErrorKind.none;
    notifyListeners();
    if (clearSavedPlayback) {
      try {
        await _lastPlaybackStore.clear();
      } catch (_) {}
    }
  }

  void _clearResolvedAudio() {
    _audioIdentity = null;
    _effectiveQuality = null;
    _lyric = '';
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

  Future<void> toggleShuffle() =>
      setPlaybackMode(_shuffle ? PlaybackMode.listLoop : PlaybackMode.shuffle);

  Future<void> cycleLoopMode() => cyclePlaybackMode();

  Future<void> cyclePlaybackMode() => setPlaybackMode(switch (playbackMode) {
        PlaybackMode.listLoop => PlaybackMode.singleLoop,
        PlaybackMode.singleLoop => PlaybackMode.shuffle,
        PlaybackMode.shuffle => PlaybackMode.listLoop,
      });

  Future<void> setPlaybackMode(PlaybackMode mode) async {
    _shuffle = mode == PlaybackMode.shuffle;
    _loopMode = mode == PlaybackMode.singleLoop ? LoopMode.one : LoopMode.all;
    await _player.setLoopMode(
      _loopMode == LoopMode.one && _onSleepTrackEnd == null
          ? LoopMode.one
          : LoopMode.off,
    );
    notifyListeners();
  }

  Future<void> seek(Duration position) {
    if (_current == null) return Future.value();
    final total = duration;
    final target = position < Duration.zero
        ? Duration.zero
        : total != null && position > total
            ? total
            : position;
    if (_loading ||
        !_positionSourceReady ||
        _player.processingState == ProcessingState.loading) {
      _deferredSeek = target;
      return Future.value();
    }
    return _enqueueSeek(target);
  }

  Future<void> _enqueueSeek(Duration target) {
    _pendingSeek = target;
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
    final seq = _playSeq;
    final target = _pendingSeek;
    _pendingSeek = null;
    if (target == null) {
      _completeSeek();
      return;
    }
    try {
      await _seekNative(target, seq);
      if (seq != _playSeq) return;
      if (_pendingSeek != null) {
        _scheduleSeekFlush();
      } else {
        _completeSeek();
      }
    } catch (error, stackTrace) {
      if (seq != _playSeq) return;
      _pendingSeek = null;
      _seekCompleter?.completeError(error, stackTrace);
      _seekCompleter = null;
    }
  }

  Future<void> _seekNative(Duration target, int seq) async {
    if (seq != _playSeq || !_positionSourceReady) return;
    _seekInFlight = true;
    final operation = _player.seek(target);
    _activeSeek = operation;
    try {
      await operation;
      if (seq == _playSeq) {
        if (_sleepCompletedPlaySeq == seq &&
            target < (duration ?? Duration.zero)) {
          _sleepCompletedPlaySeq = null;
        }
        _emitNativePosition(force: true);
      }
    } finally {
      if (identical(_activeSeek, operation)) _activeSeek = null;
      _seekInFlight = false;
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
    _clearResolvedAudio();
    WidgetsBinding.instance.removeObserver(this);
    PlaybackCoordinator.instance.unregister(this);
    _playbackSub?.cancel();
    _nativePositionSub?.cancel();
    _playingSub?.cancel();
    _durationSub?.cancel();
    _positionSampler?.cancel();
    _seekTimer?.cancel();
    _volumeTimer?.cancel();
    _seekCompleter?.complete();
    _volumeCompleter?.complete();
    _positionController.close();
    _player.dispose();
    super.dispose();
  }
}
