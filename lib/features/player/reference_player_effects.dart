import 'dart:ui';
import 'package:flutter/material.dart';
import '../../widgets/async_cover.dart';

/// A bounded artwork decode supplies the entire palette without per-frame work.
class ReferenceArtworkBackground extends StatelessWidget {
  const ReferenceArtworkBackground({super.key, required this.coverUrl});
  final String? coverUrl;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Color(0xff243746)),
          ClipRect(
              child: Transform.scale(
                  scale: 1.25,
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
