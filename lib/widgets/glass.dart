import 'dart:async';

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/settings/settings_controller.dart';
import '../core/theme/design_tokens.dart';
import '../core/theme/platform_motion.dart';

export '../core/theme/design_tokens.dart';
export '../core/theme/platform_motion.dart';
export '../core/theme/app_theme.dart' show GlassTokens, GlassTheme;

const double _macOSWindowControlsInset = 76;

/// 标记内容已经通过侧栏等布局避开了 macOS 左上角窗口按钮。
class GWindowControlsSafeRegion extends InheritedWidget {
  const GWindowControlsSafeRegion({
    super.key,
    required super.child,
    this.safe = true,
  });

  final bool safe;

  static bool contains(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GWindowControlsSafeRegion>()
          ?.safe ??
      false;

  @override
  bool updateShouldNotify(GWindowControlsSafeRegion oldWidget) =>
      oldWidget.safe != safe;
}

class GBreakpoints {
  GBreakpoints._();

  static const double compact = 600;
  static const double contentSplit = 720;
  static const double sidebar = 840;
  static const double desktopPlayer = 1080;
  static const double contentMax = 1320;
}

/// 全屏内容需要避让红黄绿按钮；主框架右侧内容已经由侧栏完成避让。
double macOSWindowControlsInset(BuildContext context) {
  final macOS = Theme.of(context).platform == TargetPlatform.macOS;
  return macOS && !GWindowControlsSafeRegion.contains(context)
      ? _macOSWindowControlsInset
      : 0;
}

/// ============================================================
/// 设计系统基础组件（大厂风格）
/// 全部基于 GestureDetector 实现：不注册 MouseRegion，
/// 从根本上规避 macOS 上 MouseTracker._debugDuringDeviceUpdate 断言。
/// ============================================================

/// 页面大标题（各页顶部统一使用）
TextStyle pageTitleStyle(BuildContext context) => TextStyle(
      fontSize:
          MediaQuery.sizeOf(context).width < 600 ? 27 : TypeScale.pageTitle,
      fontWeight: TypeScale.heavy,
      letterSpacing: 0,
      color: Theme.of(context).colorScheme.onSurface,
      height: 1.08,
    );

/// 主框架内容页头。保持各栏目标题、说明和右侧操作在同一基线上。
class GPageHeader extends StatelessWidget {
  const GPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final windowControlsInset = macOSWindowControlsInset(context);
    return Padding(
      padding: padding ??
          (compact
              ? EdgeInsets.fromLTRB(20 + windowControlsInset, 18, 20, 12)
              : EdgeInsets.fromLTRB(24 + windowControlsInset, 24, 24, 14)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackActions = trailing != null && constraints.maxWidth < 420;
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: pageTitleStyle(context), maxLines: 2),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TypeScale.body,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          );
          final effectiveTrailing = actions != null && actions!.isNotEmpty
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < actions!.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions![i],
                    ],
                  ],
                )
              : trailing;
          if (stackActions && effectiveTrailing != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 12),
                Align(
                    alignment: Alignment.centerRight, child: effectiveTrailing),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: heading),
              if (effectiveTrailing != null) ...[
                const SizedBox(width: 16),
                effectiveTrailing,
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 统一的毛玻璃填充色（随明暗主题）
Color glassFill(BuildContext context, {double alpha = 0.06}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final base = dark ? Colors.white : Colors.black;
  var quality = 'auto';
  try {
    quality =
        Provider.of<SettingsController>(context, listen: false).glassQuality;
  } catch (_) {}
  final multiplier = switch (quality) {
    'smooth' => 0.66,
    'detailed' => 1.35,
    _ => MediaQuery.devicePixelRatioOf(context) >= 2 ? 1.0 : 0.78,
  };
  return base.withValues(alpha: (alpha * multiplier).clamp(0.0, 1.0));
}

/// 统一的细分割线颜色
Color glassHairline(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? DarkPalette.hairline
        : LightPalette.hairline;

/// 按压反馈容器：按下轻微缩小，松手回弹
class GPressScale extends StatefulWidget {
  const GPressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.965,
    this.disabled = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool disabled;

  @override
  State<GPressScale> createState() => _GPressScaleState();
}

class _GPressScaleState extends State<GPressScale> {
  bool _pressed = false;
  bool _focused = false;
  bool _hovered = false;

  @override
  void didUpdateWidget(GPressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.disabled || widget.onTap == null) {
      _pressed = false;
      _hovered = false;
    }
  }

  /// 统一的激活入口：点按与键盘 Enter/Space 都经过这里，
  /// 保证整个设计系统的触觉反馈一致（按下后取消不会触发）。
  void _activate() {
    final onTap = widget.onTap;
    if (widget.disabled || onTap == null) return;
    PlatformMotion.selectionFeedback(context);
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.disabled && widget.onTap != null;
    final ios = PlatformMotion.isIOS(context);
    final platform = Theme.of(context).platform;
    final desktopPointer =
        platform == TargetPlatform.windows || platform == TargetPlatform.linux;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = PlatformMotion.duration(context, Motion.fast);
    Widget result = Semantics(
      button: enabled,
      enabled: enabled,
      child: Focus(
        canRequestFocus: enabled,
        onFocusChange: (value) {
          if (mounted) setState(() => _focused = value);
        },
        onKeyEvent: (_, event) {
          if (!enabled || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            _activate();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _activate : null,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          child: AnimatedContainer(
            duration: duration,
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RadiusToken.sm),
              color: _hovered
                  ? Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.055)
                  : null,
              border: _focused
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            child: AnimatedOpacity(
              opacity: ios && _pressed ? 0.72 : 1,
              duration: duration,
              child: AnimatedScale(
                scale: !reduceMotion && !ios && _pressed ? widget.scale : 1,
                duration: duration,
                curve: Curves.easeOut,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
    if (desktopPointer) {
      result = MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled ? (_) => setState(() => _hovered = false) : null,
        child: result,
      );
    }
    return result;
  }
}

/// 自定义顶栏（替代 AppBar，无 InkWell/MouseRegion，规避 macOS 鼠标断言卡死）
class GAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.onBack,
    this.actions,
    this.transparent = false,
  });

  final String? title;
  final Widget? titleWidget;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final bool transparent;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    final scheme = Theme.of(context).colorScheme;
    final seamlessMobile =
        MediaQuery.sizeOf(context).width < GBreakpoints.sidebar;
    final windowControlsInset = macOSWindowControlsInset(context);
    // preferredSize 无法感知 context，顶栏高度必须固定为 56。
    // 因此在栏内限制字号放大倍数，让大字号仍能放大但不撑破固定高度。
    final titleScaler = MediaQuery.textScalerOf(context).clamp(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.3,
    );
    final titleContent = MediaQuery.withNoTextScaling(
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.titleMedium!.copyWith(
              fontSize: titleScaler.scale(17),
              fontWeight: TypeScale.semibold,
              color: scheme.onSurface,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: titleWidget ?? Text(title ?? ''),
      ),
    );
    final toolbar = SizedBox(
      height: 56,
      child: seamlessMobile && windowControlsInset == 0
          ? Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        actions != null && actions!.length > 1 ? 108 : 64,
                  ),
                  child: Center(child: titleContent),
                ),
                if (back != null)
                  Positioned(
                    left: 4,
                    child: GBackButton(onTap: back),
                  ),
                if (actions != null)
                  Positioned(
                    right: 4,
                    child:
                        Row(mainAxisSize: MainAxisSize.min, children: actions!),
                  ),
              ],
            )
          : Row(
              children: [
                SizedBox(width: 6 + windowControlsInset),
                if (back != null)
                  GBackButton(onTap: back)
                else
                  const SizedBox(width: 12),
                const SizedBox(width: 4),
                Expanded(child: titleContent),
                if (actions != null) ...actions!,
                const SizedBox(width: 12),
              ],
            ),
    );
    return Container(
      key: const ValueKey('g-app-bar-surface'),
      decoration: BoxDecoration(
        color: transparent
            ? Colors.transparent
            : seamlessMobile
                ? scheme.surfaceContainerLowest
                : glassFill(context, alpha: 0.06),
        border: Border(
          bottom: BorderSide(
            color: transparent || seamlessMobile
                ? Colors.transparent
                : glassHairline(context),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: toolbar,
      ),
    );
  }
}

