import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/player/lrc_parser.dart';

/// Only the active row repaints with playback. The text layout and semantics
/// stay unchanged as the highlight crosses words, line breaks and seeks.
class KaraokeLyricText extends StatefulWidget {
  const KaraokeLyricText({
    super.key,
    required this.line,
    required this.style,
    required this.position,
    required this.positionStream,
    required this.playing,
    this.textAlign = TextAlign.left,
  });

  final LrcLine line;
  final TextStyle style;
  final Duration position;
  final Stream<Duration> positionStream;
  final bool playing;
  final TextAlign textAlign;

  @override
  State<KaraokeLyricText> createState() => _KaraokeLyricTextState();
}

class _KaraokeLyricTextState extends State<KaraokeLyricText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _transition;
  late final ValueNotifier<Duration> _position;
  StreamSubscription<Duration>? _subscription;
  double _from = 0;
  double _to = 0;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _position = ValueNotifier(widget.position);
    _transition = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80))
      ..addListener(() {
        _position.value = Duration(
            microseconds: (_from + (_to - _from) * _transition.value).round());
      });
    _subscription = widget.positionStream.listen(_onPosition);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion && _transition.isAnimating) {
      _transition.stop();
      _position.value = Duration(microseconds: _to.round());
    }
  }

  @override
  void didUpdateWidget(covariant KaraokeLyricText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionStream != widget.positionStream) {
      _subscription?.cancel();
      _subscription = widget.positionStream.listen(_onPosition);
    }
    if (oldWidget.line != widget.line ||
        oldWidget.playing != widget.playing ||
        oldWidget.position != widget.position) {
      _transition.stop();
      _position.value = widget.position;
    }
  }

  void _onPosition(Duration value) {
    final delta = value - _position.value;
    _transition.stop();
    // Interpolate only small forward clock updates. Seeks, pauses and reduced
    // motion resolve immediately and never extrapolate past native playback.
    if (widget.playing &&
        !_reduceMotion &&
        delta > Duration.zero &&
        delta <= const Duration(milliseconds: 250)) {
      _from = _position.value.inMicroseconds.toDouble();
      _to = value.inMicroseconds.toDouble();
      _transition.forward(from: 0);
    } else {
      _position.value = value;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _transition.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: _KaraokeHighlightPainter(
          textAlign: widget.textAlign,
          line: widget.line,
          style: widget.style,
          position: _position,
          direction: Directionality.of(context),
          scaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        ),
        child: SizedBox(
          width: double.infinity,
          child: Text(widget.line.text,
              textAlign: widget.textAlign,
              style: widget.style.copyWith(
                  color: widget.style.color!.withValues(alpha: 0.38))),
        ),
      ),
    );
  }
}

class _KaraokeHighlightPainter extends CustomPainter {
  _KaraokeHighlightPainter({
    required this.line,
    required this.style,
    required this.position,
    required this.textAlign,
    required this.direction,
    required this.scaler,
    required this.locale,
  }) : super(repaint: position);

  final LrcLine line;
  final TextStyle style;
  final ValueNotifier<Duration> position;
  final TextAlign textAlign;
  final TextDirection direction;
  final TextScaler scaler;
  final Locale? locale;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(text: line.text, style: style),
      textAlign: textAlign,
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
    )..layout(minWidth: size.width, maxWidth: size.width);
    final clip = Path();
    var offset = 0;
    for (final word in line.words) {
      final end = offset + word.text.length;
      final progress = word.progressAt(position.value);
      if (progress > 0 && end > offset) {
        final boxes = painter.getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: end));
        var remaining =
            boxes.fold<double>(0, (sum, box) => sum + box.right - box.left) *
                progress;
        for (final box in boxes) {
          final width = math.min(remaining, box.right - box.left);
          if (width <= 0) break;
          final left =
              box.direction == TextDirection.rtl ? box.right - width : box.left;
          clip.addRect(
              Rect.fromLTWH(left, box.top, width, box.bottom - box.top));
          remaining -= width;
        }
      }
      offset = end;
    }
    canvas.save();
    canvas.clipPath(clip);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _KaraokeHighlightPainter oldDelegate) =>
      textAlign != oldDelegate.textAlign ||
      line != oldDelegate.line ||
      style != oldDelegate.style ||
      position != oldDelegate.position ||
      direction != oldDelegate.direction ||
      scaler != oldDelegate.scaler ||
      locale != oldDelegate.locale;
}
