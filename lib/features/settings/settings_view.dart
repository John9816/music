import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/config/audio_quality_policy.dart';
import '../../core/player/player_controller.dart';
import '../../core/player/system_media_controller.dart';
import '../../core/services/sleep_timer.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass.dart';
import 'about_view.dart';
import 'desktop_settings_view.dart';
import 'ios_sideload_view.dart';
import 'notifications_view.dart';
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
                title: '音乐源',
                subtitle: '推荐、搜索、歌单与播放使用的数据源',
                value:
                    AppConfig.musicSources[settings.source] ?? settings.source,
                onTap: () => _pickSource(context, settings),
              ),
            ],
          ),
          const SettingsSection('外观'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.brightness_6_rounded,
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
                icon: Icons.palette_outlined,
                title: '主题色',
                subtitle: '调整强调色与界面氛围',
                value: AppAccent.byId(settings.accentId).name,
                onTap: () => _pickAccent(context, settings),
              ),
              SettingsRow(
                icon: Icons.blur_circular_rounded,
                title: '液态玻璃质量',
                subtitle: '影响导航、播放栏与弹出菜单',
                value: const {
                      'smooth': '流畅',
                      'detailed': '精细',
                      'auto': '自动',
                    }[settings.glassQuality] ??
                    '流畅',
                onTap: () => _pickGlassQuality(context, settings),
              ),
              SettingsRow(
                icon: Icons.auto_awesome_rounded,
                title: '减弱动态效果',
                subtitle: '减少封面、歌词和页面过渡动画',
                trailing: SettingsSwitch(
                  value: settings.reduceMotion,
                  onChanged: settings.setReduceMotion,
                ),
                onToggle: settings.setReduceMotion,
                toggleValue: settings.reduceMotion,
              ),
            ],
          ),
          const SettingsSection('播放与体验'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.graphic_eq_rounded,
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
                title: '存储与缓存',
                subtitle: '下载音质、缓存上限、有效期与分类清理',
                onTap: () => _open(context, const StorageSettingsView()),
              ),
              if (desktop)
                SettingsRow(
                  icon: Icons.desktop_mac_outlined,
                  title: '桌面与快捷键',
                  subtitle: '状态栏歌词、全局快捷键与窗口控制',
                  onTap: () => _open(context, const DesktopSettingsView()),
                ),
              if (Platform.isMacOS || Platform.isWindows)
                SettingsRow(
                  icon: Icons.phone_iphone_outlined,
                  title: 'iOS 安装中心',
                  subtitle: '从 ECS 获取 IPA，在本机签名、安装和刷新',
                  onTap: () => _open(context, const IosSideloadView()),
                ),
            ],
          ),
          const SettingsSection('通知与支持'),
          SettingsGroup(
            children: [
              if (Platform.isAndroid) const AndroidMediaStatusRow(),
              SettingsRow(
                icon: Icons.notifications_rounded,
                title: '通知',
                subtitle: '查看服务通知与重要公告',
                onTap: () => _open(context, const NotificationsView()),
              ),
              SettingsRow(
                icon: Icons.info_rounded,
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
      options: AppConfig.musicSources.entries
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

  Future<void> _pickAccent(
    BuildContext context,
    SettingsController settings,
  ) async {
    final value = await showSettingsPicker<String>(
      context,
      title: '主题色',
      current: settings.accentId,
      options: AppAccent.all
          .map((accent) => (value: accent.id, label: accent.name, detail: null))
          .toList(),
    );
    if (value != null) await settings.setAccentColor(value);
  }

  Future<void> _pickGlassQuality(
    BuildContext context,
    SettingsController settings,
  ) async {
    final value = await showSettingsPicker<String>(
      context,
      title: '液态玻璃质量',
      current: settings.glassQuality,
      options: const [
        (value: 'smooth', label: '流畅', detail: '省电'),
        (value: 'detailed', label: '精细', detail: null),
        (value: 'auto', label: '自动', detail: '跟随屏幕'),
      ],
    );
    if (value != null) await settings.setGlassQuality(value);
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
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '睡眠定时',
                style: TextStyle(fontSize: 17, fontWeight: TypeScale.bold),
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
            : '媒体通知未开启';
    final subtitle = _loading
        ? '正在检查通知权限'
        : _enabled == true
            ? '锁屏、通知中心和系统媒体卡可显示播放控制'
            : '开启后才能显示锁屏与通知中心的上一首、播放和下一首';
    return GPressScale(
      onTap: _loading ? null : _open,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Icon(
                  _enabled == true
                      ? Icons.multitrack_audio_rounded
                      : Icons.notifications_paused_outlined,
                  size: 20,
                  color: _enabled == true
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: TypeScale.semibold,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                Text(
                  _enabled == true ? '已开启' : '去开启',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: TypeScale.semibold,
                    color: _enabled == true
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 7),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
