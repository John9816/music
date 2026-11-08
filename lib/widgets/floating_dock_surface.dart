import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings/settings_controller.dart';

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
    var smooth = false;
    try {
      smooth = context.select<SettingsController, bool>(
        (settings) => settings.glassQuality == 'smooth',
      );
    } on ProviderNotFoundException {
      // The same surface is also used in isolated player previews.
    }
    const radius = BorderRadius.all(Radius.circular(999));
    final opaque = highContrast || smooth;
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
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [
                        const Color(0xFF353A43)
                            .withValues(alpha: opaque ? 1 : .90),
                        const Color(0xFF1C1F27)
                            .withValues(alpha: opaque ? 1 : .84),
                      ]
                    : [
                        const Color(0xFFF8FBFD)
                            .withValues(alpha: opaque ? 1 : .90),
                        const Color(0xFFDDE4EB)
                            .withValues(alpha: opaque ? 1 : .86),
                      ],
              ),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: .22)
                    : const Color(0xFF81909D).withValues(alpha: .36),
                width: .8,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
