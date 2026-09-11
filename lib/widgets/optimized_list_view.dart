import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

/// 优化的列表视图，提供更好的滚动性能
///
/// 核心优化：
/// - RepaintBoundary 隔离重绘
/// - 合理的 cacheExtent 减少卡顿
/// - 支持分隔符
class OptimizedListView<T> extends StatelessWidget {
  const OptimizedListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.padding,
    this.separatorBuilder,
    this.physics,
    this.cacheExtent = 500.0,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final EdgeInsetsGeometry? padding;
  final Widget Function(BuildContext context, int index)? separatorBuilder;
  final ScrollPhysics? physics;
  final double cacheExtent;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    if (separatorBuilder != null) {
      return ListView.separated(
        padding: padding,
        physics: physics,
        itemCount: items.length,
        scrollCacheExtent: ScrollCacheExtent.pixels(cacheExtent),
        itemBuilder: (context, index) {
          return RepaintBoundary(
            child: itemBuilder(context, items[index], index),
          );
        },
        separatorBuilder: separatorBuilder!,
      );
    }

    return ListView.builder(
      padding: padding,
      physics: physics,
      itemCount: items.length,
      scrollCacheExtent: ScrollCacheExtent.pixels(cacheExtent),
      itemBuilder: (context, index) {
        return RepaintBoundary(
          child: itemBuilder(context, items[index], index),
        );
      },
    );
  }
}
