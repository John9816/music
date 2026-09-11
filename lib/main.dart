import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/player/system_media_controller.dart';
import 'core/utils/performance_monitor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 全局异常兜底：任何未捕获异常只记录日志，绝不导致界面冻结/白屏。
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('=== 未捕获异常 ===\n${details.exception}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('=== 平台层异常 ===\n$error\n$stack');
    return true; // 吞掉平台层错误，防止崩溃退出
  };
  // 出错时显示小提示而非整屏灰块，避免"点不了"。
  ErrorWidget.builder = (details) => const ColoredBox(
        color: Color(0x00000000),
        child: Center(
          child: Text(
            '页面渲染出错，请返回重试',
            style: TextStyle(
              fontSize: 13,
              color: Color(0x99666666),
            ),
          ),
        ),
      );

  // macOS / Windows 毛玻璃（NSVisualEffectView / DWM 模糊）
  if (Platform.isMacOS || Platform.isWindows) {
    try {
      await Window.initialize();
      if (Platform.isMacOS) {
        // Window.initialize 会恢复系统默认标题栏，需要在初始化后重新应用。
        await Window.hideTitle();
        await Window.makeTitlebarTransparent();
        await Window.enableFullSizeContentView();
      }
    } catch (_) {}
  }

  // Android / iOS：沉浸式边到边；桌面端不适用。
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // 系统媒体卡（锁屏 / 控制中心 / 媒体键）：
  // Android 走 audio_service，iOS 与 macOS 走 MPNowPlayingInfoCenter 通道。
  // Windows 尚未实现 SMTC，只能依赖 App 内注册的全局快捷键。
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    try {
      await SystemMediaController.initialize();
    } catch (error, stack) {
      debugPrint('=== 系统媒体卡初始化失败 ===\n$error\n$stack');
    }
  }

  // 音频会话仅移动端需要配置。
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (error, stack) {
      debugPrint('=== 音频会话初始化失败 ===\n$error\n$stack');
    }
  }

  // 性能监控（仅调试模式）
  if (kDebugMode) {
    PerformanceMonitor.enable();
  }

  runApp(const DuckMusicApp());
}
