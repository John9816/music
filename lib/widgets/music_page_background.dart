import 'package:flutter/material.dart';

/// Soft ambient color shared by the compact search and library screens.
class MusicPageBackground extends StatelessWidget {
  const MusicPageBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, .45, 1],
          colors: dark
              ? const [Color(0xFF253244), Color(0xFF1B1A28), Color(0xFF09090B)]
              : const [Color(0xFFEAF0F7), Color(0xFFF4F2F8), Color(0xFFF9F9FB)],
        ),
      ),
      child: child,
    );
  }
}
