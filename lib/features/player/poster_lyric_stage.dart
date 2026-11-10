import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/song.dart';
import '../../core/player/lrc_parser.dart';
import '../../core/player/player_controller.dart';
import '../../core/settings/settings_controller.dart';
import 'karaoke_lyric_text.dart';

/// Poster layout measured from the installed reference, not its preview art.
class PosterLyricStage extends StatefulWidget {
  const PosterLyricStage(
      {super.key,
      required this.song,
      required this.lrc,
      required this.onLyrics});
  final Song song;
  final String lrc;
  final VoidCallback onLyrics;
  @override
  State<PosterLyricStage> createState() => _PosterLyricStageState();
}

class _PosterLyricStageState extends State<PosterLyricStage> {
  late List<LrcLine> _lines = parseLrc(widget.lrc);
  @override
  void didUpdateWidget(covariant PosterLyricStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lrc != widget.lrc) _lines = parseLrc(widget.lrc);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final scale =
        context.select<SettingsController, int>((s) => s.lyricFontSize) / 30;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: '大字海报播放画面，打开歌词',
      child: GestureDetector(
          onTap: widget.onLyrics,
          behavior: HitTestBehavior.opaque,
          child: StreamBuilder<Duration>(
              stream: player.positionStream,
              initialData: player.position,
              builder: (context, snapshot) {
                final time = snapshot.data ?? player.position;
                var index = -1;
                for (var i = 0;
                    i < _lines.length && _lines[i].time <= time;
                    i++) {
                  index = i;
                }
                final line = index < 0 ? null : _lines[index];
                final text = line == null || line.text.trim().isEmpty
                    ? widget.song.name
                    : line.text;
                return LayoutBuilder(builder: (context, size) {
                  final width = math.max(1.0, size.maxWidth - 44);
                  final style = TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: (size.maxWidth * .19 * scale).clamp(32.0, 88.0),
                      letterSpacing: -1.4,
                      height: 1.06);
                  return Stack(children: [
                    Positioned(
                        top: 10,
                        left: 24,
                        child: Text(
                            '${math.max(0, index + 1)}  /  ${_lines.length}',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                letterSpacing: 1.6))),
                    Positioned(
                        top: 12,
                        right: 10,
                        bottom: 20,
                        child: Align(
                            alignment: Alignment.topRight,
                            child: RotatedBox(
                                quarterTurns: 1,
                                child: Text(
                                    '${widget.song.name} — ${widget.song.artistNames}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600))))),
                    Positioned.fill(
                        top: 55,
                        bottom: 28,
                        left: 22,
                        right: 22,
                        child: Align(
                            alignment: const Alignment(-1, -.1),
                            child: AnimatedSwitcher(
                                duration: reduced
                                    ? Duration.zero
                                    : const Duration(milliseconds: 360),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                            position: Tween<Offset>(
                                                    begin: const Offset(0, .08),
                                                    end: Offset.zero)
                                                .animate(animation),
                                            child: child)),
                                child: FittedBox(
                                    key: ValueKey((widget.song.id, index)),
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: SizedBox(
                                        width: width,
                                        child: CustomPaint(
                                            painter: _MarkerPainter(
                                                text, style, width, MediaQuery.textScalerOf(context)),
                                            child: line != null && line.words.isNotEmpty ? KaraokeLyricText(line: line, style: style, position: time, positionStream: player.positionStream, playing: playing, textAlign: TextAlign.left) : Text(text, style: style))))))),
                  ]);
                });
              })),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.text, this.style, this.width, this.textScaler);
  final TextScaler textScaler;
  final String text;
  final TextStyle style;
  final double width;
  @override
  void paint(Canvas canvas, Size size) {
    final paragraph = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler)
      ..layout(maxWidth: width);
    final paint = Paint()..color = const Color(0xC9C58D57);
    for (final line in paragraph.computeLineMetrics()) {
      canvas.drawRect(
          Rect.fromLTWH(line.left - 4, line.baseline - line.ascent * .20,
              line.width + 8, line.ascent * .43),
          paint);
    }
    paragraph.dispose();
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter old) =>
      old.text != text ||
      old.style != style ||
      old.width != width ||
      old.textScaler != textScaler;
}
