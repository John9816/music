import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/player/player_controller.dart';
import '../../core/player/lrc_parser.dart';
import '../../core/services/audio_spectrum_service.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/settings/lyric_appearance.dart';
import '../../widgets/glass.dart';
import 'karaoke_lyric_text.dart';

class SpectrumPlayerView extends StatefulWidget {
  const SpectrumPlayerView({super.key});
  @override
  State<SpectrumPlayerView> createState() => _SpectrumPlayerViewState();
}

class _SpectrumPlayerViewState extends State<SpectrumPlayerView>
    with WidgetsBindingObserver {
  final _spectrum = AudioSpectrumService();
  final _bands = ValueNotifier<List<double>>(List.filled(32, 0));
  StreamSubscription<List<double>>? _frames;
  StreamSubscription<int?>? _session;
  PlayerController? _player;
  bool _playing = false;
  bool _visible = true;
  bool _foreground = true;
  bool _reducedMotion = false;
  int? _sessionId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _frames = _spectrum.frames.listen((values) {
      _bands.value = values;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (_player == null) {
      _player = context.read<PlayerController>()..addListener(_updatePlayback);
      _sessionId = _player!.audioSessionId;
      _session = _player!.audioSessionIdStream.listen((id) {
        _sessionId = id;
        _sync();
      });
      _playing = _player!.playing;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sync();
      });
    }
    if (_visible != visible || _reducedMotion != reduced) {
      _visible = visible;
      _reducedMotion = reduced;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sync();
      });
    }
  }

  void _updatePlayback() {
    final playing = _player!.playing;
    if (playing == _playing) return;
    _playing = playing;
    _sync();
  }

  void _sync({bool requestPermission = false}) {
    if (!_visible || !_foreground || !_playing || _reducedMotion) {
      unawaited(_spectrum.stop());
      return;
    }
    unawaited(
        _spectrum.start(_sessionId ?? 0, requestPermission: requestPermission));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player?.removeListener(_updatePlayback);
    _frames?.cancel();
    _session?.cancel();
    _spectrum.dispose();
    _bands.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final song = player.current;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
          backgroundColor: const Color(0xff050505),
          body: Stack(fit: StackFit.expand, children: [
            Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 160,
                child: RepaintBoundary(
                    child: CustomPaint(painter: _SpectrumPainter(_bands)))),
            SafeArea(
                child: Column(children: [
              GToolbar(
                  leading: GToolbarButton(
                      tooltip: '返回播放器',
                      onTap: () => Navigator.pop(context),
                      icon: Icons.arrow_downward_rounded,
                      tint: Colors.white)),
              Expanded(
                  child: Align(
                      alignment: const Alignment(0, -.2),
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            _SpectrumLyricFocus(
                                key: ValueKey(
                                    (song?.source, song?.id, player.lyric)),
                                lrc: player.lyric),
                            ListenableBuilder(
                                listenable: _spectrum,
                                builder: (context, _) {
                                  final needsPermission = _spectrum.status ==
                                      AudioSpectrumStatus.permissionRequired;
                                  if (needsPermission) {
                                    return Padding(
                                        padding: const EdgeInsets.only(top: 24),
                                        child: Column(children: [
                                          const Text('启用频谱需系统音频权限，仅用于可视化当前播放',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 12)),
                                          TextButton(
                                              onPressed: () => _sync(
                                                  requestPermission: true),
                                              child: const Text('启用频谱')),
                                        ]));
                                  }
                                  if (_spectrum.status ==
                                      AudioSpectrumStatus.unavailable) {
                                    return Padding(
                                        padding: const EdgeInsets.only(top: 20),
                                        child: Text(_spectrum.message,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 12)));
                                  }
                                  return const SizedBox.shrink();
                                }),
                          ])))),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 72),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                            tooltip: '上一首',
                            onPressed: player.previous,
                            icon: const Icon(CupertinoIcons.backward_end_fill,
                                color: Colors.white70, size: 23)),
                        IconButton(
                            tooltip: player.playing ? '暂停' : '播放',
                            onPressed:
                                player.loading ? null : player.togglePlay,
                            icon: Icon(
                                player.playing
                                    ? CupertinoIcons.pause_fill
                                    : CupertinoIcons.play_fill,
                                color: Colors.white70,
                                size: 26)),
                        IconButton(
                            tooltip: '下一首',
                            onPressed: player.next,
                            icon: const Icon(CupertinoIcons.forward_end_fill,
                                color: Colors.white70, size: 23)),
                      ])),
              Padding(
                  padding: const EdgeInsets.fromLTRB(36, 12, 36, 24),
                  child: Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                              onPrimary: Colors.white,
                              surfaceContainerHighest: const Color(0xff444444),
                            ),
                      ),
                      child: StreamBuilder<Duration>(
                          stream: player.positionStream,
                          initialData: player.position,
                          builder: (_, snapshot) => GProgressBar(
                              position: snapshot.data ?? player.position,
                              duration: player.duration ?? Duration.zero,
                              onSeek: player.seek,
                              height: 1.5,
                              activeColor: Colors.white60)))),
            ])),
          ])),
    );
  }
}

