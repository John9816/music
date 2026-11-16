import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';
import 'glass.dart' show glassHairline, topSystemInset;

/// 悬浮顶栏里标题的 [Opacity]，测试据此校验淡入时机。
@visibleForTesting
const ValueKey<String> gStickyTopBarTitleKey =
    ValueKey<String>('g-sticky-top-bar-title');

/// 悬浮顶栏底色所在的 [Container]，测试据此校验 alpha 插值。
@visibleForTesting
const ValueKey<String> gStickyTopBarFillKey =
    ValueKey<String>('g-sticky-top-bar-fill');

/// 滚动联动的悬浮顶栏。
///
/// 页面把大标题放在滚动内容流里，往上滑标题会跟着滚走，之后的顶部是一条
/// 「什么都没有」的裸带子——内容会直接从状态栏图标底下穿过去。这里在页面顶部
/// 叠一层固定的栏：内容滑到它下面时底色逐渐变实、标题淡入，标题就从「滚动内容
/// 里的大字」接续成「栏里的居中字」，中间不留空档。
///
/// 三条曲线挂在同一个滚动进度上：
/// - 底色 alpha：`fadeStart → fadeEnd` 线性到顶，easeOut 收尾；
/// - 标题透明度：进度过半之后才开始淡入，避免与大标题同框打架；
/// - 顶部 scrim：进度越低越明显，只压在状态栏那一条上，保证图标压在任何
///   内容上都能看清。
///
/// 进度为 0 时整层不参与命中测试，不会挡住下拉刷新和列表顶部的手势。
class GStickyTopBar extends StatefulWidget {
  const GStickyTopBar({
    super.key,
    required this.controller,
    this.title,
    this.actions,
    this.height = 52,
    this.fadeStart = 28,
    this.fadeEnd = 108,
  });

  /// 页面主滚动容器持有的控制器，用来读取滚动进度。
  final ScrollController controller;

  /// 收起态的居中标题；为空时只保留底色与 scrim（首页这种大标题即内容的页面）。
  final String? title;

  /// 收起态右侧的操作按钮，标题会自动为它让出空间。
  final List<Widget>? actions;

  /// 不含系统区的高度。
  final double height;

  /// 开始渐显时的滚动偏移。
  final double fadeStart;

  /// 完全变实时的滚动偏移；必须大于 [fadeStart]。
  final double fadeEnd;

  @override
  State<GStickyTopBar> createState() => _GStickyTopBarState();
}

class _GStickyTopBarState extends State<GStickyTopBar> {
  double get _progress {
    final controller = widget.controller;
    if (!controller.hasClients) return 0;
    final offset = controller.offset;
    final span = widget.fadeEnd - widget.fadeStart;
    if (span <= 0) return offset >= widget.fadeEnd ? 1 : 0;
    return ((offset - widget.fadeStart) / span).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => _buildBar(context, _progress),
    );
  }

  Widget _buildBar(BuildContext context, double progress) {
    final eased = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inset = topSystemInset(context);
    final titleOpacity = ((eased - 0.55) / 0.45).clamp(0.0, 1.0);
    final actions = widget.actions ?? const <Widget>[];
    final hasActions = actions.isNotEmpty;
    // 底色调到半透明，留一点内容透出来，接近毛玻璃的手感。
    final fillAlpha = eased * (dark ? 0.88 : 0.86);
    final scrimColor = dark ? Colors.black : scheme.surfaceContainerLowest;

    Widget bar = Container(
      key: gStickyTopBarFillKey,
      height: inset + widget.height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: fillAlpha),
        border: Border(
          bottom: BorderSide(
            color: glassHairline(context).withValues(alpha: 0.9 * eased),
            width: 0.6,
          ),
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: inset),
            child: Stack(
              children: [
                if (widget.title != null)
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: hasActions ? 20 + actions.length * 44 : 16,
                      ),
                      child: Opacity(
                        key: gStickyTopBarTitleKey,
                        opacity: titleOpacity,
                        child: Center(
                          child: Text(
                            widget.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: TypeScale.subhead,
                              fontWeight: TypeScale.semibold,
                              letterSpacing: 0.1,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (hasActions)
                  Positioned(
                    right: 6,
                    top: 0,
                    bottom: 0,
                    child: Opacity(
                      opacity: titleOpacity,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: actions,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // scrim 只覆盖状态栏那一条：进度越低越浓，进度到顶后完全让位给底色。
          if (inset > 0 && eased < 0.999)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: inset + 14,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        scrimColor.withValues(alpha: 0.46 * (1 - eased)),
                        scrimColor.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    // 高对比度模式与进度极低时不挂模糊，省掉一层全屏读写。
    if (eased > 0.04 && !MediaQuery.highContrastOf(context)) {
      bar = ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: 18 * eased,
            sigmaY: 18 * eased,
          ),
          child: bar,
        ),
      );
    }

    return IgnorePointer(
      ignoring: eased <= 0.02,
      child: RepaintBoundary(child: bar),
    );
  }
}