/// 统一的简洁返回控件，保留完整触控区域。
class GBackButton extends StatelessWidget {
  const GBackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: true,
      label: '返回',
      child: Tooltip(
        message: '返回',
        child: GPressScale(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 48,
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cupertino.CupertinoIcons.chevron_back,
                    size: 21,
                    color: scheme.onSurface,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃卡片容器：统一毛玻璃质感 + 细边框 + 圆角
class GSurface extends StatelessWidget {
  const GSurface({
    super.key,
    this.child,
    this.padding,
    this.radius = RadiusToken.lg,
    this.alpha = 0.06,
    this.onTap,
    this.color,
  });

  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double alpha;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: color ?? glassFill(context, alpha: alpha),
        border: Border.all(color: glassHairline(context)),
      ),
      child: child,
    );
    if (onTap != null) {
      content = GPressScale(onTap: onTap, child: content);
    }
    return content;
  }
}

/// 区块标题（大标题 + 可选副标题/右侧操作）
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.action});

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: LayoutBuilder(
          builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: TypeScale.section,
                            fontWeight: TypeScale.bold,
                            letterSpacing: 0,
                            height: 1.1,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: TypeScale.small,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (action != null) ...[
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth * 0.45),
                      child: action!,
                    ),
                  ],
                ],
              )),
    );
  }
}

