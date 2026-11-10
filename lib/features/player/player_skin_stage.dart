import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/settings/player_appearance.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/async_cover.dart';
import 'folia_player_stage.dart';
import 'poster_lyric_stage.dart';

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
    return AnimatedScale(
        scale: playing || !enabled ? 1 : .82,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        child: ClipRRect(
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
                      ..rotateZ(.006 * math.sin(t)),
                    child: child))));
  }
}

class PlayerSkinStage extends StatelessWidget {
  const PlayerSkinStage(
      {super.key,
      required this.song,
      required this.skin,
      required this.lrc,
      required this.onLyrics,
      this.visible = true});
  final Song song;
  final PlayerSkin skin;
  final String lrc;
  final VoidCallback onLyrics;
  final bool visible;
  @override
  Widget build(BuildContext context) => skin == PlayerSkin.poster
      ? PosterLyricStage(song: song, lrc: lrc, onLyrics: onLyrics)
      : FoliaPlayerStage(
          key: ValueKey(skin),
          song: song,
          skin: skin,
          lrc: lrc,
          visible: visible,
          onLyrics: onLyrics);
}
