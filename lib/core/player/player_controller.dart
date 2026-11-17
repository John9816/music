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
import '../services/artwork_color_service.dart';
import '../services/song_download_service.dart';
import '../services/local_music_service.dart';
import '../settings/settings_controller.dart';
import 'audio_source_policy.dart';
import 'last_playback_store.dart';
import 'playback_coordinator.dart';
import 'equalizer_controller.dart';
import 'source_fallback_resolver.dart';

enum PlaybackErrorKind { none, generic, loginRequired, membershipRequired }

enum PlaybackMode { listLoop, singleLoop, shuffle, sequential }

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
    bool enablePrefetch = true,
    bool enableAutoSkip = true,
    bool enableSourceFallback = true,
    bool enableAutoMix = true,
    Future<void> Function(Uri artworkUri)? warmArtwork,
    ArtworkColorService? artworkColorService,
  })  : _settings = settings,
        _enablePrefetch = enablePrefetch,
        _enableAutoSkip = enableAutoSkip,
        _enableSourceFallback = enableSourceFallback,
        _enableAutoMix = enableAutoMix,
        _warmArtwork = warmArtwork,
        _artworkColorService = artworkColorService,
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
    final effect =
        audioPlayer == null && defaultTargetPlatform == TargetPlatform.android
            ? AndroidEqualizer()
            : null;
    equalizer = EqualizerController(
        target: effect == null ? null : AndroidEqualizerTarget(effect));
    _player = audioPlayer ??
        AudioPlayer(
          useProxyForRequestHeaders:
              !usesNativeAudioHeaders(defaultTargetPlatform),
          audioPipeline: effect == null
              ? null
              : AudioPipeline(androidAudioEffects: [effect]),
        );
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
        // 只有在真正出声后才清零连续跳过计数。若仅 setAudioSource/play 成功
        // 但随后播放流报错，计数得以保留，避免坏歌被反复跳过形成死循环。
        _autoSkipStreak = 0;
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
  late final AudioPlayer _player;
  late final EqualizerController equalizer;
  final MusicApi _api;
  final Future<File?> Function(Song song)? _localFileFor;
  final Future<LocalAudio?> Function(Song song) _localAudioFor;
  final CacheService _cacheService;
  final Future<void> Function(SettingsController settings) _maintainAudioCache;
  final LastPlaybackStore _lastPlaybackStore;
  final Future<void> Function()? _beforePlayback;
  final bool _enablePrefetch;
  final bool _enableAutoSkip;
  final bool _enableSourceFallback;
  final bool _enableAutoMix;
  final Future<void> Function(Uri artworkUri)? _warmArtwork;
  final ArtworkColorService? _artworkColorService;

  /// 当前封面主色。播放页用它做切歌背景渐变过渡（对标 TuneFreeNext 的
  /// DynamicArtworkController）。未注入着色服务时保持初始中性色。
  static const Color fallbackArtworkColor = Color(0xff243746);
  final ValueNotifier<Color> artworkColor =
      ValueNotifier<Color>(fallbackArtworkColor);
  int _artworkColorSeq = 0;

  // --- AutoMix 平滑切歌（单 player 近似，对标 TuneFreeNext 的 AutoMix）---
  // 真原生 AutoMix 走 native_auto_mix_port 做双音轨交叉淡化 + ReplayGain；
  // 单 AudioPlayer 无法同时持有两条音轨，这里在“自然播放结束”切歌时做
  // 淡出→命中预取切歌→淡入，消除突兀静音断层。手动切歌不引入淡入延迟。
  int _autoMixFadeSeq = 0;
  double _autoMixTargetVolume = 1.0;

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

  int _queueGeneration = 0;
  int get queueGeneration => _queueGeneration;
  Future<bool> Function()? loadMoreQueue;
  List<Song> _queue = [];

  // --- 下一首预加载（对标 TuneFreeNext 的 _ensureNextPrepared /
  //     _prepareNextPlayable / _activatePreparedNext）---
  // 当前歌起播后提前解析下一首的播放地址并缓存；切歌命中即瞬时起播，
  // 不再需要等待网络解析，这正是安卓端“加载慢”的根治点。
  final Map<String, _PrefetchedPlayback> _prefetched = {};
  int _prefetchGeneration = 0;
  static const Duration _prefetchTtl = Duration(minutes: 5);

  /// 自动跳过计数器：连续跳过达到队列长度后停止，避免整队列不可播时死循环。
  int _autoSkipStreak = 0;
  Timer? _autoSkipTimer;

  void _invalidatePrefetch() {
    _prefetchGeneration++;
    _prefetched.clear();
  }

  String _songKey(Song song) => '${song.source}:${song.id}';

  void appendQueue(List<Song> songs, {required int generation}) {
    if (generation != _queueGeneration || songs.isEmpty) return;
    final seen = _queue.map((s) => '${s.source}:${s.id}').toSet();
    _invalidatePrefetch();
    _queue.addAll(songs.where((s) => seen.add('${s.source}:${s.id}')));
    if (_queue.length > 200 && _index > 20) {
      final remove = min(_index - 20, _queue.length - 200);
      _queue.removeRange(0, remove);
      _index -= remove;
    }
    _queueSnapshot = null;
    notifyListeners();
  }

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
          : _loopMode == LoopMode.off
              ? PlaybackMode.sequential
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
  bool get playbackAdvancing =>
      _player.playing &&
      !_loading &&
      _player.processingState == ProcessingState.ready;

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
    _queueGeneration++;
    _invalidatePrefetch();
    loadMoreQueue = null;
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
    _invalidatePrefetch();
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
    _invalidatePrefetch();
    notifyListeners();
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final seq = ++_playSeq;
    // 新的播放请求取消上一轮待执行的自动跳过，避免手动干预后被旧定时器切走。
    _autoSkipTimer?.cancel();
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
      final localUri = song.source == 'local'
          ? await LocalMusicService.instance.playbackUriFor(song)
          : null;
      final LocalAudio? downloaded;
      if (song.source == 'local') {
        downloaded = null;
        if (localUri == null) throw StateError('本地音乐不可读取，请重新扫描或检查音乐权限');
      } else if (_localFileFor != null) {
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
      if (localUri != null) {
        identity = const AudioIdentity(source: 'local');
        audioUri = localUri;
        _effectiveQuality = 'local';
      } else if (downloaded != null) {
        identity = downloaded.identity;
        audioUri = downloaded.file.uri;
        _effectiveQuality = downloaded.quality;
      } else {
        // 命中预取：切歌时直接使用上一首播放期间已解析好的地址，零网络等待。
        // 地址带时效签名，超过 TTL 视为失效并退回正常解析。
        final key = _songKey(song);
        final prefetched = _prefetched.remove(key);
        final bool prefetchedFresh = prefetched != null &&
            DateTime.now().difference(prefetched.resolvedAt) < _prefetchTtl;
        final ResolvedPlaybackInfo resolved = prefetchedFresh
            ? prefetched.resolved
            : await _resolveAudioUrl(song);
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
      // 封面预热 + 主色提取（对标 TuneFreeNext 的封面预取 + palette 过渡）。
      // 二者都在后台进行，绝不阻塞播放；用 seq 保护避免旧歌结果覆盖新歌。
      _updateArtworkColor(seq, artworkUrl);
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
          headers: audioUri.scheme == 'http' || audioUri.scheme == 'https'
              ? audioHeaders
              : null,
          tag: mediaItem,
        );
      }
      // 带 MediaItem 标签：系统通知栏/锁屏显示歌名、歌手、封面。
      await _player.setAudioSource(source).timeout(Duration(
          seconds: identity.source == 'qishui' && audioUri.scheme != 'file'
              ? 90
              : 20));
      if (seq != _playSeq) return;
      _positionSourceReady = true;
      unawaited(equalizer.initialize());
      while (seq == _playSeq && _deferredSeek != null) {
        final deferredSeek = _deferredSeek!;
        _deferredSeek = null;
        await _seekNative(deferredSeek, seq);
      }
      if (seq != _playSeq) return;
      if (song.source != 'local') _loadLyric(seq, identity);
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
      if (seq == _playSeq) {
        onSongPlayed?.call(song);
        // 当前歌已起播，后台预解析下一首；不阻塞播放。
        // 连续跳过计数只在 playingStream 确认真正出声后清零。
        _triggerPrefetchNext(seq);
      }
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

  /// 计算“下一首”索引，与 [next] 的顺序/shuffle 语义保持一致，
  /// 但不触发 loadMoreQueue 副作用（预取不能改变队列）。
  int? _peekNextIndex() {
    if (_queue.isEmpty || _index < 0) return null;
    if (_shuffle && _queue.length > 1) {
      // shuffle 的下一首由 next() 用 Random 决定，无法预测，故不预取。
      return null;
    }
    final next = _index + 1;
    if (next < _queue.length) return next;
    // 队尾：单曲循环/顺序模式不会自动前进；列表循环会回到开头。
    if (_loopMode == LoopMode.all && _queue.length > 1) return 0;
    return null;
  }

  /// 后台预解析下一首。只在确实需要网络解析的曲目上做，且用
  /// playSeq + prefetchGeneration 双重保护：切歌或队列变化后旧结果作废。
  void _triggerPrefetchNext(int seq) {
    if (!_enablePrefetch) return;
    if (seq != _playSeq) return;
    final nextIndex = _peekNextIndex();
    if (nextIndex == null) return;
    final song = _queue[nextIndex];
    if (song.source == 'local') return;
    final key = _songKey(song);
    final cached = _prefetched[key];
    if (cached != null &&
        DateTime.now().difference(cached.resolvedAt) < _prefetchTtl) {
      return;
    }
    final generation = _prefetchGeneration;
    unawaited(() async {
      try {
        // 下一首可能已有下载文件或本地缓存，此时无需网络预解析。
        final hasLocal = await _hasLocalAudio(song);
        if (hasLocal) return;
        if (seq != _playSeq || generation != _prefetchGeneration) return;
        final resolved = await _resolveAudioUrl(song, prefetch: true);
        if (seq != _playSeq || generation != _prefetchGeneration) return;
        // 队列顺序可能已变，确认这首歌仍是预期的下一首。
        if (_peekNextIndex() != nextIndex) return;
        _prefetched[key] = _PrefetchedPlayback(resolved, DateTime.now());
        // 音源就绪的同时预热下一首封面：切歌瞬间封面与主色已就位，
        // 消除模糊背景二次加载造成的视觉卡顿。
        if (_settings.crossfadeArtwork) {
          final nextArt = normalizeRemoteImageUrl(song.album.picUrl);
          final nextUri = nextArt == null ? null : Uri.tryParse(nextArt);
          final warm = _warmArtwork;
          if (nextUri != null && warm != null) {
            unawaited(warm(nextUri).catchError((_) {}));
          }
        }
      } catch (_) {
        // 预取失败静默忽略：切歌时会走正常解析，用户无感。
      }
    }());
  }

  /// 后台预热当前封面并提取主色。切歌时旧主色保留，新主色就绪后由 UI
  /// 的 AnimatedContainer 平滑过渡过去。seq 保证乱序结果不会串色。
  void _updateArtworkColor(int seq, String? artworkUrl) {
    if (!_settings.crossfadeArtwork) return;
    final generation = ++_artworkColorSeq;
    if (artworkUrl == null || artworkUrl.isEmpty) return;
    final uri = Uri.tryParse(artworkUrl);
    if (uri == null) return;
    final warm = _warmArtwork;
    if (warm != null) unawaited(warm(uri).catchError((_) {}));
    final service = _artworkColorService;
    if (service == null) return;
    unawaited(service.colorFor(uri).then((color) {
      if (seq != _playSeq || generation != _artworkColorSeq) return;
      if (color != null) artworkColor.value = color;
    }).catchError((_) {}));
  }

  /// 判断一首歌是否已有可直接播放的本地来源（本地音乐 / 已下载）。
  Future<bool> _hasLocalAudio(Song song) async {
    if (song.source == 'local') return true;
    try {
      final localFileFor = _localFileFor;
      if (localFileFor != null && await localFileFor(song) != null) {
        return true;
      }
      final local = await _localAudioFor(song);
      return local != null;
    } catch (_) {
      return false;
    }
  }

  Future<ResolvedPlaybackInfo> _resolveAudioUrl(
    Song song, {
    bool prefetch = false,
    bool allowFallback = true,
  }) async {
    Object? lastError;
    final requestedQuality = _settings.qualityForSource(song.source);
    try {
      final resolved = await resolvePlaybackInfo(
        source: song.source,
        requestedQuality: requestedQuality,
        loadInfo: (quality) => _api
            .getPlaybackInfo(
              song.id,
              source: song.source,
              quality: quality,
              prefetch: prefetch,
            )
            .timeout(const Duration(seconds: 12)),
      );
      if (resolved != null) return resolved;
    } on ApiException catch (error) {
      if (error.unauthorized || error.statusCode == 403) rethrow;
      lastError = error;
    } catch (error) {
      lastError = error;
    }

    // 自动换源（对标 TuneFreeNext 的 AutomaticSourceFallbackResolver）：
    // 普通“拿不到地址”失败时，跨备用音源搜索同一首歌，按歌名+歌手+时长打分
    // 选最佳候选重解析。会员/登录错误在上方已 rethrow，不会走到这里。
    // 预热预取不触发换源，避免后台放大请求。
    if (allowFallback &&
        !prefetch &&
        _enableSourceFallback &&
        _settings.autoSourceFallback) {
      final fallback = await _tryFallbackSource(song);
      if (fallback != null) return fallback;
    }

    if (lastError is ApiException) throw lastError;
    if (song.source.trim().toLowerCase() == 'qq') {
      throw Exception('当前 QQ 音乐播放地址不可用，请稍后重试');
    }
    throw Exception('未获取到播放地址，请切换音乐源后重试');
  }

  /// 跨备用音源打分匹配同一首歌，返回最佳候选的可播放信息。
  /// 顺序遍历备用源，每个源搜索一次并取打分最高的候选；全失败返回 null。
  static const List<String> _fallbackSources = ['netease', 'qq', 'kuwo', 'qishui'];
  static const SourceFallbackResolver _sourceResolver = SourceFallbackResolver();

  Future<ResolvedPlaybackInfo?> _tryFallbackSource(Song song) async {
    final originalSource = song.source.trim().toLowerCase();
    final leadArtist = song.artists.isEmpty ? '' : song.artists.first.name;
    final keyword = leadArtist.isEmpty ? song.name : '${song.name} $leadArtist';
    for (final source in _fallbackSources) {
      if (source == originalSource) continue;
      List<Song> candidates;
      try {
        candidates = await _api
            .searchSongs(keyword, source: source, limit: 8)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        continue;
      }
      final best = _sourceResolver.bestCandidateOrNull(song, candidates);
      if (best == null) continue;
      try {
        // allowFallback:false 防止候选再次失败时递归换源。
        return await _resolveAudioUrl(best, allowFallback: false);
      } catch (_) {
        // 该候选不可用，继续下一个音源。
      }
    }
    return null;
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
          loadMoreQueue == null &&
          _index == _queue.length - 1 &&
          !_shuffle) {
        final completedSeq = _playSeq;
        _sleepCompletedPlaySeq = completedSeq;
        unawaited(Future<void>.microtask(() async {
          if (completedSeq != _playSeq) return;
          await _player.pause();
        }));
        notifyListeners();
        return;
      }
      // 自然播放结束：AutoMix 开启时走平滑淡出淡入切歌。
      unawaited(next(smooth: true));
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
      return;
    }
    // 解析/播放失败自动跳过：只对普通失败生效，登录/会员错误必须让用户看到。
    // 单首歌或整队列都试过仍失败时保留错误提示，避免死循环。
    if (_errorKind == PlaybackErrorKind.generic) {
      _scheduleAutoSkip(seq);
    }
  }

  /// 失败后短暂延时自动切到下一首（对标 TuneFreeNext 的 auto_skip_unplayable）。
  /// 延时给用户一个看到错误的瞬间，也避免与本轮错误流抢占状态。
  void _scheduleAutoSkip(int seq) {
    if (!_enableAutoSkip || !_settings.autoSkipUnplayable) return;
    if (seq != _playSeq) return;
    if (_queue.length <= 1) return; // 无处可跳，保留错误可见
    if (_autoSkipStreak >= _queue.length) return; // 已跳过一整轮，停止

    _autoSkipTimer?.cancel();
    _autoSkipStreak++;
    _autoSkipTimer = Timer(const Duration(milliseconds: 350), () {
      if (seq != _playSeq) return;
      final nextIndex = _peekNextIndex();
      if (nextIndex == null || nextIndex == _index) return;
      _error = null;
      _errorKind = PlaybackErrorKind.none;
      unawaited(next());
    });
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
        _player.processingState == ProcessingState.completed ||
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
    _invalidatePrefetch();
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
    _queueGeneration++;
    loadMoreQueue = null;
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

  Future<void> next({bool smooth = false}) async {
    // AutoMix 平滑切歌：仅在自然播放结束时由调用方传 smooth=true。
    // 手动点“下一首”不引入淡出延迟，保持即时响应。
    final doSmooth = smooth &&
        _enableAutoMix &&
        _settings.autoMix &&
        _queue.length > 1;
    if (!doSmooth) {
      await _nextCore();
      return;
    }
    final fadeSeq = ++_autoMixFadeSeq;
    _autoMixTargetVolume = _player.volume;
    await _autoMixFadeTo(0.0, const Duration(milliseconds: 110), fadeSeq);
    try {
      await _nextCore();
    } finally {
      // 即使切歌失败也恢复音量，避免卡在静音。
      if (fadeSeq == _autoMixFadeSeq) {
        await _autoMixFadeTo(
            _autoMixTargetVolume, const Duration(milliseconds: 180), fadeSeq);
      }
    }
  }

  /// 把播放器音量在 [duration] 内平滑过渡到 [target]。
  /// 使用 just_audio 的 setVolume（底层 ExoPlayer/AVPlayer 支持运行时调音量），
  /// fadeSeq 变化（新一轮切歌/用户干预）时立即中止旧的渐变。
  Future<void> _autoMixFadeTo(double target, Duration duration, int fadeSeq) async {
    final from = _player.volume;
    const steps = 4;
    for (var i = 1; i <= steps; i++) {
      if (fadeSeq != _autoMixFadeSeq) return;
      final value = from + (target - from) * (i / steps);
      try {
        await _player.setVolume(value.clamp(0.0, 1.0));
      } catch (_) {
        return;
      }
      if (i < steps) {
        await Future<void>.delayed(duration ~/ steps);
      }
    }
  }

  Future<void> _nextCore() async {
    if (_queue.isEmpty) return;
    final continuation = loadMoreQueue;
    if (continuation != null && _index == _queue.length - 1) {
      final generation = _queueGeneration;
      final playSequence = _playSeq;
      final hasMore = await continuation();
      if (generation != _queueGeneration || playSequence != _playSeq) return;
      if (!hasMore && _index == _queue.length - 1) {
        await pause();
        return;
      }
    }
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
        PlaybackMode.shuffle ||
        PlaybackMode.sequential =>
          PlaybackMode.listLoop,
      });

  Future<void> setPlaybackMode(PlaybackMode mode) async {
    _shuffle = mode == PlaybackMode.shuffle;
    _invalidatePrefetch();
    _loopMode = switch (mode) {
      PlaybackMode.singleLoop => LoopMode.one,
      PlaybackMode.sequential => LoopMode.off,
      _ => LoopMode.all,
    };
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
    equalizer.dispose();
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
    _autoSkipTimer?.cancel();
    _invalidatePrefetch();
    artworkColor.dispose();
    _positionController.close();
    _player.dispose();
    super.dispose();
  }
}

/// 预解析好的下一首播放信息。[resolvedAt] 用于过期判断——播放地址通常
/// 带时效签名，过旧的预取结果不能再用。
class _PrefetchedPlayback {
  const _PrefetchedPlayback(this.resolved, this.resolvedAt);

  final ResolvedPlaybackInfo resolved;
  final DateTime resolvedAt;
}
