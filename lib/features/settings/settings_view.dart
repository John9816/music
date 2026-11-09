import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/config/audio_quality_policy.dart';
import '../../core/player/player_controller.dart';
import '../../core/player/system_media_controller.dart';
import '../../core/services/sleep_timer.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/glass.dart';
import 'about_view.dart';
import 'qishui_account_view.dart';
import 'desktop_settings_view.dart';
import 'ios_sideload_view.dart';
import 'lyric_settings_view.dart';
import 'settings_components.dart';
import 'storage_settings_view.dart';

/// 统一设置入口，承载从“我的”中移出的偏好与支持功能。
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final sleepTimer = context.watch<SleepTimer>();
    final desktop = Platform.isMacOS || Platform.isWindows;

    return Scaffold(
      appBar: GAppBar(
        title: '设置',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          const SettingsSection('通用'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.language_rounded,
                iconColor: const Color(0xFF30A9D8),
                title: '音乐源',
                subtitle: '首页推荐与发现使用的数据源；搜索独立选择',
                value:
                    AppConfig.musicSources[settings.source] ?? settings.source,
                onTap: () => _pickSource(context, settings),
              ),
            ],
          ),
          const SettingsSection('音乐账号'),
          SettingsGroup(children: [
            SettingsRow(
                icon: Icons.account_circle_outlined,
                title: '黑源账号',
                subtitle: '汽水音乐扫码绑定与授权管理',
                onTap: () => _open(context, const QishuiAccountView()))
          ]),
          const SettingsSection('外观'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.brightness_6_rounded,
                iconColor: const Color(0xFF625BE8),
                title: '深浅模式',
                subtitle: '深色、浅色或跟随系统',
                value: const {
                      'system': '跟随系统',
                      'dark': '深色',
                      'light': '浅色',
                    }[settings.themeModeId] ??
                    '跟随系统',
                onTap: () => _pickThemeMode(context, settings),
              ),
              SettingsRow(
                icon: Icons.text_fields_rounded,
                iconColor: const Color(0xFF818188),
                title: '歌词显示',
                subtitle: '字体大小、字形样式与实时预览',
                value:
                    '${settings.lyricFontSize} · ${settings.lyricFontStyle.label}',
                onTap: () => _open(context, const LyricSettingsView()),
              ),
            ],
          ),
          const SettingsSection('播放与体验'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.graphic_eq_rounded,
                iconColor: const Color(0xFFF5A000),
                title: '默认播放音质',
                subtitle:
                    '${sourceDisplayName(settings.source)}${qualitySupportSummary(settings.source)}',
                value: qualityLabelForSource(
                  settings.source,
                  settings.qualityForSource(settings.source),
                ),
                onTap: () => _pickQuality(context, settings),
              ),
              SettingsRow(
                icon: Icons.timer_outlined,
                iconColor: const Color(0xFF5C78D3),
                title: '睡眠定时',
                subtitle: sleepTimer.isActive
                    ? '剩余 ${sleepTimer.displayText}，点击可重新设置'
                    : '到点后自动暂停播放',
                value: sleepTimer.isActive ? '已开启' : null,
                onTap: () => _showSleepTimerPicker(context),
              ),
            ],
          ),
          const SettingsSection('存储与设备'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.inventory_2_outlined,
                iconColor: const Color(0xFF8E8E93),
                title: '存储与缓存',
                subtitle: '下载音质、缓存上限、有效期与分类清理',
                onTap: () => _open(context, const StorageSettingsView()),
              ),
              if (Theme.of(context).platform == TargetPlatform.android)
                SettingsRow(
                  icon: Icons.directions_car_rounded,
                  title: '车载模式',
                  subtitle: '适合车机直装的大按钮界面；Android Auto 自动使用系统界面',
                  trailing: SettingsSwitch(
                    value: settings.carModeEnabled,
                    onChanged: settings.setCarModeEnabled,
                  ),
                  onToggle: settings.setCarModeEnabled,
                  toggleValue: settings.carModeEnabled,
                ),
              if (desktop)
                SettingsRow(
                  icon: Icons.desktop_mac_outlined,
                  iconColor: const Color(0xFF4C98D5),
                  title: '桌面与快捷键',
                  subtitle: '状态栏歌词、全局快捷键与窗口控制',
                  onTap: () => _open(context, const DesktopSettingsView()),
                ),
              if (Platform.isMacOS || Platform.isWindows)
                SettingsRow(
                  icon: Icons.phone_iphone_outlined,
                  iconColor: const Color(0xFF5A6AB8),
                  title: 'iOS 安装中心',
                  subtitle: '从 ECS 获取 IPA，在本机签名、安装和刷新',
                  onTap: () => _open(context, const IosSideloadView()),
                ),
            ],
          ),
          const SettingsSection('通知与支持'),
          SettingsGroup(
            children: [
              if (Theme.of(context).platform == TargetPlatform.android)
                const AndroidMediaStatusRow(),
              SettingsRow(
                icon: Icons.info_rounded,
                iconColor: Theme.of(context).colorScheme.primary,
                title: '关于 ${AppConfig.appName}',
                subtitle: '版本、更新与服务状态',
                onTap: () => _open(context, const AboutView()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickSource(
    BuildContext context,
    SettingsController settings,
  ) async {
    final value = await showSettingsPicker<String>(
      context,
      title: '选择音乐源',
      current: settings.source,
      options: AppConfig.browsingMusicSources.entries
          .map((entry) => (value: entry.key, label: entry.value, detail: null))
          .toList(),
    );
    if (value != null) await settings.setSource(value);
  }

  Future<void> _pickThemeMode(
    BuildContext context,
    SettingsController settings,
  ) async {
    final value = await showSettingsPicker<String>(
      context,
      title: '显示模式',
      current: settings.themeModeId,
      options: const [
        (value: 'system', label: '跟随系统', detail: null),
        (value: 'dark', label: '深色', detail: null),
        (value: 'light', label: '浅色', detail: null),
      ],
    );
    if (value != null) await settings.setThemeMode(value);
  }

  Future<void> _pickQuality(
    BuildContext context,
    SettingsController settings,
  ) async {
    final value = await showSettingsPicker<String>(
      context,
      title: '${sourceDisplayName(settings.source)}播放音质',
      current: settings.qualityForSource(settings.source),
      options: qualityOptionsForSource(settings.source)
          .map((option) =>
              (value: option.id, label: option.label, detail: option.detail))
          .toList(),
    );
    if (value != null) {
      await settings.setQualityForSource(settings.source, value);
    }
  }

  Future<void> _showSleepTimerPicker(BuildContext context) async {
    final player = context.read<PlayerController>();
    final timer = context.read<SleepTimer>();
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle(
        duration: PlatformMotion.duration(context, Motion.normal),
        reverseDuration: PlatformMotion.duration(context, Motion.normal),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '睡眠定时',
                  style:
                      TextStyle(fontSize: 18, fontWeight: TypeScale.semibold),
                ),
              ),
              GListTile(
                leading: const Icon(Icons.timer_off_rounded),
                title: const Text('取消定时'),
                selected: !timer.isActive,
                onTap: () {
                  timer.stop();
                  Navigator.of(sheetContext).pop();
                },
              ),
              for (final minutes in [15, 30, 45, 60, 90])
                GListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text('$minutes 分钟后暂停'),
                  onTap: () {
                    timer.start(
                      Duration(minutes: minutes),
                      onTimeout: player.pause,
                    );
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => page),
    );
  }
}

class AndroidMediaStatusRow extends StatefulWidget {
  const AndroidMediaStatusRow({super.key});

  @override
  State<AndroidMediaStatusRow> createState() => _AndroidMediaStatusRowState();
}

class _AndroidMediaStatusRowState extends State<AndroidMediaStatusRow>
    with WidgetsBindingObserver {
  bool? _enabled;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await SystemMediaController.androidNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
    });
  }

  Future<void> _open() async {
    await SystemMediaController.openAndroidNotificationSettings();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _loading
        ? '检查媒体控制'
        : _enabled == true
            ? '媒体通知已开启'
            : _enabled == false
                ? '媒体通知未开启'
                : '媒体通知';
    final subtitle = _loading
        ? '正在检查通知权限'
        : _enabled == true
            ? '歌曲、歌手、封面与播放控制会同步到系统媒体卡；灵动岛展示由系统决定'
            : '管理系统媒体通知、锁屏与悬浮展示；不同手机的入口可能不同';
    return SettingsRow(
      icon: _enabled == true
          ? Icons.multitrack_audio_rounded
          : Icons.notifications_paused_outlined,
      iconColor: _enabled == true ? scheme.primary : const Color(0xFF8E8E93),
      title: title,
      subtitle: subtitle,
      value: _loading ? null : (_enabled == true ? '已开启' : '去开启'),
      trailing: _loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _loading ? null : _open,
    );
  }
}
