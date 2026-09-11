import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/network/image_request_policy.dart';
import '../core/theme/design_tokens.dart';
import '../core/theme/platform_motion.dart';
import '../core/utils/image_cache_manager.dart';

/// 网络封面图（带占位/错误态），对应 macOS 版 AsyncImageView。
/// size 支持有限数值；传入 infinite（如歌单卡片封面）时自动填满父级，
/// 避免 Icon 拿到 infinite fontSize 触发布局断言。
///
/// [heroTag] 用于「列表封面 → 迷你播放栏 → 全屏播放页」的共享元素转场。
/// **同一路由内 tag 必须唯一**：同一首歌可能同时出现在列表和迷你栏中，
/// 重复 tag 会直接抛异常。请用 [coverHeroTag] 生成带命名空间的 tag，
/// 并保证同屏只有一个位置使用某个 tag（通常让迷你栏让位给列表）。
class AsyncCover extends StatelessWidget {
  const AsyncCover({
    super.key,
    required this.url,
    this.size = 48,
    this.radius = 8,
    this.memCacheWidth,
    this.memCacheHeight,
    this.heroTag,
  });

  final String? url;
  final double size;
  final double radius;
  final int? memCacheWidth;
  final int? memCacheHeight;

  /// 非空时包一层 [Hero]。为空时行为与改造前完全一致。
  final Object? heroTag;

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
    // 尊重系统「减弱动态效果」：关闭动画时直接显示，不做淡入。
    final fadeIn = PlatformMotion.duration(context, Motion.fast);

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
        cacheManager: ImageCacheManager.instance,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: targetWidth,
        memCacheHeight: targetHeight,
        maxWidthDiskCache: 512,
        maxHeightDiskCache: 512,
        fadeInDuration: fadeIn,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      );
    } else {
      image = CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: requestHeaders,
        cacheManager: ImageCacheManager.instance,
        fit: BoxFit.cover,
        memCacheWidth: targetWidth,
        memCacheHeight: targetHeight,
        maxWidthDiskCache: 512,
        maxHeightDiskCache: 512,
        fadeInDuration: fadeIn,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      );
    }

    final Widget clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: finite ? image : SizedBox.expand(child: image),
    );

    final tag = heroTag;
    if (tag == null) return clipped;
    return Hero(
      tag: tag,
      // 默认 shuttle 会把源 widget 整个搬过去，起终点圆角不同时会看到
      // 圆角「跳变」。这里在飞行过程中对圆角做插值，过渡才连续。
      flightShuttleBuilder: (
        context,
        animation,
        direction,
        fromContext,
        toContext,
      ) {
        final fromCover = fromContext.widget as Hero;
        final toCover = toContext.widget as Hero;
        final fromRadius = _radiusOf(fromContext) ?? radius;
        final toRadius = _radiusOf(toContext) ?? radius;
        final child = direction == HeroFlightDirection.push
            ? toCover.child
            : fromCover.child;
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final t = direction == HeroFlightDirection.push
                ? animation.value
                : 1 - animation.value;
            return ClipRRect(
              borderRadius: BorderRadius.circular(
                lerpDouble(fromRadius, toRadius, t),
              ),
              child: child,
            );
          },
        );
      },
      child: clipped,
    );
  }

  static double? _radiusOf(BuildContext context) {
    final cover = context.findAncestorWidgetOfExactType<AsyncCover>();
    return cover?.radius;
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// 生成带命名空间的封面 Hero tag，避免不同列表间意外撞 tag。
///
/// [scope] 用于区分来源（如 `'queue'`、`'playlist:123'`），[id] 通常是歌曲 ID。
Object coverHeroTag(String scope, Object id) => 'cover:$scope:$id';
