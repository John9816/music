import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Scroll content extends under the dock; only its trailing padding clears it.
class FloatingDockInsets extends InheritedWidget {
  const FloatingDockInsets(
      {super.key, required this.bottom, required super.child});
  final double bottom;
  static double bottomOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FloatingDockInsets>()
          ?.bottom ??
      0;
  @override
  bool updateShouldNotify(FloatingDockInsets oldWidget) =>
      bottom != oldWidget.bottom;
}

/// The navigation pill and playback pill share the same restrained glass rim.
class FloatingDockSurface extends StatelessWidget {
  const FloatingDockSurface({
    super.key,
    this.surfaceKey,
    required this.child,
  });

  final Key? surfaceKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    const radius = BorderRadius.all(Radius.circular(999));
    final opaque = highContrast;
    return Container(
      key: surfaceKey,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .24 : .11),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          enabled: !opaque,
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [
                        const Color(0xFF353A43)
                            .withValues(alpha: opaque ? 1 : .62),
                        const Color(0xFF1C1F27)
                            .withValues(alpha: opaque ? 1 : .48),
                      ]
                    : [
                        const Color(0xFFF8FBFD)
                            .withValues(alpha: opaque ? 1 : .62),
                        const Color(0xFFDDE4EB)
                            .withValues(alpha: opaque ? 1 : .54),
                      ],
              ),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: .22)
                    : const Color(0xFF81909D).withValues(alpha: .36),
                width: .8,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .12, .48, 1],
                  colors: [
                    Colors.white.withValues(alpha: dark ? .16 : .55),
                    Colors.white.withValues(alpha: .02),
                    Colors.transparent,
                    Colors.white.withValues(alpha: dark ? .03 : .14),
                  ],
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
