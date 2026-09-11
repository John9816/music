import 'package:flutter/material.dart';

/// 显示应用统一的 Toast 提示
///
/// 自动计算底部边距以避免遮挡迷你播放栏
void showAppToast(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) {
  final mediaQuery = MediaQuery.of(context);
  final bottomInset = mediaQuery.viewPadding.bottom;

  // 计算迷你播放栏的高度（如果存在）
  // 移动端迷你栏约 56-80px，考虑安全区
  const miniPlayerHeight = 56.0;
  final bottomMargin = bottomInset + miniPlayerHeight + 8.0;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: action,
      duration: duration,
      margin: EdgeInsets.only(
        bottom: bottomMargin,
        left: 16,
        right: 16,
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// 显示错误提示
void showErrorToast(BuildContext context, String message) {
  showAppToast(context, message);
}

/// 显示成功提示
void showSuccessToast(BuildContext context, String message) {
  showAppToast(context, message);
}