/// 大按钮：主色渐变胶囊 / 柔和主色两种形态
class GButton extends StatelessWidget {
  const GButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.filled = true,
    this.loading = false,
    this.expand = false,
    this.small = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool filled;
  final bool loading;
  final bool expand;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null && !loading;
    final foreground = filled ? scheme.onPrimary : scheme.primary;
    // Keep the label in layout while loading so surrounding controls do not move.
    final child = Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: loading ? 0 : 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon!,
                  size: small ? 15 : 18,
                  color: filled ? scheme.onPrimary : scheme.primary,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                  child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: small ? 14 : 16,
                  fontWeight: TypeScale.semibold,
                  color: filled ? scheme.onPrimary : scheme.primary,
                ),
              )),
            ],
          ),
        ),
        if (loading)
          Positioned.fill(
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: foreground),
              ),
            ),
          ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      value: loading ? '正在加载' : null,
      liveRegion: loading,
      onTap: enabled
          ? () {
              PlatformMotion.selectionFeedback(context);
              onTap!();
            }
          : null,
      child: ExcludeSemantics(
        child: GPressScale(
          onTap: enabled ? onTap : null,
          disabled: !enabled,
          child: AnimatedContainer(
            duration: PlatformMotion.duration(context, Motion.fast),
            width: expand ? double.infinity : null,
            constraints: BoxConstraints(
              minHeight: switch (Theme.of(context).platform) {
                TargetPlatform.android => 48,
                TargetPlatform.iOS => 44,
                _ => 36,
              },
            ),
            padding: EdgeInsets.symmetric(
              horizontal: small ? 16 : 22,
              vertical: small ? 7 : 11,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RadiusToken.pill),
              color: filled
                  ? scheme.primary
                  : scheme.primary.withValues(alpha: 0.10),
            ),
            child: Center(widthFactor: 1, heightFactor: 1, child: child),
          ),
        ),
      ),
    );
  }
}

/// 圆形图标按钮（无 hover，规避 macOS 断言）
class GIconButton extends StatelessWidget {
  const GIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 22,
    this.padding = 10,
    this.tint,
    this.disabled = false,
    this.filled = false,
    this.backgroundColor,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double padding;
  final Color? tint;
  final bool disabled;
  final bool filled;
  final Color? backgroundColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final platform = Theme.of(context).platform;
    final minimumTargetSize = switch (platform) {
      TargetPlatform.android => 48.0,
      TargetPlatform.iOS => 44.0,
      _ => 36.0,
    };
    final visualSize = size + padding * 2;
    final targetSize =
        visualSize > minimumTargetSize ? visualSize : minimumTargetSize;
    final color = tint ?? (disabled ? scheme.outlineVariant : scheme.onSurface);
    final bg = backgroundColor ??
        (filled
            ? scheme.primary.withValues(alpha: 0.92)
            : scheme.onSurface.withValues(alpha: 0.06));
    final enabled = !disabled && onTap != null;
    final button = SizedBox.square(
      dimension: targetSize,
      child: GPressScale(
        onTap: enabled ? onTap : null,
        disabled: !enabled,
        child: Center(
          child: Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
            ),
            child: Icon(
              icon,
              size: size,
              color: filled ? scheme.onPrimary : color,
            ),
          ),
        ),
      ),
    );
    final semanticButton = Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      onTap: enabled
          ? () {
              PlatformMotion.selectionFeedback(context);
              onTap!();
            }
          : null,
      child: tooltip == null ? button : ExcludeSemantics(child: button),
    );
    return tooltip == null
        ? semanticButton
        : Tooltip(message: tooltip!, child: semanticButton);
  }
}

