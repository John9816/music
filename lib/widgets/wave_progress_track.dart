import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Paint-only variant of the shared seek control. Its phase never alters time.
class WaveProgressTrack extends StatefulWidget {
  const WaveProgressTrack(
      {super.key,
      required this.fraction,
      required this.buffered,
      required this.playing,
      required this.dragging,
      required this.activeColor,
      required this.trackColor,
      required this.height});

  final double fraction;
  final double buffered;
  final bool playing;
  final bool dragging;
  final Color activeColor;
  final Color trackColor;
  final double height;

  @override
  State<WaveProgressTrack> createState() => _WaveProgressTrackState();
}

class _WaveProgressTrackState extends State<WaveProgressTrack>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _phase = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200));
  bool _foreground = true;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(WaveProgressTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncAnimation();
  }

  void _syncAnimation() {
    final animate = widget.playing &&
        !widget.dragging &&
        !_reduceMotion &&
        _tickerEnabled &&
        _foreground;
    if (animate && !_phase.isAnimating) {
      _phase.repeat();
    } else if (!animate && _phase.isAnimating) {
      _phase.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _WavePainter(
            phase: _phase,
            fraction: widget.fraction,
            buffered: widget.buffered,
            waving: widget.playing && !_reduceMotion && !widget.dragging,
            dragging: widget.dragging,
            active: widget.activeColor,
            track: widget.trackColor,
          ),
        ),
      );
}

class _WavePainter extends CustomPainter {
  _WavePainter(
      {required this.phase,
      required this.fraction,
      required this.buffered,
      required this.waving,
      required this.dragging,
      required this.active,
      required this.track})
      : super(repaint: phase);
  final Animation<double> phase;
  final double fraction;
  final double buffered;
  final bool waving;
  final bool dragging;
  final Color active;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final y = size.height / 2;
    final end = size.width * fraction.clamp(0.0, 1.0);
    final radius = dragging ? 7.0 : 4.5;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = dragging ? 3.0 : 2.2;
    if (end + radius + 5 < size.width) {
      canvas.drawLine(Offset(end + radius + 5, y), Offset(size.width, y),
          stroke..color = track);
      final bufferEnd = size.width * buffered.clamp(0.0, 1.0);
      if (bufferEnd > end + radius + 5) {
        canvas.drawLine(Offset(end + radius + 5, y), Offset(bufferEnd, y),
            stroke..color = active.withValues(alpha: .15));
      }
    }
    final path = Path()..moveTo(0, y);
    for (double x = 0; x < end; x += 1.5) {
      final envelope = math.min(1.0, math.min(x, end - x) / 12);
      final offset = waving
          ? math.sin(x / 8 - phase.value * math.pi * 2) * 3 * envelope
          : 0.0;
      path.lineTo(x, y + offset);
    }
    path.lineTo(end, y);
    canvas.drawPath(path, stroke..color = active);
    canvas.drawCircle(
        Offset(end.clamp(radius, math.max(radius, size.width - radius)), y),
        radius,
        Paint()..color = active);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.fraction != fraction ||
      old.buffered != buffered ||
      old.waving != waving ||
      old.dragging != dragging ||
      old.active != active ||
      old.track != track;
}
