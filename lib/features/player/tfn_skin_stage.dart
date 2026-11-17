import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/audio_spectrum_service.dart';
import '../../core/services/skin_asset_server.dart';
import '../../core/settings/player_appearance.dart';
import '../../core/settings/settings_controller.dart';
import 'folia_timeline.dart';

/// TuneFreeNext 4.3.7 同款播放页皮肤舞台。
///
/// 加载 App 内置的 Folia(Lumiere/Hanabi) 与 Nebbia 渲染器，通过本地 HttpServer
/// 提供 ES module 资源，按 `window.TfnNebbia.receive(packet)` 协议推送时钟、
/// 歌词与频谱。协议字段与对方 host.js 逐项对齐。
class TfnSkinStage extends StatefulWidget {
  const TfnSkinStage({
    super.key,
    required this.song,
    required this.skin,
    required this.lrc,
    required this.visible,
    required this.onLyrics,
  });

  final Song song;
  final TfnSkin skin;
  final String lrc;
  final bool visible;
  final VoidCallback onLyrics;

  @override
  State<TfnSkinStage> createState() => _TfnSkinStageState();
}

class _TfnSkinStageState extends State<TfnSkinStage>
    with WidgetsBindingObserver {
  WebViewController? _web;
  PlayerController? _player;
  final _spectrum = AudioSpectrumService();
  StreamSubscription<List<double>>? _frames;
  StreamSubscription<int?>? _session;
  StreamSubscription<Duration>? _position;
  Timer? _timer, _timeout;
  String? _origin;
  bool _loaded = false, _ready = false, _failed = false;
  bool _foreground = true, _visible = true, _reduced = false;
  bool _contentDirty = true, _sending = false, _pending = false;
  int _sequence = 0, _generation = 0;
  int _fontSize = 30;
  List<double> _bands = List.filled(32, 0);
  String _audioKey = '';
  int _durationMs = 0;
  SkinFrameRate _frameRate = SkinFrameRate.balanced;

  bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS) &&
      WebViewPlatform.instance != null;
  bool get _active => widget.visible && _foreground && _visible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _frames = _spectrum.frames.listen((values) => _bands = values);
    if (_supported) _bootstrapAndCreate();
  }

  Future<void> _bootstrapAndCreate() async {
    try {
      final origin = await SkinAssetServer.instance.start();
      if (!mounted) return;
      setState(() => _origin = origin);
      _createWebView();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// 皮肤 → 资源子目录与 skin 标识。
  ({String dir, String skin}) get _engine => switch (widget.skin) {
        TfnSkin.lumiere => (dir: 'folia', skin: 'lumiere'),
        TfnSkin.hanabi => (dir: 'folia', skin: 'hanabi'),
        TfnSkin.nebbia => (dir: 'nebbia', skin: 'nebbia'),
      };

  void _createWebView() {
    final generation = ++_generation;
    _loaded = false;
    _ready = false;
    _failed = false;
    _contentDirty = true;
    _timeout?.cancel();
    final web = WebViewController();
    _web = web;
    unawaited(() async {
      try {
        await web.setJavaScriptMode(JavaScriptMode.unrestricted);
        await web.setBackgroundColor(Colors.transparent);
        await web.addJavaScriptChannel('TfnNebbiaHost',
            onMessageReceived: (message) {
          if (!mounted || generation != _generation) return;
          try {
            final event = jsonDecode(message.message) as Map;
            switch (event['type']) {
              case 'loaded':
                if (!_failed) {
                  _loaded = true;
                  _enqueue();
                }
              case 'frame':
                if (!_failed) {
                  _timeout?.cancel();
                  if (!_ready) setState(() => _ready = true);
                }
              case 'failed':
                _fail();
            }
          } catch (_) {
            _fail();
          }
        });
        if (!mounted || generation != _generation) return;
        final engine = _engine;
        final base = _origin ?? '';
        await web.loadRequest(Uri.parse('$base/${engine.dir}/index.html'));
        if (!mounted || generation != _generation) return;
        _timeout = Timer(const Duration(seconds: 20), () {
          if (!_ready) _fail();
        });
      } catch (_) {
        if (mounted && generation == _generation) _fail();
      }
    }());
  }

  void _fail() {
    if (!mounted || _failed) return;
    _timeout?.cancel();
    _loaded = false;
    unawaited(_web
            ?.runJavaScript('window.TfnNebbia?.dispose();')
            .catchError((_) {}) ??
        Future<void>.value());
    setState(() {
      _failed = true;
      _ready = false;
    });
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _reduced = MediaQuery.disableAnimationsOf(context);
    final settings = context.read<SettingsController>();
    if (_fontSize != settings.lyricFontSize ||
        _frameRate != settings.skinFrameRate) {
      _fontSize = settings.lyricFontSize;
      _frameRate = settings.skinFrameRate;
      _contentDirty = true;
    }
    if (_player == null) {
      _player = context.read<PlayerController>()..addListener(_sync);
      _session = _player!.audioSessionIdStream.listen((_) => _sync());
      _position = _player!.positionStream.listen((_) {
        if (!_player!.playbackAdvancing) _enqueue();
      });
    }
    _sync();
  }

  @override
  void didUpdateWidget(covariant TfnSkinStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.song.source != widget.song.source ||
        oldWidget.lrc != widget.lrc ||
        oldWidget.skin != widget.skin) {
      _contentDirty = true;
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (!mounted || _player == null) return;
    final duration = _player!.duration?.inMilliseconds ?? 0;
    if (duration != _durationMs) {
      _durationMs = duration;
      _contentDirty = true;
    }
    final animate = _active && !_failed && _web != null;
    if (animate && _player!.playbackAdvancing) {
      _timer ??= Timer.periodic(const Duration(milliseconds: 120), (_) {
        _enqueue();
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
    final audio = animate && !_reduced && _player!.playing;
    final key = '$audio:${_player!.audioSessionId}';
    if (key != _audioKey) {
      _audioKey = key;
      if (audio) {
        unawaited(_spectrum.start(_player!.audioSessionId ?? 0));
      } else {
        unawaited(_spectrum.stop());
      }
    }
    _enqueue();
  }

  void _enqueue() {
    if (!_loaded || _web == null || _player == null || !mounted) return;
    _pending = true;
    if (!_sending) unawaited(_flush());
  }

  Future<void> _flush() async {
    _sending = true;
    final web = _web;
    try {
      while (_pending && mounted && _loaded && identical(web, _web)) {
        _pending = false;
        final player = _player!;
        final bands = _bands;
        final bass = _avg(bands, 0, 2);
        final vocal = _avg(bands, 4, 8);
        final power = _avg(bands, 0, bands.length);
        final clock = <String, Object>{
          'position': player.position.inMilliseconds,
          'duration': player.duration?.inMilliseconds ?? 0,
          'playing': player.playbackAdvancing,
          'active': _active && !_failed,
          'reduceMotion': _reduced,
          'bands': bands,
          'bass': bass,
          'vocal': vocal,
          'power': power,
        };
        final packet = <String, Object>{
          'sequence': ++_sequence,
          'clock': clock,
        };
        if (_contentDirty) {
          _contentDirty = false;
          packet['content'] = _buildContent(player);
        }
        await web!.runJavaScript(
            'window.TfnNebbia?.receive(${jsonEncode(packet)});');
      }
    } catch (_) {
      if (identical(web, _web)) _fail();
    } finally {
      _sending = false;
      if (_pending && mounted && _loaded) _enqueue();
    }
  }

  double _avg(List<double> values, int from, int to) {
    final end = to.clamp(from, values.length);
    if (end <= from) return 0;
    var sum = 0.0;
    for (var i = from; i < end; i++) {
      sum += values[i];
    }
    return sum / (end - from);
  }

  /// 构造与对方 host.js 对齐的 content 对象。
  Map<String, Object> _buildContent(PlayerController player) {
    final engine = _engine;
    final lines = foliaTimeline(widget.lrc, player.duration ?? Duration.zero);
    final seed = _seedFor(widget.song);
    return {
      'skin': engine.skin,
      'songKey': '${widget.song.source}:${widget.song.id}',
      'trackIdentity': '${widget.song.source}:${widget.song.id}',
      'song': {
        'seed': seed,
        'title': widget.song.name,
        'artist': widget.song.artistNames,
        'duration': player.duration?.inMilliseconds ?? 0,
        'lines': lines,
      },
      'theme': {
        'name': '',
        'description': '',
        'fontStyle': 'sans',
        'fontWeight': 500,
        'animationIntensity': 'normal',
        'secondaryColor': '#b7b8d8',
        'backgroundColor': '#10121a',
        'wordColors': <String>[],
        'lyricsIcons': <String>[],
      },
      'tuning': <String, Object>{},
      'performance': {
        'maxFps': _frameRate.maxFps,
        'pixelRatioCap': _frameRate.pixelRatioCap,
      },
      'lyricScale': _fontSize / 30,
      'scale': 1.0,
      'insets': {
        'top': 0.0,
        'bottom': 0.0,
      },
    };
  }

  /// 稳定的曲目种子：歌词种子只依赖曲目身份，歌词晚到也不改。
  int _seedFor(Song song) =>
      '${song.source}:${song.id}'.hashCode & 0x7fffffff;

  @override
  void dispose() {
    ++_generation;
    _loaded = false;
    _timer?.cancel();
    _timeout?.cancel();
    _player?.removeListener(_sync);
    _frames?.cancel();
    _session?.cancel();
    _position?.cancel();
    unawaited(_spectrum.stop());
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_web
            ?.runJavaScript('window.TfnNebbia?.dispose();')
            .catchError((_) {}) ??
        Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      if (_web != null && !_failed)
        IgnorePointer(
            child:
                WebViewWidget(key: ValueKey(_generation), controller: _web!)),
      if (_ready)
        Semantics(
            button: true,
            label: '打开完整歌词',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onLyrics,
            )),
      if (!_ready)
        GestureDetector(
          onTap: widget.onLyrics,
          behavior: HitTestBehavior.opaque,
          child: ColoredBox(
              color: _failed ? const Color(0xff14141c) : Colors.transparent,
              child: Center(
                child: !_failed
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('当前设备暂时无法显示此皮肤',
                            style: TextStyle(color: Colors.white60)),
                        TextButton(
                            onPressed: () {
                              setState(() => _failed = false);
                              _createWebView();
                            },
                            child: const Text('重新加载')),
                      ]),
              )),
        ),
    ]);
  }
}
