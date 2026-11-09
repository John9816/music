import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/song.dart';
import '../../core/player/lrc_parser.dart';
import '../../core/player/player_controller.dart';
import '../../core/settings/player_appearance.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/async_cover.dart';
import 'karaoke_lyric_text.dart';

Future<void> showPlayerSkins(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('播放页皮肤',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('换背景、封面舞台与歌词的呈现方式'),
                  const SizedBox(height: 20),
                  for (final skin in PlayerSkin.values)
                    Consumer<SettingsController>(
                        builder: (context, settings, _) => ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                          colors: _skinColors(skin))),
                                  child: Icon(_skinIcon(skin),
                                      color: Colors.white)),
                              title: Text(skin.label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(skin.description),
                              trailing: settings.playerSkin == skin
                                  ? const Icon(Icons.check_circle,
                                      color: Color(0xFFFF2D55))
                                  : null,
                              onTap: () {
                                settings.setPlayerSkin(skin);
                                Navigator.pop(context);
                              },
                            )),
                  const SizedBox(height: 12),
                  const Text('动态效果会增加耗电。选择保存在这台设备上。',
                      style: TextStyle(fontSize: 12)),
                ]),
          )),
    );
List<Color> _skinColors(PlayerSkin s) => switch (s) {
      PlayerSkin.classic => [const Color(0xff5d6979), const Color(0xff26354c)],
      PlayerSkin.poster => [const Color(0xff3c8ddb), const Color(0xff122c57)],
      PlayerSkin.mist => [const Color(0xff8f9992), const Color(0xff313d41)],
      PlayerSkin.light => [const Color(0xffaf89d5), const Color(0xff242345)],
      PlayerSkin.fireworks => [
          const Color(0xffdb976a),
          const Color(0xff33243f)
        ],
    };
IconData _skinIcon(PlayerSkin s) => switch (s) {
      PlayerSkin.classic => Icons.album_outlined,
      PlayerSkin.poster => Icons.text_fields,
      PlayerSkin.mist => Icons.cloud_outlined,
      PlayerSkin.light => Icons.blur_on,
      PlayerSkin.fireworks => Icons.auto_awesome_outlined,
    };

/// Shares one slow clock per effect and stops it whenever it cannot be seen.
class ArtworkMotion extends StatefulWidget {
  const ArtworkMotion(
      {super.key, required this.enabled, required this.builder, this.child});
  final bool enabled;
  final Widget Function(BuildContext, double, Widget?) builder;
  final Widget? child;
  @override
  State<ArtworkMotion> createState() => _ArtworkMotionState();
}

class _ArtworkMotionState extends State<ArtworkMotion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 24));
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ArtworkMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final active = widget.enabled &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (active && !_clock.isAnimating) {
      _clock.repeat();
    }
    if (!active && _clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _clock,
      child: widget.child,
      builder: (context, child) =>
          widget.builder(context, _clock.value * math.pi * 2, child));
}

class AnimatedSongArtwork extends StatelessWidget {
  const AnimatedSongArtwork(
      {super.key, required this.song, required this.size});
  final Song song;
  final double size;
  @override
  Widget build(BuildContext context) {
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final enabled =
        context.select<SettingsController, bool>((s) => s.animatedArtwork);
    return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ArtworkMotion(
            enabled: enabled && playing,
            child: AsyncCover(
                key: const ValueKey('mobile-player-artwork'),
                url: song.album.picUrl,
                size: size,
                radius: 0),
            builder: (context, t, child) => Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scaleByDouble(1.035 + .015 * math.sin(t),
                      1.035 + .015 * math.sin(t), 1, 1)
                  ..rotateZ(.012 * math.sin(t)),
                child: child)));
  }
}

class PlayerSkinStage extends StatefulWidget {
  const PlayerSkinStage(
      {super.key,
      required this.song,
      required this.skin,
      required this.lrc,
      required this.onLyrics});
  final Song song;
  final PlayerSkin skin;
  final String lrc;
  final VoidCallback onLyrics;
  @override
  State<PlayerSkinStage> createState() => _PlayerSkinStageState();
}

class _PlayerSkinStageState extends State<PlayerSkinStage> {
  late List<LrcLine> _lines;
  @override
  void initState() {
    super.initState();
    _lines = parseLrc(widget.lrc);
  }