/// 列表行（替代 ListTile，无 MouseRegion）
class GListTile extends StatelessWidget {
  const GListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.margin = const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return GPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: PlatformMotion.duration(context, Motion.fast),
        constraints: BoxConstraints(minHeight: ios ? 56 : 0),
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RadiusToken.md),
          color: selected
              ? scheme.onSurface.withValues(alpha: 0.07)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                            fontSize: TypeScale.bodyLarge,
                            fontWeight: selected
                                ? TypeScale.semibold
                                : TypeScale.medium,
                            color: selected ? scheme.primary : scheme.onSurface,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: title!,
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                            fontSize: TypeScale.small,
                            color: scheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

/// 播放进度条（替代 Slider，支持点击/拖动 seek，自带圆点滑块）
class GProgressBar extends StatefulWidget {
  const GProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.bufferedPosition,
    this.height = 4,
    this.showThumb = true,
    this.activeColor,
    this.semanticLabel = '播放进度',
    this.touchTargetHeight,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  /// 已缓冲进度，绘制为轨道上的二级进度。为空则不显示。
  final Duration? bufferedPosition;
  final double height;
  final bool showThumb;
  final Color? activeColor;
  final String semanticLabel;
  final double? touchTargetHeight;

  @override
  State<GProgressBar> createState() => _GProgressBarState();
}

