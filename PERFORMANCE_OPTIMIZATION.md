# DuckMusic 性能与交互优化方案

## 📊 当前状态分析

### 已有的优化
✅ 使用 `cached_network_image` 缓存封面图
✅ 实现了 Hero 动画过渡
✅ 使用 `const` 构造函数（部分）
✅ Provider 状态管理
✅ 页面缓存机制 (`_pageCache`)

### 待优化项

## 🎯 优化方案

### 1. 列表性能优化（高优先级）

#### 问题
- `SongRow` 每次都重建整个 widget
- 封面图可能触发不必要的网络请求
- 列表滚动时可能卡顿

#### 解决方案

```dart
// lib/widgets/song_row.dart 优化版本
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.song,
    this.onTap,
    this.trailing,
    this.leading,
  });

  final Song song;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 只监听这首歌的播放状态，而不是整个 player
    final isPlaying = context.select<PlayerController, bool>(
      (p) => p.current?.id == song.id && p.current?.source == song.source,
    );

    return RepaintBoundary(  // 🔥 隔离重绘边界
      child: GListTile(
        onTap: onTap,
        leading: leading ?? _CoverWithIndicator(song: song, isPlaying: isPlaying),
        title: _SongTitle(song: song, isPlaying: isPlaying, scheme: scheme),
        subtitle: ArtistNamesLink(
          artists: song.artists,
          source: song.source,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: TypeScale.small),
        ),
        trailing: trailing ?? _SongTrailing(song: song, onTap: onTap),
      ),
    );
  }
}

// 封面组件独立出来，避免不必要的重建
class _CoverWithIndicator extends StatelessWidget {
  const _CoverWithIndicator({
    required this.song,
    required this.isPlaying,
  });

  final Song song;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AsyncCover(
            url: song.album.picUrl, 
            size: 48, 
            radius: 10,
            // 🔥 启用内存缓存优化
            memCacheWidth: 96,
            memCacheHeight: 96,
          ),
        ),
        if (isPlaying)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.black.withValues(alpha: 0.6),
              ),
              child: Icon(
                Icons.graphic_eq_rounded,
                color: scheme.primary,
                size: 24,
              ),
            ),
          ),
      ],
    );
  }
}

class _SongTitle extends StatelessWidget {
  const _SongTitle({
    required this.song,
    required this.isPlaying,
    required this.scheme,
  });

  final Song song;
  final bool isPlaying;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Text(
      song.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: TypeScale.bodyLarge,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: isPlaying ? scheme.primary : null,
      ),
    );
  }
}

class _SongTrailing extends StatelessWidget {
  const _SongTrailing({
    required this.song,
    required this.onTap,
  });

  final Song song;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (song.durationMs > 0)
          Text(
            _formatDuration(song.durationMs),
            style: TextStyle(
              fontSize: TypeScale.caption,
              color: scheme.outline,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        SongActionButton(song: song, onPlay: onTap),
      ],
    );
  }
  
  String _formatDuration(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
```

### 2. 图片加载优化（高优先级）

#### 问题
- 大图加载可能阻塞 UI
- 内存占用过高
- 网络请求未充分优化

#### 解决方案

```dart
// lib/core/utils/image_cache_manager.dart（新文件）
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 自定义图片缓存管理器
class ImageCacheManager {
  static const key = 'duckMusicImageCache';
  
  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 200,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );
  
  /// 预加载封面图
  static Future<void> preloadCovers(List<String> urls) async {
    for (final url in urls.take(10)) {  // 只预加载前 10 个
      if (url.isEmpty) continue;
      await instance.downloadFile(url);
    }
  }
  
  /// 清理过期缓存
  static Future<void> cleanCache() async {
    await instance.emptyCache();
  }
}
```

```dart
// 在 AsyncCover 中使用自定义缓存管理器
class AsyncCover extends StatelessWidget {
  // ... existing code ...
  
  @override
  Widget build(BuildContext context) {
    // ... existing code ...
    
    image = CachedNetworkImage(
      imageUrl: imageUrl,
      httpHeaders: requestHeaders,
      cacheManager: ImageCacheManager.instance,  // 🔥 使用自定义缓存
      width: size,
      height: size,
      fit: BoxFit.cover,
      memCacheWidth: targetWidth,
      memCacheHeight: targetHeight,
      fadeInDuration: fadeIn,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => placeholder,
      maxWidthDiskCache: 512,  // 🔥 限制磁盘缓存大小
      maxHeightDiskCache: 512,
    );
    
    // ... rest of code ...
  }
}
```

### 3. 动画性能优化（中优先级）

#### 问题
- 页面切换可能有卡顿
- 动画曲线不够流畅
- 过度动画影响性能

#### 解决方案

