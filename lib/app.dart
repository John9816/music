import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:provider/provider.dart';

import 'core/auth/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/player/player_controller.dart';
import 'core/player/app_playback_runtime.dart';
import 'core/player/system_media_controller.dart';
import 'core/services/cache_service.dart';
import 'core/services/desktop_integration_service.dart';
import 'core/services/ios_sideload_service.dart';
import 'core/services/sleep_timer.dart';
import 'core/services/song_download_service.dart';
import 'core/settings/settings_controller.dart';
import 'features/home/home_shell.dart';
import 'features/profile/login_view.dart';
import 'features/search/search_view.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class DuckMusicApp extends StatefulWidget {
  const DuckMusicApp({super.key, required this.runtime});
  final AppPlaybackRuntime runtime;

  @override
  State<DuckMusicApp> createState() => _DuckMusicAppState();
}

class _DuckMusicAppState extends State<DuckMusicApp>
    with WidgetsBindingObserver {
  late final SettingsController _settings;
  late final PlayerController _player;
  late final AuthController _auth;
  late final DesktopIntegrationService _desktopIntegration;
  late final IosSideloadService _iosSideload;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings = widget.runtime.settings;
    _player = widget.runtime.player;
    _auth = widget.runtime.auth;
    _iosSideload = IosSideloadService(stateStore: FileIosSideloadStateStore());
    unawaited(SongDownloadService.instance.initialize());
    _desktopIntegration = DesktopIntegrationService(
      settings: _settings,
      player: _player,
      onOpenSearch: () {
        appNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const SearchView()),
        );
      },
    );
    unawaited(widget.runtime.ready.then((_) async {
      if (!mounted) return;
      await CacheService.instance.maintainAudioCache(_settings);
      await _desktopIntegration.initialize();
      await _iosSideload.autoRefreshIfNeeded();
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _desktopIntegration.dispose();
    _iosSideload.dispose();
    widget.runtime.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      unawaited(
        SystemMediaController.instance.refreshAndroidNotificationPermission(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider.value(value: _player),
        ChangeNotifierProvider.value(value: _desktopIntegration),
        ChangeNotifierProvider.value(value: SongDownloadService.instance),
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: widget.runtime.library),
        ChangeNotifierProvider.value(value: widget.runtime.roaming),
        ChangeNotifierProvider(create: (_) => SleepTimer()),
        ChangeNotifierProvider.value(value: _iosSideload),
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
      scrollBehavior: const DuckMusicScrollBehavior(),
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final mobile = Platform.isAndroid || Platform.isIOS;
        final mediaQuery = MediaQuery.of(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            // Mobile devices use gesture navigation and edge-to-edge layout.
            // Keep the app surface visible behind the home indicator/nav
            // gesture area; SafeArea still keeps controls out of that inset.
            systemNavigationBarColor: mobile
                ? Colors.transparent
                : Theme.of(context).scaffoldBackgroundColor,
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          ),
          child: MediaQuery(
            data: mediaQuery.copyWith(
              disableAnimations: mediaQuery.disableAnimations,
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
class AuthGate extends StatefulWidget {
  const AuthGate(
      {super.key, this.restoreTimeout = const Duration(seconds: 10)});

  final Duration restoreTimeout;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Timer? _timeoutTimer;
  bool _timedOut = false;
  bool _skipRestore = false;

  @override
  void initState() {
    super.initState();
    _startTimeout();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(widget.restoreTimeout, () {
      if (mounted && !context.read<AuthController>().initialized) {
        setState(() => _timedOut = true);
      }
    });
  }

  void _retry() {
    setState(() {
      _timedOut = false;
      _skipRestore = false;
    });
    _startTimeout();
    unawaited(context.read<AuthController>().load());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (auth.isLoggedIn) {
      _timeoutTimer?.cancel();
      return const HomeShell();
    }
    if (!auth.initialized && !_skipRestore) {
      if (_timedOut) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 38,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '登录状态恢复超时',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '网络连接可能不稳定。你可以重新加载，或直接进入登录页。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          key: const ValueKey('auth-restore-retry'),
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重新加载'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const ValueKey('auth-restore-skip'),
                        onPressed: () => setState(() => _skipRestore = true),
                        child: const Text('直接登录'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
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
    _timeoutTimer?.cancel();
    if (!auth.isLoggedIn) return const LoginView(allowBack: false);
    return const HomeShell();
  }
}

/// Windows/Linux 保留桌面滚动位置反馈；macOS 避免 RawScrollbar 内部的
/// MouseRegion 触发已知 MouseTracker 断言，移动端也不显示常驻滚动条。
class DuckMusicScrollBehavior extends ScrollBehavior {
  const DuckMusicScrollBehavior();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux) {
      return Scrollbar(controller: details.controller, child: child);
    }
    return child;
  }

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child; // 移除 overscroll glow，风格更贴近原生 macOS
  }
}
