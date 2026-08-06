import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/sleep_timer.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass.dart';
import 'about_view.dart';
import 'desktop_settings_view.dart';
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
    final desktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

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
                subtitle: '推荐、歌单详情与播放使用的数据源；搜索会合并三源结果',
                value: AppConfig.musicSources[settings.source] ??
                    settings.source,
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
              ),
            ],
          ),
          const SettingsSection('播放与体验'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.graphic_eq_rounded,
                title: '默认播放音质',
                subtitle: '为音乐播放选择合适的音质',
                value: AppConfig.qualityLabels[settings.quality] ??
                    settings.quality,
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
            ],
          ),
          const SettingsSection('通知与支持'),
          SettingsGroup(
            children: [
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
          .map((entry) => (value: entry.key, label: entry.value))
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
        (value: 'system', label: '跟随系统'),
        (value: 'dark', label: '深色'),
        (value: 'light', label: '浅色'),
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
          .map((accent) => (value: accent.id, label: accent.name))
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
        (value: 'smooth', label: '流畅'),
        (value: 'detailed', label: '精细'),
        (value: 'auto', label: '自动'),
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
      title: '默认播放音质',
      current: settings.quality,
      options: AppConfig.qualityLabels.entries
          .map((entry) => (value: entry.key, label: entry.value))
          .toList(),
    );
    if (value != null) await settings.setQuality(value);
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
