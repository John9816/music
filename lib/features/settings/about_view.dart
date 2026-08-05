import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/services/app_update_service.dart';
import '../../widgets/glass.dart';
import 'settings_components.dart';

class AboutView extends StatefulWidget {
  const AboutView({super.key});

  @override
  State<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<AboutView> {
  bool _checkingUpdate = false;
  double? _downloadProgress;
  String _updateText = '点击检查新版本';
  String _serviceStatus = '检查中';

  @override
  void initState() {
    super.initState();
    _checkService();
  }

  Future<void> _checkService() async {
    if (mounted) setState(() => _serviceStatus = '检查中');
    try {
      final response = await http
          .get(Uri.parse(AppConfig.apiBaseUrl))
          .timeout(const Duration(seconds: 6));
      if (!mounted) return;
      setState(() {
        _serviceStatus = response.statusCode < 500 ? '运行正常' : '服务异常';
      });
    } catch (_) {
      if (mounted) setState(() => _serviceStatus = '暂时无法连接');
    }
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate || _downloadProgress != null) return;
    setState(() {
      _checkingUpdate = true;
      _updateText = '正在检查更新';
    });
    final service = AppUpdateService();
    final result = await service.checkLatest();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    if (result.status == UpdateCheckStatus.failed) {
      setState(() => _updateText = result.message ?? '检查更新失败');
      _message(_updateText);
      return;
    }
    final release = result.release!;
    if (result.status == UpdateCheckStatus.upToDate) {
      setState(() => _updateText = '当前暂无可用更新');
      _message('已是最新版本（${release.version}）');
      return;
    }
    setState(() => _updateText = '发现新版本 ${release.version}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('发现新版本 ${release.version}'),
        content: Text(
          release.assetUrl == null || Platform.isIOS
              ? '当前平台将打开官方发布页面继续更新。'
              : '安装包已准备好，是否立即下载？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              release.assetUrl == null || Platform.isIOS ? '打开' : '下载',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (release.assetUrl == null || Platform.isIOS) {
      final opened = await service.openReleaseDestination(release);
      if (!opened) _message('无法打开更新地址');
      return;
    }
    setState(() => _downloadProgress = 0);
    final path = await service.downloadUpdate(
      release.assetUrl!,
      onProgress: (progress) {
        if (mounted) setState(() => _downloadProgress = progress);
      },
    );
    if (!mounted) return;
    setState(() => _downloadProgress = null);
    if (path == null) {
      _message('更新包下载失败');
      return;
    }
    if (!await service.installUpdate(path)) {
      _message('无法打开系统安装器');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: GAppBar(
        title: '关于 ${AppConfig.appName}',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/branding/app_icon.png',
                width: 100,
                height: 100,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            AppConfig.appName,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: TypeScale.heavy),
          ),
          const SizedBox(height: 5),
          const Text(
            '版本 ${AppConfig.appVersion}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5),
          ),
          const SettingsSection('版本与服务'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.system_update_alt_rounded,
                title: '检查更新',
                subtitle: _downloadProgress == null
                    ? _updateText
                    : '正在下载 ${(_downloadProgress! * 100).round()}%',
                trailing: _checkingUpdate || _downloadProgress != null
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: _downloadProgress,
                        ),
                      )
                    : null,
                onTap: _checkUpdate,
              ),
              SettingsRow(
                icon: Icons.cloud_rounded,
                title: '服务状态',
                value: _serviceStatus,
                onTap: _checkService,
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            '${AppConfig.appName} 是独立开发的跨平台音乐客户端。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
