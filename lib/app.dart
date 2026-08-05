import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:provider/provider.dart';

import 'core/auth/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/player/player_controller.dart';
import 'core/services/cache_service.dart';
import 'core/services/desktop_integration_service.dart';
import 'core/services/sleep_timer.dart';
import 'core/settings/settings_controller.dart';
import 'features/home/home_shell.dart';
import 'features/profile/login_view.dart';
import 'features/search/search_view.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class DuckMusicApp extends StatefulWidget {
  const DuckMusicApp({super.key});

  @override
  State<DuckMusicApp> createState() => _DuckMusicAppState();
}

class _DuckMusicAppState extends State<DuckMusicApp> {
  late final SettingsController _settings;
  late final PlayerController _player;
  late final DesktopIntegrationService _desktopIntegration;

  @override
  void initState() {
    super.initState();
    _settings = SettingsController();
    _player = PlayerController(settings: _settings);
    _desktopIntegration = DesktopIntegrationService(
      settings: _settings,
      player: _player,
      onOpenSearch: () {
        appNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const SearchView()),
        );
      },
    );
    unawaited(_settings.load().then((_) async {
      await CacheService.instance.maintainAudioCache(_settings);
      await _desktopIntegration.initialize();
    }));
  }

  @override
  void dispose() {
    _desktopIntegration.dispose();
    _player.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider.value(value: _player),
        ChangeNotifierProvider.value(value: _desktopIntegration),
        ChangeNotifierProvider(create: (_) => AuthController()..load()),
        ChangeNotifierProvider(create: (_) => SleepTimer()),
      ],
      child: const _ThemeBridge(),
    );
  }
}

/// 监听主题变化，同步切换毛玻璃明暗（macOS / Windows 生效）。
/// 只在初始化与主题真正变化时调用一次平台效果，避免每次 build 重复触发。
class _ThemeBridge extends StatefulWidget {
  const _ThemeBridge();

  @override
  State<_ThemeBridge> createState() => _ThemeBridgeState();
}

class _ThemeBridgeState extends State<_ThemeBridge> {
  bool? _lastAppliedDark;

  void _applyEffect(SettingsController settings) {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    try {
      // Windows 用 Acrylic 模糊；macOS 用 sidebar 侧边栏材质
      final effect =
          Platform.isWindows ? WindowEffect.acrylic : WindowEffect.sidebar;
      Window.setEffect(
        effect: effect,
        dark: _effectiveDark(settings),
      );
    } catch (_) {}
  }

  bool _effectiveDark(SettingsController settings) {
    if (settings.themeMode == ThemeMode.dark) return true;
    if (settings.themeMode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final effectiveDark = _effectiveDark(settings);
    if ((Platform.isMacOS || Platform.isWindows) &&
        _lastAppliedDark != effectiveDark) {
      _lastAppliedDark = effectiveDark;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyEffect(settings);
      });
    }
    return MaterialApp(
      title: AppConfig.appName,
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: settings.lightTheme.data,
      darkTheme: settings.darkTheme.data,
      themeMode: settings.themeMode,
      scrollBehavior: const _NoScrollbarBehavior(),
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final mediaQuery = MediaQuery.of(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          ),
          child: MediaQuery(
            data: mediaQuery.copyWith(
              disableAnimations:
                  settings.reduceMotion || mediaQuery.disableAnimations,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const AuthGate(),
    );
  }
}

/// 等待本地会话恢复后再创建首页，避免音乐请求早于 Token 注入。
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (!auth.initialized) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (!auth.isLoggedIn) return const LoginView(allowBack: false);
    return const HomeShell();
  }
}

/// 移除 macOS 上 RawScrollbar（内含 MouseRegion）以规避鼠标断言卡死。
/// macOS 用户主要使用触控板滚动，不需要覆盖滚动条。
class _NoScrollbarBehavior extends ScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child; // 不包裹 Scrollbar → 无 RawScrollbar → 无 MouseRegion
  }

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child; // 移除 overscroll glow，风格更贴近原生 macOS
  }
}
