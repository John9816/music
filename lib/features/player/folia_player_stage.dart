import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/models/song.dart';
import '../../core/player/lrc_parser.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/audio_spectrum_service.dart';
import '../../core/settings/player_appearance.dart';
import '../../core/settings/settings_controller.dart';
import 'folia_timeline.dart';

/// A local, network-free Folia canvas. Native playback owns its clock and audio.
class FoliaPlayerStage extends StatefulWidget {
  const FoliaPlayerStage(
      {super.key,
      required this.song,
      required this.skin,
      required this.lrc,
      required this.visible,
      required this.onLyrics});
  final Song song;
  final PlayerSkin skin;
  final String lrc;
  final bool visible;
  final VoidCallback onLyrics;
  @override
  State<FoliaPlayerStage> createState() => _FoliaPlayerStageState();
}

class _FoliaPlayerStageState extends State<FoliaPlayerStage>
    with WidgetsBindingObserver {
  WebViewController? _web;
  PlayerController? _player;
  final _spectrum = AudioSpectrumService();
  StreamSubscription<List<double>>? _frames;
  StreamSubscription<int?>? _session;
  StreamSubscription<Duration>? _position;
  Timer? _timer, _timeout;
  bool _loaded = false, _ready = false, _failed = false;
  bool _foreground = true, _visible = true, _reduced = false;
  bool _contentDirty = true, _sending = false, _pending = false;
  int _sequence = 0, _generation = 0;
  int _fontSize = 30;
  int _fontWeight = 700;
  int _durationMs = 0;
  String _audioKey = '';
  List<double> _bands = List.filled(32, 0);
  bool get _supported => !kIsWeb && WebViewPlatform.instance != null;
  bool get _active => widget.visible && _foreground && _visible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _frames = _spectrum.frames.listen((values) => _bands = values);
    if (_supported) _createWebView();
  }

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
        await web.addJavaScriptChannel('DuckMusicFolia',
            onMessageReceived: (message) {
          if (!mounted || generation != _generation) return;
          try {
            final event = jsonDecode(message.message) as Map;
            switch (event['type']) {
              case 'loaded':
                if (_failed) return;
                _loaded = true;
                _enqueue();
              case 'ready':
                if (_failed) return;
                _timeout?.cancel();
                setState(() {
                  _ready = true;
                  _failed = false;
                });
              case 'failed':
                debugPrint('Folia ${widget.skin.name}: ${event['detail']}');
                _fail();
            }
          } catch (_) {
            _fail();
          }
        });
        await web.setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (request) => request.url.startsWith('file:///')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (generation == _generation && error.isForMainFrame == true) {
              _fail();
            }
          },
        ));
        if (!mounted || generation != _generation) return;
        await web.loadFlutterAsset('assets/player/folia/index.html');
        if (!mounted || generation != _generation) return;
        _timeout = Timer(const Duration(seconds: 20), () {
          if (!_ready) _fail();
        });
      } catch (error) {
        if (mounted && generation == _generation) _fail();
      }
    }());
  }

  void _fail() {
    if (!mounted || _failed) return;
    _timeout?.cancel();
    _loaded = false;
    unawaited(_web
            ?.runJavaScript('window.DuckFolia?.dispose();')
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
    final settings = Provider.of<SettingsController>(context);
    final weight = settings.lyricFontStyle.weight.value;
    if (_fontSize != settings.lyricFontSize || _fontWeight != weight) {
      _fontSize = settings.lyricFontSize;
      _fontWeight = weight;
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
  void didUpdateWidget(covariant FoliaPlayerStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.song.source != widget.song.source ||
        oldWidget.lrc != widget.lrc) {
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
      _timer ??=
          Timer.periodic(const Duration(milliseconds: 120), (_) => _enqueue());
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
        final packet = <String, Object>{
          'sequence': ++_sequence,
          'clock': {
            'positionMs': player.position.inMilliseconds,
            'durationMs': player.duration?.inMilliseconds ?? 0,
            'playing': player.playbackAdvancing,
            'visible': _active && !_failed,
            'reduced': _reduced,
          },
          'bands': _bands,
        };
        if (_contentDirty) {
          _contentDirty = false;
          packet['content'] = {
            'skin': widget.skin.name,
            'songKey': '${widget.song.source}:${widget.song.id}',
            'title': widget.song.name,
            'artist': widget.song.artistNames,
            'durationMs': player.duration?.inMilliseconds ?? 0,
            'fontScale': _fontSize / 30,
            'fontWeight': _fontWeight,
            'lines':
                foliaTimeline(widget.lrc, player.duration ?? Duration.zero),
          };
        }
        await web!
            .runJavaScript('window.DuckFolia?.receive(${jsonEncode(packet)});');
      }
    } catch (_) {
      if (identical(web, _web)) _fail();
    } finally {
      _sending = false;
      if (_pending && mounted && _loaded) _enqueue();
    }
  }

  void _retry() {
    unawaited(_web
            ?.runJavaScript('window.DuckFolia?.dispose();')
            .catchError((_) {}) ??
        Future<void>.value());
    setState(_createWebView);
    _sync();
  }

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
    _spectrum.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_web
            ?.runJavaScript('window.DuckFolia?.dispose();')
            .catchError((_) {}) ??
        Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      if (_web != null)
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
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (_web != null && !_failed) ...[
                          const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(height: 20),
                        ],
                        StreamBuilder<Duration>(
                            stream: _player?.positionStream,
                            initialData: _player?.position,
                            builder: (context, snapshot) {
                              final position = snapshot.data ?? Duration.zero;
                              final current = parseLrc(widget.lrc)
                                  .where((l) => l.time <= position)
                                  .lastOrNull;
                              return Text(current?.text ?? widget.song.name,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: _fontSize.toDouble(),
                                      color: Colors.white,
                                      height: 1.4));
                            }),
                        if (_failed) ...[
                          const SizedBox(height: 16),
                          const Text('当前设备暂时无法显示此皮肤',
                              style: TextStyle(color: Colors.white60)),
                          TextButton(
                              onPressed: _retry, child: const Text('重新加载')),
                        ],
                      ])),
                ))),
    ]);
  }
}
