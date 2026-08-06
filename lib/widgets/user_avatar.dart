import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.radius,
    required this.name,
    required this.showInitial,
    this.imageUrl,
    this.backgroundColor,
    this.foregroundColor,
  });

  final double radius;
  final String name;
  final bool showInitial;
  final String? imageUrl;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = radius * 2;
    final fallback = ColoredBox(
      color: backgroundColor ?? scheme.surfaceContainerHighest,
      child: Center(
        child: showInitial && name.trim().isNotEmpty
            ? Text(
                name.trim().characters.first.toUpperCase(),
                style: TextStyle(
                  fontSize: radius * 0.78,
                  fontWeight: FontWeight.w800,
                  color: foregroundColor ?? scheme.onPrimaryContainer,
                ),
              )
            : Icon(
                Icons.person_rounded,
                size: radius * 0.88,
                color: foregroundColor ?? scheme.onSurfaceVariant,
              ),
      ),
    );
    final normalizedUrl = imageUrl?.trim();
    final image = normalizedUrl == null || normalizedUrl.isEmpty
        ? fallback
        : CachedNetworkImage(
            imageUrl: normalizedUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) => fallback,
            errorWidget: (_, __, ___) => fallback,
          );

    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: image,
      ),
    );
  }
}
