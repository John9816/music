import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings/settings_controller.dart';
import '../core/theme/design_tokens.dart';

export '../core/theme/design_tokens.dart';
export '../core/theme/app_theme.dart' show GlassTokens, GlassTheme;

const double _macOSWindowControlsInset = 76;

/// 标记内容已经通过侧栏等布局避开了 macOS 左上角窗口按钮。
class GWindowControlsSafeRegion extends InheritedWidget {
  const GWindowControlsSafeRegion({
    super.key,
    required super.child,
  });

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GWindowControlsSafeRegion>() !=
      null;

  @override
  bool updateShouldNotify(GWindowControlsSafeRegion oldWidget) => false;
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
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final windowControlsInset = macOSWindowControlsInset(context);
    return Padding(
      padding: padding ??
          (compact
              ? EdgeInsets.fromLTRB(
                  18 + windowControlsInset,
                  18,
                  18,
                  12,
                )
              : EdgeInsets.fromLTRB(
                  24 + windowControlsInset,
                  28,
                  24,
                  14,
                )),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: pageTitleStyle(context)),
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
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 16),
            trailing!,
          ],
        ],
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

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.disabled && widget.onTap != null;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : Motion.fast;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? widget.onTap : null,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedOpacity(
        opacity: ios && _pressed ? 0.56 : 1,
        duration: duration,
        child: AnimatedScale(
          scale: !reduceMotion && !ios && _pressed ? widget.scale : 1,
          duration: duration,
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
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
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final scheme = Theme.of(context).colorScheme;
    final windowControlsInset = macOSWindowControlsInset(context);
    final titleContent = DefaultTextStyle(
      style: TextStyle(
        fontSize: 17,
        fontWeight: TypeScale.semibold,
        color: scheme.onSurface,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: titleWidget ?? Text(title ?? ''),
    );
    final toolbar = SizedBox(
      height: 56,
      child: ios
          ? Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 72),
                  child: Center(child: titleContent),
                ),
                if (onBack != null)
                  Positioned(
                    left: 4,
                    child: GIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: '返回',
                      size: 17,
                      padding: 11,
                      onTap: onBack,
                    ),
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
                if (onBack != null)
                  GIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: '返回',
                    size: 16,
                    padding: 12,
                    onTap: onBack,
                  )
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
      decoration: BoxDecoration(
        color:
            transparent ? Colors.transparent : glassFill(context, alpha: 0.06),
        border: Border(
          bottom: BorderSide(
            color: transparent ? Colors.transparent : glassHairline(context),
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
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: TypeScale.section,
              fontWeight: TypeScale.bold,
              letterSpacing: 0,
              height: 1.1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
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
    final Widget child;
    if (loading) {
      child = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: filled ? Colors.white : scheme.primary,
        ),
      );
    } else {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon!, size: small ? 15 : 18),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: small ? 13 : 14,
              fontWeight: TypeScale.semibold,
              color: filled ? Colors.white : scheme.primary,
            ),
          ),
        ],
      );
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: GPressScale(
          onTap: enabled ? onTap : null,
          disabled: !enabled,
          child: AnimatedContainer(
            duration: Motion.fast,
            width: expand ? double.infinity : null,
            padding: EdgeInsets.symmetric(
              horizontal: small ? 16 : 22,
              vertical: small ? 7 : 11,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RadiusToken.pill),
              gradient: filled ? AppBrand.gradient(scheme.primary) : null,
              color: filled ? null : scheme.primary.withValues(alpha: 0.12),
              boxShadow: filled
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Center(child: child),
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
      TargetPlatform.android || TargetPlatform.iOS => 44.0,
      _ => 36.0,
    };
    final visualSize = size + padding * 2;
    final targetSize =
        visualSize > minimumTargetSize ? visualSize : minimumTargetSize;
    final color = tint ?? (disabled ? scheme.outlineVariant : scheme.onSurface);
    final bg = backgroundColor ??
        (filled
            ? scheme.primary.withValues(alpha: 0.92)
            : scheme.primary.withValues(alpha: 0.10));
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
            child: Icon(icon, size: size, color: filled ? Colors.white : color),
          ),
        ),
      ),
    );
    final semanticButton = Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
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
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return GPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        constraints: BoxConstraints(minHeight: ios ? 56 : 0),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RadiusToken.md),
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? TypeScale.semibold : TypeScale.medium,
                        color: selected ? scheme.primary : scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: title!,
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 12,
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
    this.height = 4,
    this.showThumb = true,
    this.activeColor,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final double height;
  final bool showThumb;
  final Color? activeColor;

  @override
  State<GProgressBar> createState() => _GProgressBarState();
}