```dart
// lib/core/theme/app_animations.dart（新文件）
import 'package:flutter/animation.dart';

class AppAnimations {
  // 使用 FastOutSlowIn 替代 easeOutCubic，更自然
  static const Curve pageTransition = Curves.fastOutSlowIn;
  
  // 列表项动画
  static const Curve listItem = Curves.easeOut;
  
  // 播放器动画
  static const Curve player = Curves.easeInOutCubic;
  
  // 持续时间
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 400);
  
  // 🔥 自适应动画：根据设备性能调整
  static Duration adaptive(Duration base, {bool reducedMotion = false}) {
    if (reducedMotion) return Duration.zero;
    // 可以根据设备性能进一步调整
    return base;
  }
}
```

```dart
// 在 player_view.dart 中使用
Route<void> buildPlayerRoute({required bool reducedMotion}) {
  return PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: AppAnimations.adaptive(
      AppAnimations.slow,
      reducedMotion: reducedMotion,
    ),
    reverseTransitionDuration: AppAnimations.adaptive(
      AppAnimations.slow,
      reducedMotion: reducedMotion,
    ),
    pageBuilder: (context, animation, secondaryAnimation) => const PlayerView(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppAnimations.pageTransition,  // 🔥 使用统一曲线
        reverseCurve: AppAnimations.pageTransition,
      );
      // ... rest of code ...
    },
  );
}
```

### 4. 列表滚动优化（高优先级）

#### 问题
- 长列表滚动可能卡顿
- 没有使用虚拟滚动
- item 构建开销大

#### 解决方案

```dart
// lib/widgets/optimized_list_view.dart（新文件）
import 'package:flutter/material.dart';

/// 优化的列表视图
class OptimizedListView<T> extends StatelessWidget {
  const OptimizedListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.padding,
    this.separatorBuilder,
    this.physics,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final EdgeInsetsGeometry? padding;
  final Widget Function(BuildContext context, int index)? separatorBuilder;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    if (separatorBuilder != null) {
      return ListView.separated(
        padding: padding,
        physics: physics,
        itemCount: items.length,
        // 🔥 关键优化：设置合理的 cacheExtent
        cacheExtent: 500,  // 缓存屏幕外 500 像素
        itemBuilder: (context, index) {
          return RepaintBoundary(  // 🔥 每个 item 独立重绘
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
      cacheExtent: 500,
      itemBuilder: (context, index) {
        return RepaintBoundary(
          child: itemBuilder(context, items[index], index),
        );
      },
    );
  }
}

/// 使用示例
// OptimizedListView<Song>(
//   items: songs,
//   itemBuilder: (context, song, index) => SongRow(
//     song: song,
//     onTap: () => player.playFromList(songs, index),
//   ),
// );
```

### 5. 状态管理优化（中优先级）

#### 问题
- 过度使用 `context.watch` 导致不必要的重建
- Provider 粒度不够细

#### 解决方案

```dart
// 使用 Selector 替代 watch，减少重建
class PlayerControlBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // ❌ 不好：整个 PlayerController 变化都会重建
    // final player = context.watch<PlayerController>();
    
    // ✅ 好：只监听需要的字段
    final isPlaying = context.select<PlayerController, bool>(
      (player) => player.isPlaying,
    );
    final position = context.select<PlayerController, Duration>(
      (player) => player.position,
    );
    final duration = context.select<PlayerController, Duration>(
      (player) => player.duration,
    );
    
    return Column(
      children: [
        Slider(
          value: position.inSeconds.toDouble(),
          max: duration.inSeconds.toDouble(),
          onChanged: (value) {
            context.read<PlayerController>().seek(
              Duration(seconds: value.toInt()),
            );
          },
        ),
        IconButton(
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: () {
            context.read<PlayerController>().playPause();
          },
        ),
      ],
    );
  }
}
```

### 6. 交互响应优化（高优先级）

#### 问题
- 点击反馈不够明显
- 缺少触觉反馈
- 手势识别不够灵敏

#### 解决方案

```dart
// lib/widgets/responsive_button.dart（新文件）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 响应式按钮，带触觉反馈和缩放动画
class ResponsiveButton extends StatefulWidget {
  const ResponsiveButton({
    super.key,
    required this.child,
    required this.onTap,
    this.enableHaptic = true,
    this.scaleDown = 0.95,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool enableHaptic;
  final double scaleDown;

  @override
  State<ResponsiveButton> createState() => _ResponsiveButtonState();
}

class _ResponsiveButtonState extends State<ResponsiveButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleDown,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
    if (widget.enableHaptic) {
      HapticFeedback.lightImpact();  // 🔥 触觉反馈
    }
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
```

```dart
// 在 SongRow 中使用
class SongRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ResponsiveButton(  // 🔥 替换 GestureDetector
      onTap: onTap ?? () {},
      child: GListTile(
        // ... existing code ...
      ),
    );
  }
}
```

### 7. 代码层面优化（低优先级但重要）

