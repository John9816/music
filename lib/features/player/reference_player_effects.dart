import 'dart:ui';
import 'package:flutter/material.dart';
import '../../widgets/async_cover.dart';
import 'package:provider/provider.dart';
import '../../core/player/player_controller.dart';
import '../../core/settings/settings_controller.dart';
import 'player_skin_stage.dart';
import 'dart:math' as math;

/// A bounded artwork decode supplies the entire palette without per-frame work.
class ReferenceArtworkBackground extends StatelessWidget {
  const ReferenceArtworkBackground(
      {super.key, required this.coverUrl, this.poster = false});
  final String? coverUrl;
  final bool poster;
  @override
  Widget build(BuildContext context) {
    final active =
        context.select<PlayerController?, bool>((p) => p?.playing ?? false) &&
            context.select<SettingsController?, bool>(
                (s) => s?.fluidBackground ?? false);
    if (poster) {
      return RepaintBoundary(
          child: Stack(fit: StackFit.expand, children: [
        AsyncCover(
            url: coverUrl,
            size: double.infinity,
            radius: 0,
            memCacheWidth: 768,
            memCacheHeight: 1200),
        const ColoredBox(color: Color(0x79000000)),
        const DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
              Color(0x22000000),
              Color(0x00000000),
              Color(0xD9000000)
            ],
                    stops: [
              0,
              .55,
              1
            ]))),
      ]));
    }
    return RepaintBoundary(
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Color(0xff243746)),
        ClipRect(
            child: ArtworkMotion(
                enabled: active,
                builder: (context, phase, child) => Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..translateByDouble(
                          math.sin(phase) * 30, math.cos(phase) * 20, 0, 1)
                      ..rotateZ(.16 * math.sin(phase))
                      ..scaleByDouble(1.45, 1.45, 1, 1),
                    child: child),
                child: RepaintBoundary(
                    child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                  child: AsyncCover(
                      url: coverUrl,
                      size: double.infinity,
                      radius: 0,
                      memCacheWidth: 256,
                      memCacheHeight: 256),
                )))),
        // 主色渐变过渡（对标 TuneFreeNext 的 DynamicArtworkController）：
        // 从当前封面提取的主色随切歌平滑变化，让背景氛围与歌曲一致。
        const _ArtworkTintGradient(),
      ]),
    );
  }
}

/// 用封面主色绘制一层柔和渐变，切歌时平滑过渡。
/// 无可用主色时回退到中性色，视觉与改造前一致。
class _ArtworkTintGradient extends StatelessWidget {
  const _ArtworkTintGradient();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final crossfade = context.select<SettingsController, bool>(
        (s) => s.crossfadeArtwork);
    if (!crossfade) {
      return const DecoratedBox(
          decoration: BoxDecoration(
              gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x38202a40), Color(0x20000000), Color(0x99050a16)],
        stops: [0, .5, 1],
      )));
    }
    return ValueListenableBuilder<Color>(
      valueListenable: player.artworkColor,
      builder: (context, tint, _) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint.withValues(alpha: 0.34),
                const Color(0x20000000),
                Color.lerp(tint, const Color(0xff050a16), 0.8)!
                    .withValues(alpha: 0.55),
              ],
              stops: const [0, .5, 1],
            ),
          ),
        );
      },
    );
  }
}
