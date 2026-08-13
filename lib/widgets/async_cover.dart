import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/network/image_request_policy.dart';

/// 网络封面图（带占位/错误态），对应 macOS 版 AsyncImageView。
/// size 支持有限数值；传入 infinite（如歌单卡片封面）时自动填满父级，
/// 避免 Icon 拿到 infinite fontSize 触发布局断言。
class AsyncCover extends StatelessWidget {
  const AsyncCover({
    super.key,
    required this.url,
    this.size = 48,
    this.radius = 8,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String? url;
  final double size;
  final double radius;
  final int? memCacheWidth;
  final int? memCacheHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final imageUrl = normalizeRemoteImageUrl(url);
    final requestHeaders = imageRequestHeaders(imageUrl);
    final finite = size.isFinite && size > 0;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final targetWidth = memCacheWidth ??
        (finite ? (size * pixelRatio).ceil().clamp(1, 1024).toInt() : null);
    final targetHeight = memCacheHeight ??
        (finite ? (size * pixelRatio).ceil().clamp(1, 1024).toInt() : null);

    final Widget placeholder;
    if (finite) {
      placeholder = Container(
        width: size,
        height: size,
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.music_note, size: size * 0.4, color: scheme.outline),
      );
    } else {
      // 无限尺寸：占满父级（如歌单卡片封面）
      placeholder = ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.music_note, size: 32, color: scheme.outline),
        ),
      );
    }

    final Widget image;
    if (imageUrl == null) {
      image = placeholder;
    } else if (finite) {
      image = CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: requestHeaders,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: targetWidth,
        memCacheHeight: targetHeight,
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      );
    } else {
      image = CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: requestHeaders,
        fit: BoxFit.cover,
        memCacheWidth: targetWidth,
        memCacheHeight: targetHeight,
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: finite ? image : SizedBox.expand(child: image),
    );
  }
}
