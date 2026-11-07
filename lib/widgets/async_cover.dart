import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/network/image_request_policy.dart';
import '../core/theme/design_tokens.dart';
import '../core/theme/platform_motion.dart';
import '../core/utils/image_cache_manager.dart';
import 'glass.dart' show GPressScale;

/// 网络封面图（带占位/错误态），对应 macOS 版 AsyncImageView。
/// size 支持有限数值；传入 infinite（如歌单卡片封面）时自动填满父级，
/// 避免 Icon 拿到 infinite fontSize 触发布局断言。
///
/// [heroTag] 用于「列表封面 → 迷你播放栏 → 全屏播放页」的共享元素转场。
/// **同一路由内 tag 必须唯一**：同一首歌可能同时出现在列表和迷你栏中，
/// 重复 tag 会直接抛异常。请用 [coverHeroTag] 生成带命名空间的 tag，
/// 并保证同屏只有一个位置使用某个 tag（通常让迷你栏让位给列表）。
class AsyncCover extends StatefulWidget {
  const AsyncCover({
    super.key,
    required this.url,
    this.size = 48,
    this.radius = 8,
    this.memCacheWidth,
    this.memCacheHeight,
    this.heroTag,
    this.placeholderAlignment = Alignment.center,
  });

  final String? url;
  final double size;
  final double radius;
  final int? memCacheWidth;
  final int? memCacheHeight;

  /// Positions missing/error artwork without changing the loaded image crop.
  final AlignmentGeometry placeholderAlignment;

  /// 非空时包一层 [Hero]。为空时行为与改造前完全一致。
  final Object? heroTag;

  @override
  State<AsyncCover> createState() => _AsyncCoverState();

  static double? _radiusOf(BuildContext context) {
    final cover = context.findAncestorWidgetOfExactType<AsyncCover>();
    return cover?.radius;
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

class _AsyncCoverState extends State<AsyncCover> {
  int _requestGeneration = 0;
  bool _retrying = false;

  @override
  void didUpdateWidget(AsyncCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (normalizeRemoteImageUrl(oldWidget.url) !=
        normalizeRemoteImageUrl(widget.url)) {
      _requestGeneration++;
      _retrying = false;
    }
  }

  Future<void> _retry(
    String imageUrl,
    int? targetWidth,
    int? targetHeight,
  ) async {
    if (_retrying) return;
    final generation = ++_requestGeneration;
    setState(() => _retrying = true);
    final cache = ImageCacheManager.instance;
    final provider = ResizeImage.resizeIfNeeded(
      targetWidth,
      targetHeight,
      CachedNetworkImageProvider(
        imageUrl,
        cacheManager: cache,
        headers: imageRequestHeaders(imageUrl),
        maxWidth: 512,
        maxHeight: 512,
      ),
    );
    try {
      await Future.wait([
        cache.removeFile(imageUrl),
        cache.removeFile('resized_w512_h512_$imageUrl'),
        provider.evict(),
      ]);
    } catch (_) {
      // A cache cleanup failure should still leave the cover retryable.
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _retrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = widget.size;
    final radius = widget.radius;
    final imageUrl = normalizeRemoteImageUrl(widget.url);
    final requestHeaders = imageRequestHeaders(imageUrl);
    final finite = size.isFinite && size > 0;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final targetWidth = widget.memCacheWidth ??
        (finite ? (size * pixelRatio).ceil().clamp(1, 1024).toInt() : null);
    final targetHeight = widget.memCacheHeight ??
        (finite ? (size * pixelRatio).ceil().clamp(1, 1024).toInt() : null);
    // 尊重系统「减弱动态效果」：关闭动画时直接显示，不做淡入。
    final fadeIn = PlatformMotion.duration(context, Motion.fast);

    Widget surface({IconData? icon}) => SizedBox(
          width: finite ? size : null,
          height: finite ? size : null,
          child: ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Align(
              alignment: widget.placeholderAlignment,
              child: icon == null
                  ? null
                  : Icon(
                      icon,
                      size: finite ? (size * .4).clamp(16.0, 40.0) : 32,
                      color: scheme.outline,
                    ),
            ),
          ),
        );
    final loading = Semantics(label: '封面加载中', child: surface());

    Widget failed() {
      void retry() => _retry(imageUrl!, targetWidth, targetHeight);
      return Tooltip(
        message: '重新加载封面',
        child: Semantics(
          label: '重新加载封面',
          button: true,
          onTap: retry,
          child: ExcludeSemantics(
            child: GPressScale(
              onTap: retry,
              child: surface(icon: Icons.refresh_rounded),
            ),
          ),
        ),
      );
    }

    final Widget image;
    if (imageUrl == null) {
      image = Semantics(
        label: '暂无封面',
        image: true,
        child: surface(icon: Icons.music_note),
      );
    } else if (_retrying) {
      image = loading;
    } else {
      image = CachedNetworkImage(
        key: ValueKey((imageUrl, _requestGeneration)),
        imageUrl: imageUrl,
        httpHeaders: requestHeaders,
        cacheManager: ImageCacheManager.instance,
        width: finite ? size : null,
        height: finite ? size : null,
        fit: BoxFit.cover,
        memCacheWidth: targetWidth,
        memCacheHeight: targetHeight,
        maxWidthDiskCache: 512,
        maxHeightDiskCache: 512,
        fadeInDuration: fadeIn,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => loading,
        errorWidget: (_, __, ___) => failed(),
      );
    }

    final Widget clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: finite ? image : SizedBox.expand(child: image),
    );

    final tag = widget.heroTag;
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
        final fromRadius = AsyncCover._radiusOf(fromContext) ?? radius;
        final toRadius = AsyncCover._radiusOf(toContext) ?? radius;
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
                AsyncCover.lerpDouble(fromRadius, toRadius, t),
              ),
              child: child,
            );
          },
        );
      },
      child: clipped,
    );
  }
}

/// 生成带命名空间的封面 Hero tag，避免不同列表间意外撞 tag。
///
/// [scope] 用于区分来源（如 `'queue'`、`'playlist:123'`），[id] 通常是歌曲 ID。
Object coverHeroTag(String scope, Object id) => 'cover:$scope:$id';