/// Shared progress calculation for full-size and compact playback controls.
double playbackProgressFraction(Duration position, Duration duration) {
  final totalMs = duration.inMilliseconds;
  if (totalMs <= 0) return 0.0;
  return (position.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble();
}

class _GProgressBarState extends State<GProgressBar> {
  double? _dragFraction;
  final FocusNode _focusNode = FocusNode(debugLabel: 'playback-progress');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _seekTo(int milliseconds) {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return;
    final target = milliseconds.clamp(0, total);
    if (target == widget.position.inMilliseconds) return;
    widget.onSeek(Duration(milliseconds: target));
  }

  String _timeLabel(int milliseconds) {
    final seconds = milliseconds < 0 ? 0 : milliseconds ~/ 1000;
    final minutes = seconds ~/ 60;
    final tail = (seconds % 60).toString().padLeft(2, '0');
    if (minutes < 60) return '$minutes:$tail';
    return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:$tail';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.activeColor ?? scheme.primary;
    final total = widget.duration.inMilliseconds.toDouble();
    final fraction = playbackProgressFraction(widget.position, widget.duration);
    final displayedFraction = _dragFraction ?? fraction;
    final buffered = widget.bufferedPosition == null
        ? 0.0
        : playbackProgressFraction(widget.bufferedPosition!, widget.duration);
    // 拖动中加粗轨道、放大滑块，给出「已抓住」的手感。
    final dragging = _dragFraction != null;
    final motion = PlatformMotion.duration(context, Motion.fast);
    final trackHeight = dragging ? widget.height + 2 : widget.height;
    final thumbSize = dragging ? 15.0 : 11.0;
    final enabled = total > 0;
    final platform = Theme.of(context).platform;
    final touchTargetHeight = widget.touchTargetHeight ??
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS
            ? 44.0
            : 28.0);
    final displayedMilliseconds = (displayedFraction * total).round();
    String timeValue(int milliseconds) =>
        '${_timeLabel(milliseconds)} / ${_timeLabel(total.round())}';

    return Semantics(
      slider: enabled,
      enabled: enabled,
      label: widget.semanticLabel,
      value: enabled ? timeValue(displayedMilliseconds) : '时长未知',
      increasedValue: enabled
          ? timeValue((displayedMilliseconds + 5000).clamp(0, total.round()))
          : null,
      decreasedValue: enabled
          ? timeValue((displayedMilliseconds - 5000).clamp(0, total.round()))
          : null,
      onIncrease: enabled ? () => _seekTo(displayedMilliseconds + 5000) : null,
      onDecrease: enabled ? () => _seekTo(displayedMilliseconds - 5000) : null,
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: enabled,
        onFocusChange: (focused) {
          if (mounted) setState(() => _focused = focused);
        },
        onKeyEvent: (_, event) {
          if (!enabled || event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final keyboard = HardwareKeyboard.instance;
          if (keyboard.isControlPressed ||
              keyboard.isMetaPressed ||
              keyboard.isShiftPressed ||
              keyboard.isAltPressed) {
            return KeyEventResult.ignored;
          }
          final target = switch (event.logicalKey) {
            LogicalKeyboardKey.arrowLeft ||
            LogicalKeyboardKey.arrowDown =>
              displayedMilliseconds - 5000,
            LogicalKeyboardKey.arrowRight ||
            LogicalKeyboardKey.arrowUp =>
              displayedMilliseconds + 5000,
            LogicalKeyboardKey.home => 0,
            LogicalKeyboardKey.end => total.round(),
            _ => null,
          };
          if (target == null) return KeyEventResult.ignored;
          _seekTo(target);
          return KeyEventResult.handled;
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RadiusToken.sm),
            border: _focused ? Border.all(color: active, width: 2) : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              double? fractionAt(double dx) {
                if (total <= 0 || constraints.maxWidth <= 0) return null;
                return (dx / constraints.maxWidth).clamp(0.0, 1.0).toDouble();
              }

              void commitAt(double dx) {
                final ratio = fractionAt(dx);
                if (ratio == null) return;
                PlatformMotion.selectionFeedback(context);
                _focusNode.requestFocus();
                widget.onSeek(Duration(milliseconds: (total * ratio).round()));
              }

              void previewAt(double dx) {
                final ratio = fractionAt(dx);
                if (ratio == null) return;
                setState(() => _dragFraction = ratio);
              }

              void commitDrag() {
                final ratio = _dragFraction;
                if (ratio == null || total <= 0) return;
                PlatformMotion.selectionFeedback(context);
                widget.onSeek(Duration(milliseconds: (total * ratio).round()));
                setState(() => _dragFraction = null);
              }

              void cancelDrag() {
                if (_dragFraction != null) setState(() => _dragFraction = null);
              }

              return GestureDetector(
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => commitAt(details.localPosition.dx),
                onHorizontalDragStart: total <= 0
                    ? null
                    : (_) => setState(() => _dragFraction = fraction),
                onHorizontalDragUpdate: total <= 0
                    ? null
                    : (details) => previewAt(details.localPosition.dx),
                onHorizontalDragEnd: total <= 0 ? null : (_) => commitDrag(),
                onHorizontalDragCancel: total <= 0 ? null : cancelDrag,
                child: SizedBox(
                  height: touchTargetHeight,
                  child: Center(
                    child: AnimatedContainer(
                      duration: motion,
                      curve: Motion.standard,
                      height: trackHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.centerLeft,
                        children: [
                          // 轨道
                          Container(
                            height: trackHeight,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.55),
                              borderRadius:
                                  BorderRadius.circular(trackHeight / 2),
                            ),
                          ),
                          // 已缓冲（二级进度）
                          if (buffered > displayedFraction)
                            FractionallySizedBox(
                              widthFactor: buffered,
                              heightFactor: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.22),
                                  borderRadius:
                                      BorderRadius.circular(trackHeight / 2),
                                ),
                              ),
                            ),
                          // 已播放
                          FractionallySizedBox(
                            widthFactor: displayedFraction,
                            heightFactor: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: AppBrand.gradient(active),
                                borderRadius:
                                    BorderRadius.circular(trackHeight / 2),
                              ),
                            ),
                          ),
                          if (widget.showThumb)
                            Positioned(
                              left: (constraints.maxWidth * displayedFraction) -
                                  thumbSize / 2,
                              top: (trackHeight - thumbSize) / 2,
                              child: AnimatedContainer(
                                duration: motion,
                                curve: Motion.standard,
                                width: thumbSize,
                                height: thumbSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: scheme.onPrimary,
                                  boxShadow: [
                                    BoxShadow(
                                      color: scheme.shadow.withValues(
                                          alpha: dragging ? 0.36 : 0.28),
                                      blurRadius: dragging ? 6 : 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 分类筛选胶囊（替代 ChoiceChip）
class GChoiceChip extends StatelessWidget {
  const GChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.mini = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: PlatformMotion.duration(context, Motion.fast),
        margin: const EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(
          horizontal: mini ? 12 : 15,
          vertical: mini ? 6 : 8,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RadiusToken.pill),
          color: selected ? scheme.primary : scheme.surfaceContainerHigh,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: mini ? TypeScale.small : TypeScale.body,
            fontWeight: selected ? TypeScale.semibold : TypeScale.medium,
            color: selected ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// 分段选择控件（搜索类型等场景）
class GSegmented extends StatelessWidget {
  const GSegmented({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<String> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = PlatformMotion.duration(context, Motion.normal);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      // 选中滑块在轨道上滑动（对齐 Apple 分段控件），而不是逐项跳变底色。
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = items.length;
          if (count == 0) return const SizedBox.shrink();
          final hasBoundedWidth = constraints.hasBoundedWidth &&
              constraints.maxWidth.isFinite &&
              constraints.maxWidth > 0;

          final labels = <Widget>[
            for (var i = 0; i < count; i++)
              _GSegmentedLabel(
                label: items[i],
                selected: i == selected,
                duration: duration,
                onTap: () => onSelected(i),
                expand: hasBoundedWidth,
              ),
          ];

          // 宽度不确定时（如被 Row 包裹）退回无滑块的紧凑排列，
          // 避免用 FractionallySizedBox 触发无界宽度断言。
          if (!hasBoundedWidth) {
            return Row(mainAxisSize: MainAxisSize.min, children: labels);
          }

          final index = selected.clamp(0, count - 1);
          return Stack(
            children: [
              Positioned.fill(
                child: AnimatedAlign(
                  duration: duration,
                  curve: Motion.standard,
                  // -1 → 最左，1 → 最右；单项时居中。
                  alignment: Alignment(
                    count == 1 ? 0 : (index / (count - 1)) * 2 - 1,
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / count,
                    // 必须显式撑满高度，否则 Align 下的子级高度会塌成 0。
                    heightFactor: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        color: scheme.surfaceContainerHigh,
                        boxShadow: [
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: 0.16),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [for (final label in labels) Expanded(child: label)],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 分段控件的单个标签。滑块由父级统一绘制，这里只负责文字与点击。
class _GSegmentedLabel extends StatelessWidget {
  const _GSegmentedLabel({
    required this.label,
    required this.selected,
    required this.duration,
    required this.onTap,
    required this.expand,
  });

  final String label;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: AnimatedDefaultTextStyle(
        duration: duration,
        curve: Motion.standard,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              fontSize: TypeScale.body,
              fontWeight: selected ? TypeScale.semibold : TypeScale.medium,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// 加载占位
class GLoading extends StatelessWidget {
  const GLoading({super.key, this.padding = 60});

  final double padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: padding),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}

/// 骨架屏占位块：内容加载期间代替转圈，保持版式稳定、感知更快。
/// 开启「减弱动态效果」时退化为静态色块，不做流光。
class GSkeleton extends StatefulWidget {
  const GSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = RadiusToken.sm,
    this.shape = BoxShape.rectangle,
  });

  /// 圆形骨架（头像等），尺寸取 [height]。
  const GSkeleton.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = 0,
        shape = BoxShape.circle;

  final double? width;
  final double height;
  final double radius;
  final BoxShape shape;

  @override
  State<GSkeleton> createState() => _GSkeletonState();
}

class _GSkeletonState extends State<GSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 无障碍设置变化时同步启停，避免在减弱动态效果下空转。
    if (MediaQuery.disableAnimationsOf(context)) {
      _shimmer.stop();
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = glassFill(context, alpha: 0.07);
    final highlight = glassFill(context, alpha: 0.13);
    final borderRadius = widget.shape == BoxShape.circle
        ? null
        : BorderRadius.circular(widget.radius);

    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          shape: widget.shape,
          borderRadius: borderRadius,
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (context, _) {
          // 流光从左到右扫过，两端留白让循环看起来连续。
          final t = _shimmer.value * 2 - 1;
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: widget.shape,
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment(t - 1, 0),
                end: Alignment(t + 1, 0),
                colors: [base, highlight, base],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 列表骨架屏：封面方块 + 两行文字，形状对齐 [GListTile] / SongRow。
class GSkeletonList extends StatelessWidget {
  const GSkeletonList({
    super.key,
    this.itemCount = 6,
    this.leadingSize = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
  });

  final int itemCount;
  final double leadingSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < itemCount; i++)
          Padding(
            padding: padding,
            child: Row(
              children: [
                GSkeleton(
                  width: leadingSize,
                  height: leadingSize,
                  radius: RadiusToken.md,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 宽度递减，避免整列骨架看起来像表格。
                      GSkeleton(width: 120 + (i % 3) * 46, height: 13),
                      const SizedBox(height: Space.sm),
                      GSkeleton(width: 80 + (i % 4) * 28, height: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 状态切换时「弹一下」的图标。用于收藏、下载等开关型操作：
/// 图标交叉淡入 + 一次轻微过冲缩放，让操作有确定的落点反馈。
/// 开启「减弱动态效果」时退化为直接切换。
class GPopIcon extends StatefulWidget {
  const GPopIcon({
    super.key,
    required this.icon,
    required this.active,
    this.size = 22,
    this.color,
    this.activeColor,
  });

  final IconData icon;

  /// 激活态。变化时触发弹跳。
  final bool active;
  final double size;
  final Color? color;
  final Color? activeColor;

  @override
  State<GPopIcon> createState() => _GPopIconState();
}

class _GPopIconState extends State<GPopIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: Motion.slow,
      value: 1,
    );
    // 0 → 1 走一段过冲曲线：0.82 弹到 1.12 再回到 1。
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.82, end: 1.12), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 55),
    ]).animate(CurvedAnimation(parent: _pop, curve: Motion.standard));
  }

  @override
  void didUpdateWidget(GPopIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pop.value = 1;
      return;
    }
    _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = widget.active
        ? (widget.activeColor ?? scheme.primary)
        : (widget.color ?? scheme.onSurfaceVariant);
    return ScaleTransition(
      scale: _scale,
      child: AnimatedSwitcher(
        duration: PlatformMotion.duration(context, Motion.fast),
        child: Icon(
          widget.icon,
          // Key 必须区分状态，否则 AnimatedSwitcher 不会触发过渡。
          key: ValueKey('${widget.icon.codePoint}-${widget.active}'),
          size: widget.size,
          color: tint,
        ),
      ),
    );
  }
}

/// 列表项入场动画：按索引错峰淡入并轻微上浮。
/// 仅在首屏出现时播放一次，滚动复用不会重复触发。
class GListEntrance extends StatefulWidget {
  const GListEntrance({
    super.key,
    required this.index,
    required this.child,
    this.stagger = const Duration(milliseconds: 28),
    this.maxStaggeredItems = 12,
  });

  final int index;
  final Widget child;

  /// 相邻两项之间的延迟。
  final Duration stagger;

  /// 超过该数量后不再累加延迟，避免长列表末尾等待过久。
  final int maxStaggeredItems;

  @override
  State<GListEntrance> createState() => _GListEntranceState();
}

class _GListEntranceState extends State<GListEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.slow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        widget.index >= widget.maxStaggeredItems) {
      _startTimer?.cancel();
      _startTimer = null;
      _controller.value = 1;
      return;
    }
    if (_controller.value > 0 || _startTimer != null) return;
    final steps = widget.index.clamp(0, widget.maxStaggeredItems);
    _startTimer = Timer(widget.stagger * steps, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Motion.standard);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// 统一的页面转场：淡入 + 轻微上浮。比 MaterialPageRoute 的默认转场更克制，
/// 且在 macOS / Windows 上不会出现移动端味道过重的整页横移。
///
/// iOS 保留系统默认的边缘返回手势体验，因此仍走 [MaterialPageRoute]。
Route<T> buildAppRoute<T>(
  BuildContext context,
  WidgetBuilder builder, {
  RouteSettings? settings,
}) {
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS) {
    return MaterialPageRoute<T>(builder: builder, settings: settings);
  }
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: reduceMotion ? Duration.zero : Motion.slow,
    reverseTransitionDuration: reduceMotion ? Duration.zero : Motion.normal,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.standard,
        reverseCurve: Motion.standard.flipped,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 通用空状态 / 错误提示（图标 + 文字 + 可选重试按钮）
class GEmptyState extends StatelessWidget {
  const GEmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.onRetry,
    this.title,
    this.actionLabel,
  });

  final IconData icon;
  final String text;
  final String? title;
  final VoidCallback? onRetry;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: 0.18),
                  scheme.primary.withValues(alpha: 0.05),
                ],
              ),
              border: Border.all(color: glassHairline(context)),
            ),
            child: Icon(
              icon,
              size: 30,
              color: scheme.primary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 16),
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                fontSize: TypeScale.subhead,
                fontWeight: TypeScale.semibold,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: TypeScale.body, color: scheme.onSurfaceVariant),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            GButton(label: actionLabel ?? '重试', filled: false, onTap: onRetry),
          ],
        ],
      ),
    );
  }
}