  @override
  void didUpdateWidget(covariant PlayerSkinStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lrc != widget.lrc) _lines = parseLrc(widget.lrc);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final fontSize =
        context.select<SettingsController, int>((s) => s.lyricFontSize);
    return RepaintBoundary(
        child: Stack(fit: StackFit.expand, children: [
      IgnorePointer(
          child: ArtworkMotion(
              enabled: playing,
              builder: (context, phase, _) =>
                  CustomPaint(painter: _SkinPainter(widget.skin, phase)))),
      StreamBuilder<Duration>(
          stream: player.positionStream,
          initialData: player.position,
          builder: (context, snapshot) {
            final time = snapshot.data ?? Duration.zero;
            var index = -1;
            for (var i = 0; i < _lines.length && _lines[i].time <= time; i++) {
              index = i;
            }
            final line = index < 0 ? null : _lines[index];
            final text = line?.text.trim();
            final current =
                text == null || text.isEmpty ? widget.song.name : text;
            final next = index + 1 < _lines.length
                ? _lines[index + 1].text
                : widget.song.artistNames;
            final poster = widget.skin == PlayerSkin.poster;
            final style = TextStyle(
                color: Colors.white,
                height: 1.24,
                fontSize: (poster ? 48.0 : 32.0) * fontSize / 30,
                fontWeight: poster ? FontWeight.w900 : FontWeight.w600,
                fontFamily: widget.skin == PlayerSkin.mist ? 'serif' : null,
                letterSpacing: poster ? -1.8 : 1,
                shadows: const [
                  Shadow(color: Color(0x99000000), blurRadius: 12)
                ]);
            return Semantics(
                button: true,
                label: '打开完整歌词',
                child: GestureDetector(
                    onTap: widget.onLyrics,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 18, 28, 22),
                        child: Column(
                            crossAxisAlignment: poster
                                ? CrossAxisAlignment.start
                                : CrossAxisAlignment.center,
                            children: [
                              Row(children: [
                                Text(
                                    index >= 0
                                        ? '${(index + 1).toString().padLeft(2, '0')} / ${_lines.length}'
                                        : widget.skin.label,
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        letterSpacing: 2)),
                                const Spacer(),
                                AsyncCover(
                                    url: widget.song.album.picUrl,
                                    size: 34,
                                    radius: 7),
                              ]),
                              Expanded(
                                  child: Center(
                                      child: AnimatedSwitcher(
                                          duration: MediaQuery.disableAnimationsOf(context)
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 380),
                                          child: SizedBox(
                                              key: ValueKey(
                                                  (widget.song.id, index)),
                                              width: double.infinity,
                                              child: LayoutBuilder(
                                                  builder: (context, c) => FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment: poster
                                                          ? Alignment.centerLeft
                                                          : Alignment.center,
                                                      child: Container(
                                                          width: c.maxWidth,
                                                          padding: poster
                                                              ? const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 5)
                                                              : EdgeInsets.zero,
                                                          decoration: poster
                                                              ? BoxDecoration(color: const Color(0xbb286dd5), borderRadius: BorderRadius.circular(3))
                                                              : null,
                                                          child: line != null && line.words.isNotEmpty ? KaraokeLyricText(line: line, style: style, position: time, positionStream: player.positionStream, playing: playing, textAlign: poster ? TextAlign.left : TextAlign.center) : Text(current, style: style, textAlign: poster ? TextAlign.left : TextAlign.center)))))))),
                              Text(next,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: poster
                                      ? TextAlign.left
                                      : TextAlign.center,
                                  style: const TextStyle(
                                      color: Color(0xffe2e6ed),
                                      fontSize: 17,
                                      height: 1.4)),
                            ]))));
          }),
    ]));
  }
}

class _SkinPainter extends CustomPainter {
  _SkinPainter(this.skin, this.phase);
  final PlayerSkin skin;
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    if (skin == PlayerSkin.fireworks) {
      for (var i = 0; i < 28; i++) {
        final seed = i * 2.39996;
        final progress = (phase / (2 * math.pi) + i / 28) % 1;
        final center = Offset(size.width * (.5 + .48 * math.sin(seed)),
            size.height * (1 - progress));
        canvas.drawCircle(
            center,
            1.5 + 2 * math.sin(seed).abs(),
            Paint()
              ..color = Color.lerp(
                      const Color(0xffffb678), const Color(0xffced9ff), i / 28)!
                  .withValues(alpha: .4 * math.sin(progress * math.pi)));
      }
    } else if (skin == PlayerSkin.light) {
      final paint = Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: .12);
      for (var i = 0; i < 9; i++) {
        final x = size.width * i / 7 + 30 * math.sin(phase + i);
        canvas.drawLine(
            Offset(x, 0), Offset(x - size.width * .6, size.height), paint);
      }
      final rect = Offset.zero & size;
      canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
                    center:
                        Alignment(math.sin(phase) * .8, math.cos(phase) * .4),
                    colors: const [Color(0x44768ceb), Color(0x005f88ff)],
                    radius: .9)
                .createShader(rect));
    } else if (skin == PlayerSkin.mist) {
      final rect = Offset.zero & size;
      canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
                    center:
                        Alignment(math.sin(phase) * .5, math.cos(phase) * .5),
                    colors: const [Color(0x448fa7a0), Color(0x00253338)],
                    radius: 1.1)
                .createShader(rect));
    }
  }

  @override
  bool shouldRepaint(covariant _SkinPainter old) =>
      old.phase != phase || old.skin != skin;
}