class _SpectrumLyricFocus extends StatefulWidget {
  const _SpectrumLyricFocus({super.key, required this.lrc});
  final String lrc;

  @override
  State<_SpectrumLyricFocus> createState() => _SpectrumLyricFocusState();
}

class _SpectrumLyricFocusState extends State<_SpectrumLyricFocus> {
  late final List<LrcLine> _lines = parseLrc(widget.lrc);
  PlayerController? _player;
  late Stream<int> _lineChanges;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final player = context.read<PlayerController>();
    if (_player != player) {
      _player = player;
      _lineChanges = player.positionStream.map(_currentLine).distinct();
    }
  }

  int _currentLine(Duration position) {
    var low = 0;
    var high = _lines.length - 1;
    var current = -1;
    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      if (_lines[middle].time <= position) {
        current = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return current;
  }

  @override
  Widget build(BuildContext context) {
    final player = _player!;
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final settings = context.watch<SettingsController>();
    final style = lyricTextStyle(
      DefaultTextStyle.of(context).style.copyWith(color: Colors.white),
      fontSize: settings.lyricFontSize,
      fontStyle: settings.lyricFontStyle,
    );
    return StreamBuilder<int>(
      stream: _lineChanges,
      initialData: _currentLine(player.position),
      builder: (context, snapshot) {
        final index = snapshot.data ?? _currentLine(player.position);
        final line = index >= 0 ? _lines[index] : null;
        final next = index + 1 < _lines.length ? _lines[index + 1] : null;
        final text = _lines.isEmpty
            ? (widget.lrc.trim().isEmpty ? '暂无歌词' : widget.lrc.trim())
            : line == null || line.text.isEmpty
                ? '· · ·'
                : line.text;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(colors: [
              Color(0xffe2cb7d),
              Color(0xffdbb5bc),
              Color(0xffbcb4ef),
            ]).createShader(rect),
            child: line != null && line.words.isNotEmpty
                ? KaraokeLyricText(
                    line: line,
                    style: style,
                    position: player.position,
                    positionStream: player.positionStream,
                    playing: playing,
                    textAlign: TextAlign.center,
                  )
                : Text(text, textAlign: TextAlign.center, style: style),
          ),
          if (next != null && next.text.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(next.text,
                textAlign: TextAlign.center,
                style: style.copyWith(
                    color: Colors.white60, fontSize: style.fontSize! * .72)),
          ],
        ]);
      },
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.bands) : super(repaint: bands);
  final ValueNotifier<List<double>> bands;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final count = bands.value.length * 2;
    final width = size.width / count;
    for (var i = 0; i < count; i++) {
      final band = i < bands.value.length ? i : count - i - 1;
      final height = math.max(1.0, bands.value[band] * size.height);
      final rect = Rect.fromLTWH(
          i * width + width * .22, size.height - height, width * .38, height);
      paint.shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x008d667f), Color(0xffb68ca8)]).createShader(rect);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1)), paint);
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) =>
      oldDelegate.bands != bands;
}
