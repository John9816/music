import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/app_update_service.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/sleep_timer.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass.dart';

/// 设置页：音乐源 / 主题 / 睡眠定时 / 缓存 / 更新
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  int _cacheBytes = -1;
  String? _latestVersion;
  bool _checkingUpdate = false;
  double _downloadProgress = -1;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final bytes = await CacheService.instance.totalSizeBytes();
    if (mounted) setState(() => _cacheBytes = bytes);
  }

  Future<void> _clearCache() async {
    await CacheService.instance.clearAll();
    if (mounted) {
      setState(() => _cacheBytes = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存已清理')),
      );
    }
  }

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    final service = AppUpdateService();
    final result = await service.checkLatest();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);

    if (result.status == UpdateCheckStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? '检查更新失败')),
      );
      return;
    }

    final release = result.release!;
    setState(() => _latestVersion = release.version);
    if (result.status == UpdateCheckStatus.upToDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已是最新版本（${release.version}）')),
      );
      return;
    }

    final mobileStore = AppUpdateService.currentTarget == UpdateTarget.ios;
    final downloadUrl = release.assetUrl;
    if (mobileStore || downloadUrl == null) {
      final action = mobileStore && AppConfig.iosAppStoreId.isNotEmpty
          ? '前往 App Store'
          : '打开下载页';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('发现新版本 ${release.version}'),
          content: Text(
            mobileStore ? 'iOS 更新由 App Store 安装。' : '当前发布未提供此平台的安装包，可前往发布页查看。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('稍后'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(action),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        final opened = await service.openReleaseDestination(release);
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开更新地址')),
          );
        }
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text('${release.version} 可用，是否下载并安装？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('下载'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _downloadProgress = 0);
    final filePath = await service.downloadUpdate(
      downloadUrl,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      },
    );
    if (!mounted || filePath == null) {
      if (mounted) {
        setState(() => _downloadProgress = -1);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载失败')),
        );
      }
      return;
    }

    setState(() => _downloadProgress = -1);
    final installed = await service.installUpdate(filePath);
    if (!installed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开系统安装器，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final sleepTimer = context.watch<SleepTimer>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GAppBar(
        title: '设置',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _Section('通用'),
          GListTile(
            leading: const Icon(Icons.language),
            title: const Text('音乐源'),
            subtitle: Text(
              '${AppConfig.musicSources[settings.source] ?? settings.source}'
              ' (${settings.source})',
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _pick<String>(
              title: '选择音乐源',
              current: settings.source,
              options: AppConfig.musicSources.entries
                  .map((e) => (value: e.key, label: '${e.value} (${e.key})'))
                  .toList(),
              onSelected: settings.setSource,
            ),
          ),
          GListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题'),
            subtitle: Text(settings.theme.name),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _pick<String>(
              title: '选择主题',
              current: settings.theme.id,
              options: AppTheme.all
                  .map((t) => (value: t.id, label: t.name))
                  .toList(),
              onSelected: settings.setTheme,
            ),
          ),
          const Divider(),
          const _Section('播放'),
          GListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: const Text('音质'),
            subtitle: Text(
              AppConfig.qualityValues[settings.quality] ?? settings.quality,
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _pick<String>(
              title: '选择音质',
              current: settings.quality,
              options: AppConfig.qualityValues.entries
                  .map((e) => (value: e.key, label: e.value))
                  .toList(),
              onSelected: settings.setQuality,
            ),
          ),
          GListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('睡眠定时'),
            subtitle: Text(
              sleepTimer.isActive
                  ? '剩余 ${sleepTimer.displayText}，点击取消'
                  : '到点后自动暂停播放',
            ),
            trailing: sleepTimer.isActive
                ? GButton(
                    label: '取消',
                    filled: false,
                    onTap: sleepTimer.stop,
                  )
                : const Icon(Icons.chevron_right, size: 18),
            onTap: () => _showSleepTimerPicker(context),
          ),
          const Divider(),
          const _Section('存储'),
          GListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('缓存管理'),
            subtitle: Text(
              _cacheBytes < 0
                  ? '计算中…'
                  : '当前缓存 ${CacheService.formatBytes(_cacheBytes)}',
            ),
            trailing: _cacheBytes > 0
                ? GButton(label: '清理', filled: false, onTap: _clearCache)
                : null,
          ),
          const Divider(),
          const _Section('关于'),
          GListTile(
            leading: const Icon(Icons.system_update_alt),
            title: const Text('检查更新'),
            subtitle: Text(
              _downloadProgress >= 0
                  ? '正在下载 ${(_downloadProgress * 100).round()}%'
                  : _latestVersion != null
                      ? '线上版本：$_latestVersion'
                      : '当前版本：${AppConfig.appVersion}',
            ),
            trailing: _checkingUpdate || _downloadProgress >= 0
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: _downloadProgress >= 0 ? _downloadProgress : null,
                    ),
                  )
                : const Icon(Icons.chevron_right, size: 18),
            onTap:
                _checkingUpdate || _downloadProgress >= 0 ? null : _checkUpdate,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              '柒伍壹壹音乐 v${AppConfig.appVersion} · Flutter 跨平台版\n'
              '一套代码覆盖 iOS / Android / macOS / Windows\n'
              '基于 just_audio 播放 | 数据源：api.751152.xyz',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  void _showSleepTimerPicker(BuildContext context) {
    final player = context.read<PlayerController>();
    final timer = context.read<SleepTimer>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xE61A1A1A)
          : const Color(0xE6FFFFFF),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '睡眠定时',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            GListTile(
              leading: const Icon(Icons.timer_off),
              title: const Text('取消定时'),
              onTap: () {
                timer.stop();
                Navigator.of(sheetCtx).pop();
              },
            ),
            for (final minutes in [15, 30, 45, 60, 90])
              GListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text('$minutes 分钟后暂停'),
                onTap: () {
                  timer.start(
                    Duration(minutes: minutes),
                    onTimeout: () => player.pause(),
                  );
                  Navigator.of(sheetCtx).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pick<T>({
    required String title,
    required T current,
    required List<({T value, String label})> options,
    required Future<void> Function(T) onSelected,
  }) async {
    final selected = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xE61A1A1A)
          : const Color(0xE6FFFFFF),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            for (final option in options)
              GListTile(
                selected: option.value == current,
                title: Text(option.label),
                trailing: option.value == current
                    ? Icon(Icons.check,
                        color: Theme.of(sheetCtx).colorScheme.primary)
                    : null,
                onTap: () => Navigator.of(sheetCtx).pop(option.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) await onSelected(selected);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
