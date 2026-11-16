import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 顶部/底部系统栏图标的深浅，跟随当前页面底色。
///
/// 背景：Android 15+ 强制 edge-to-edge 之后，状态栏是一条**透明**的带子，
/// 图标颜色完全由应用决定。不主动声明时系统会沿用上一次的取值，于是在浅色
/// 页面出现白图标、在深色页面出现黑图标——也就是「顶部发白/看不见时间」。
///
/// 这里按底色亮度给出整套 style，深色底配白图标、浅色底配黑图标，并清掉
/// 系统在导航栏上强加的对比度遮罩，保持与页面同色。
SystemUiOverlayStyle systemOverlayStyleFor(
  BuildContext context, {
  Color? background,
}) {
  final scheme = Theme.of(context).colorScheme;
  final base = background ?? scheme.surfaceContainerLowest;
  final lightIcons =
      ThemeData.estimateBrightnessForColor(base) == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness:
        lightIcons ? Brightness.light : Brightness.dark,
    // iOS 语义相反：dark 表示「深色背景」，即白字。
    statusBarBrightness:
        lightIcons ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness:
        lightIcons ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

/// 让子树的系统栏图标颜色跟随底色。
///
/// 一层就够：`AnnotatedRegion` 取绘制顺序最靠上的那个，所以主框架在最外层
/// 声明一次，二级页若有自己的深色封面背景，可以在页面内部再包一层覆盖。
class GStatusBarRegion extends StatelessWidget {
  const GStatusBarRegion({super.key, required this.child, this.background});

  final Widget child;

  /// 页面实际底色；不传时按主题的 `surfaceContainerLowest` 判断。
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayStyleFor(context, background: background),
      child: child,
    );
  }
}
