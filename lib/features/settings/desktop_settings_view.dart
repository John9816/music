import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:provider/provider.dart';

import '../../core/services/desktop_integration_service.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/glass.dart';
import 'settings_components.dart';

class DesktopSettingsView extends StatelessWidget {
  const DesktopSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final integration = context.watch<DesktopIntegrationService>();
    final desktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    return Scaffold(
      appBar: GAppBar(
        title: '桌面与快捷键',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: [
          const SettingsSection('状态栏歌词'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.lyrics_outlined,
                title: '状态栏歌词',
                subtitle: Platform.isMacOS
                    ? '播放时在菜单栏显示当前歌词，点击可唤回主窗口'
                    : '该功能当前在 macOS 上可用',
                trailing: SettingsSwitch(
                  value: settings.statusBarLyrics,
                  onChanged: Platform.isMacOS
                      ? settings.setStatusBarLyrics
                      : (_) => _message(context, '状态栏歌词当前仅支持 macOS'),
                ),
              ),
            ],
          ),
          const SettingsSection('全局快捷键'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.keyboard_outlined,
                title: '启用全局快捷键',
                subtitle: desktop ? '系统媒体键仍由系统媒体会话处理' : '当前平台不支持系统级快捷键',
                trailing: SettingsSwitch(
                  value: settings.globalShortcutsEnabled,
                  onChanged: desktop
                      ? settings.setGlobalShortcutsEnabled
                      : (_) => _message(context, '当前平台不支持全局快捷键'),
                ),
              ),
              for (final spec in playbackShortcutSpecs)
                _shortcutRow(context, spec, settings, integration),
            ],
          ),
          const SettingsSection('窗口与歌词'),
          SettingsGroup(
            children: [
              for (final spec in windowShortcutSpecs)
                _shortcutRow(context, spec, settings, integration),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shortcutRow(
    BuildContext context,
    DesktopShortcutSpec spec,
    SettingsController settings,
    DesktopIntegrationService integration,
  ) {
    final raw = settings.shortcutBindings[spec.id];
    final error = integration.errorFor(spec.id);
    return SettingsRow(
      icon: _iconFor(spec.id),
      title: spec.title,
      subtitle: error ?? spec.subtitle,
      value: raw == null ? '未设置' : _bindingLabel(raw),
      onTap: integration.supported
          ? () => _record(context, spec, settings, raw, integration)
          : null,
    );
  }

  Future<void> _record(
    BuildContext context,
    DesktopShortcutSpec spec,
    SettingsController settings,
    String? raw,
    DesktopIntegrationService integration,
  ) async {
    HotKey? initial;
    if (raw != null) {
      try {
        initial = HotKey.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } catch (_) {}
    }
    HotKey? recorded = initial;
    final result = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('设置${spec.title}'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(spec.subtitle),
                const SizedBox(height: 18),
                Container(
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: glassHairline(context)),
                  ),
                  child: HotKeyRecorder(
                    initalHotKey: initial,
                    onHotKeyRecorded: (hotKey) {
                      recorded = HotKey(
                        key: hotKey.key,
                        modifiers: hotKey.modifiers,
                        scope: HotKeyScope.system,
                      );
                      setDialogState(() {});
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '请按下至少包含一个修饰键的组合键',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (initial != null)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('clear'),
                child: const Text('清除'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed:
                  recorded == null || (recorded!.modifiers?.isEmpty ?? true)
                      ? null
                      : () => Navigator.of(dialogContext).pop(recorded),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == 'clear') {
      await settings.setShortcutBinding(spec.id, null);
      return;
    }
    if (result is! HotKey) return;
    await settings.setShortcutBinding(
      spec.id,
      jsonEncode(result.toJson()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!context.mounted) return;
    final error = integration.errorFor(spec.id);
    _message(context, error ?? '${spec.title}快捷键已生效');
  }

  String _bindingLabel(String raw) {
    try {
      final hotKey = HotKey.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      return hotKey.debugName
          .replaceAll('Meta', Platform.isMacOS ? '⌘' : 'Win')
          .replaceAll('Control', Platform.isMacOS ? '⌃' : 'Ctrl')
          .replaceAll('Alt', Platform.isMacOS ? '⌥' : 'Alt')
          .replaceAll('Shift', Platform.isMacOS ? '⇧' : 'Shift');
    } catch (_) {
      return '未设置';
    }
  }

  IconData _iconFor(String id) => switch (id) {
        'playPause' => Icons.play_arrow_rounded,
        'previous' => Icons.skip_previous_rounded,
        'next' => Icons.skip_next_rounded,
        'volumeUp' => Icons.volume_up_rounded,
        'volumeDown' => Icons.volume_down_rounded,
        'mute' => Icons.volume_off_rounded,
        'favorite' => Icons.favorite_border_rounded,
        'loop' => Icons.repeat_rounded,
        'shuffle' => Icons.shuffle_rounded,
        'window' => Icons.web_asset_rounded,
        'search' => Icons.search_rounded,
        _ => Icons.lyrics_outlined,
      };

  static void _message(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
