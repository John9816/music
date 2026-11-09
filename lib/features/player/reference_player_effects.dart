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
  const ReferenceArtworkBackground({super.key, required this.coverUrl});
  final String? coverUrl;
  @override
  Widget build(BuildContext context) {
    final active =
        context.select<PlayerController?, bool>((p) => p?.playing ?? false) &&
            context.select<SettingsController?, bool>(
                (s) => s?.fluidBackground ?? false);
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
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                  child: AsyncCover(
                      url: coverUrl,
                      size: double.infinity,
                      radius: 0,
                      memCacheWidth: 256,
                      memCacheHeight: 256),
                ))),
        const DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x38202a40), Color(0x20000000), Color(0x99050a16)],
          stops: [0, .5, 1],
        ))),
      ]),
    );
  }
}