class _GProgressBarState extends State<GProgressBar> {
  double? _dragFraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.activeColor ?? scheme.primary;
    final total = widget.duration.inMilliseconds.toDouble();
    final pos =
        widget.position.inMilliseconds.clamp(0, total.toInt()).toDouble();
    final fraction = total <= 0 ? 0.0 : (pos / total).clamp(0.0, 1.0);
    final displayedFraction = _dragFraction ?? fraction;

    return LayoutBuilder(
      builder: (context, constraints) {
        void seekAt(double dx, {bool preview = false}) {
          if (constraints.maxWidth <= 0) return;
          final ratio = (dx / constraints.maxWidth).clamp(0.0, 1.0).toDouble();
          if (preview) setState(() => _dragFraction = ratio);
          widget.onSeek(Duration(milliseconds: (total * ratio).round()));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekAt(d.localPosition.dx),
          onHorizontalDragStart: (_) =>
              setState(() => _dragFraction = fraction),
          onHorizontalDragUpdate: (d) =>
              seekAt(d.localPosition.dx, preview: true),
          onHorizontalDragEnd: (_) => setState(() => _dragFraction = null),
          onHorizontalDragCancel: () => setState(() => _dragFraction = null),
          child: SizedBox(
            height: 22,
            child: Center(
              child: SizedBox(
                height: widget.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    // 轨道
                    Container(
                      height: widget.height,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(widget.height / 2),
                      ),
                    ),
                    // 已播放
                    FractionallySizedBox(
                      widthFactor: displayedFraction,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppBrand.gradient(active),
                          borderRadius:
                              BorderRadius.circular(widget.height / 2),
                        ),
                      ),
                    ),
                    if (widget.showThumb)
                      Positioned(
                        left: (constraints.maxWidth * displayedFraction) - 5,
                        top: (widget.height - 11) / 2,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.28),
                                blurRadius: 4,
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
        duration: Motion.fast,
        margin: const EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(
          horizontal: mini ? 12 : 15,
          vertical: mini ? 6 : 8,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RadiusToken.pill),
          gradient: selected ? AppBrand.gradient(scheme.primary) : null,
          color: selected ? null : glassFill(context, alpha: 0.05),
          border: Border.all(
            color: selected ? Colors.transparent : glassHairline(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: mini ? 12 : 13,
            fontWeight: selected ? TypeScale.semibold : TypeScale.medium,
            color: selected ? Colors.white : scheme.onSurface,
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
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: glassFill(context, alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: glassHairline(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            GPressScale(
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: Motion.fast,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: i == selected
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF2C2C2E)
                          : Colors.white)
                      : Colors.transparent,
                  boxShadow: i == selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  items[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        i == selected ? TypeScale.semibold : TypeScale.medium,
                    color: i == selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
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

/// 通用空状态 / 错误提示（图标 + 文字 + 可选重试按钮）
class GEmptyState extends StatelessWidget {
  const GEmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.onRetry,
    this.title,
  });

  final IconData icon;
  final String text;
  final String? title;
  final VoidCallback? onRetry;

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
                fontSize: 15,
                fontWeight: TypeScale.semibold,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            GButton(label: '重试', filled: false, onTap: onRetry),
          ],
        ],
      ),
    );
  }
}