#### const 构造函数优化

```bash
# 批量添加 const 关键字（需要手动确认）
find lib -name "*.dart" -exec sed -i '' 's/SizedBox(/const SizedBox(/g' {} \;
find lib -name "*.dart" -exec sed -i '' 's/EdgeInsets\./const EdgeInsets\./g' {} \;
find lib -name "*.dart" -exec sed -i '' 's/Duration(/const Duration(/g' {} \;
```

#### 避免在 build 中创建对象

```dart
// ❌ 不好：每次 build 都创建新对象
Widget build(BuildContext context) {
  final decoration = BoxDecoration(
    borderRadius: BorderRadius.circular(10),
  );
  return Container(decoration: decoration);
}

// ✅ 好：使用 const 或提取到字段
class _MyWidgetState extends State<MyWidget> {
  static const _decoration = BoxDecoration(
    borderRadius: BorderRadius.all(Radius.circular(10)),
  );
  
  Widget build(BuildContext context) {
    return Container(decoration: _decoration);
  }
}
```

### 8. 性能监控（推荐）

```dart
// lib/core/utils/performance_monitor.dart（新文件）
import 'package:flutter/scheduler.dart';
import 'dart:developer' as developer;

class PerformanceMonitor {
  static bool _enabled = false;
  static final List<Duration> _frameTimes = [];
  
  static void enable() {
    _enabled = true;
    SchedulerBinding.instance.addTimingsCallback(_onFrame);
  }
  
  static void disable() {
    _enabled = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrame);
  }
  
  static void _onFrame(List<FrameTiming> timings) {
    if (!_enabled) return;
    
    for (final timing in timings) {
      final frameTime = timing.totalSpan;
      _frameTimes.add(frameTime);
      
      // 检测掉帧（>16.67ms = 60fps）
      if (frameTime.inMicroseconds > 16670) {
        developer.log(
          'Frame dropped: ${frameTime.inMilliseconds}ms',
          name: 'Performance',
        );
      }
    }
    
    // 保持最近 100 帧
    if (_frameTimes.length > 100) {
      _frameTimes.removeAt(0);
    }
  }
  
  static double get averageFps {
    if (_frameTimes.isEmpty) return 0;
    final avgMicros = _frameTimes
        .map((d) => d.inMicroseconds)
        .reduce((a, b) => a + b) / _frameTimes.length;
    return 1000000 / avgMicros;
  }
}

// 在 main.dart 中启用（仅调试模式）
void main() {
  if (kDebugMode) {
    PerformanceMonitor.enable();
  }
  runApp(MyApp());
}
```

## 📈 性能指标目标

### 启动时间
- 冷启动：< 2 秒
- 热启动：< 0.5 秒

### 帧率
- 列表滚动：保持 60 FPS
- 动画：保持 60 FPS
- 页面切换：保持 60 FPS

### 内存
- 空闲状态：< 150 MB
- 播放音乐：< 200 MB
- 滚动长列表：< 250 MB

### 网络
- 封面图缓存命中率：> 80%
- 预加载数量：10 个封面
- 超时时间：< 5 秒

## 🛠️ 实施步骤

### 第一阶段（立即可做）
1. ✅ 为所有静态 widget 添加 `const`
2. ✅ 在列表 item 上添加 `RepaintBoundary`
3. ✅ 优化 `context.select` 使用
4. ✅ 为图片添加内存缓存参数

### 第二阶段（需要测试）
1. 实现自定义图片缓存管理器
2. 添加响应式按钮和触觉反馈
3. 实现优化的列表视图
4. 统一动画曲线和时长

### 第三阶段（持续优化）
1. 添加性能监控
2. 分析和优化热点代码
3. 减少不必要的 widget 重建
4. 优化内存占用

## 📝 测试清单

- [ ] 滚动包含 1000+ 首歌的播放列表，检查是否流畅
- [ ] 快速切换标签页，检查是否卡顿
- [ ] 播放音乐时打开全屏播放器，检查动画是否流畅
- [ ] 长时间使用后检查内存占用
- [ ] 在低端设备上测试性能
- [ ] 使用 Flutter DevTools 分析性能

## 🎨 交互体验增强

### 微交互
- 点击时轻微缩放
- 触觉反馈
- 加载状态指示器
- 下拉刷新动画
- 骨架屏占位

### 视觉反馈
- 按钮按下高亮
- 列表项选中状态
- 播放进度平滑过渡
- 封面图淡入动画

### 手势优化
- 播放器页面下滑关闭
- 歌词页面左右滑动
- 长按显示菜单
- 双击快进/快退

## 📚 参考资源

- [Flutter Performance Best Practices](https://docs.flutter.dev/perf/best-practices)
- [Flutter Performance Profiling](https://docs.flutter.dev/perf/ui-performance)
- [Material Design Motion](https://m3.material.io/styles/motion/overview)
