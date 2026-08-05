import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../core/config/app_config.dart';
import '../../core/services/cache_service.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/glass.dart';
import 'settings_components.dart';

class StorageSettingsView extends StatefulWidget {
  const StorageSettingsView({super.key});

  @override
  State<StorageSettingsView> createState() => _StorageSettingsViewState();
}

class _StorageSettingsViewState extends State<StorageSettingsView> {
  CacheSnapshot? _snapshot;
  int _downloadBytes = 0;
  String _downloadPath = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final results = await Future.wait<Object>([
      CacheService.instance.snapshot(),
      CacheService.instance.downloadsSizeBytes(),
      CacheService.instance.downloadsDirectory,
    ]);
    if (!mounted) return;
    setState(() {
      _snapshot = results[0] as CacheSnapshot;
      _downloadBytes = results[1] as int;
      _downloadPath = (results[2] as Directory).path;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final snapshot = _snapshot;
    return Scaffold(
      appBar: GAppBar(
        title: '存储与缓存',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.inventory_2_outlined,
                title: '缓存占用',
                subtitle: settings.audioCacheLimitBytes == 0
                    ? '自动清理'
                    : '达到上限后清理最早使用的歌曲',
                value: _loading
                    ? '计算中'
                    : CacheService.formatBytes(snapshot?.totalBytes ?? 0),
              ),
            ],
          ),
          const SettingsSection('自动管理'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.music_note_rounded,
                title: '自动缓存歌曲',
                subtitle: '播放时保存完整音频，关闭后直接在线播放',
                trailing: SettingsSwitch(
                  value: settings.automaticAudioCache,
                  onChanged: settings.setAutomaticAudioCache,
                ),
              ),
              SettingsRow(
                icon: Icons.inventory_rounded,
                title: '歌曲缓存上限',
                subtitle: '达到上限后自动清理最早使用的歌曲',
                value: _cacheLimitLabel(settings.audioCacheLimitBytes),
                onTap: () => _pickCacheLimit(settings),
              ),
              SettingsRow(
                icon: Icons.schedule_rounded,
                title: '歌曲缓存有效期',
                subtitle: '从缓存生成时间开始计算，过期后自动清理',
                value: '${settings.audioCacheValidityDays} 天',
                onTap: () => _pickValidity(settings),
              ),
            ],
          ),
          const SettingsSection('下载'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.music_note_rounded,
                title: '下载音质',
                subtitle: '新任务使用此音质，已下载歌曲不会改变',
                value: _downloadQualityLabel(settings.downloadQuality),
                onTap: () => _pickDownloadQuality(settings),
              ),
              SettingsRow(
                icon: Icons.folder_outlined,
                title: '在文件管理器中显示',
                subtitle: _downloadPath.isEmpty ? '正在准备下载目录' : _downloadPath,
                onTap: _openDownloads,
              ),
              SettingsRow(
                icon: Icons.download_for_offline_outlined,
                title: '已下载占用',
                subtitle: '不计入歌曲缓存上限',
                value: CacheService.formatBytes(_downloadBytes),
              ),
              SettingsRow(
                icon: Icons.delete_outline_rounded,
                title: '清空全部下载',
                subtitle: '删除已下载歌曲、歌词和未完成任务',
                destructive: true,
                onTap: _downloadBytes > 0 ? _clearDownloads : null,
              ),
            ],
          ),
          const SettingsSection('占用空间'),
          SettingsGroup(
            children: [
              _categoryRow(CacheCategory.songs, '歌曲缓存', Icons.audio_file),
              _categoryRow(CacheCategory.images, '图片缓存', Icons.image_outlined),
              _categoryRow(CacheCategory.lyrics, '歌词缓存', Icons.lyrics_outlined),
              _categoryRow(
                  CacheCategory.pageData, '页面数据', Icons.storage_outlined),
            ],
          ),
          const SettingsSection('清理'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.delete_sweep_outlined,
                title: '清除全部缓存',
                subtitle: '不会删除下载内容、收藏、歌单或账号数据',
                destructive: true,
                onTap: snapshot != null && snapshot.totalBytes > 0
                    ? _clearAllCache
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _categoryRow(CacheCategory category, String title, IconData icon) {
    final bytes = _snapshot?.bytesFor(category) ?? 0;
    return SettingsRow(
      icon: icon,
      title: title,
      value: CacheService.formatBytes(bytes),
      trailing: bytes > 0
          ? GIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: '清理$title',
              size: 18,
              padding: 7,
              tint: Theme.of(context).colorScheme.error,
              onTap: () => _clearCategory(category, title),
            )
          : null,
    );
  }

  Future<void> _pickCacheLimit(SettingsController settings) async {
    const mb = 1024 * 1024;
    final value = await showSettingsPicker<int>(
      context,
      title: '歌曲缓存上限',
      current: settings.audioCacheLimitBytes,
      options: const [
        (value: 0, label: '自动管理'),
        (value: 512 * mb, label: '512 MB'),
        (value: 1024 * mb, label: '1 GB'),
        (value: 2 * 1024 * mb, label: '2 GB'),
        (value: 5 * 1024 * mb, label: '5 GB'),
        (value: 10 * 1024 * mb, label: '10 GB'),
        (value: 20 * 1024 * mb, label: '20 GB'),
      ],
    );
    if (value == null) return;
    await settings.setAudioCacheLimitBytes(value);
    await CacheService.instance.maintainAudioCache(settings);
    await _reload();
  }

  Future<void> _pickValidity(SettingsController settings) async {
    final value = await showSettingsPicker<int>(
      context,
      title: '歌曲缓存有效期',
      current: settings.audioCacheValidityDays,
      options: const [
        (value: 7, label: '7 天'),
        (value: 30, label: '30 天'),
        (value: 90, label: '90 天'),
      ],
    );
    if (value == null) return;
    await settings.setAudioCacheValidityDays(value);
    await CacheService.instance.maintainAudioCache(settings);
    await _reload();
  }

  Future<void> _pickDownloadQuality(SettingsController settings) async {
    final value = await showSettingsPicker<String>(
      context,
      title: '下载音质',
      current: settings.downloadQuality,
      options: [
        const (value: 'follow', label: '跟随播放音质'),
        ...AppConfig.qualityLabels.entries
            .where((entry) => entry.key != 'auto')
            .map((entry) => (value: entry.key, label: entry.value)),
      ],
    );
    if (value != null) await settings.setDownloadQuality(value);
  }

  Future<void> _openDownloads() async {
    if (_downloadPath.isEmpty) return;
    final uri = Uri.directory(_downloadPath);
    if (!await launcher.launchUrl(
      uri,
      mode: launcher.LaunchMode.externalApplication,
    )) {
      _message('无法打开下载目录');
    }
  }

  Future<void> _clearCategory(CacheCategory category, String title) async {
    if (!await _confirm('清理$title？', '该分类的缓存文件会被永久删除。')) return;
    await CacheService.instance.clearCategory(category);
    await _reload();
    _message('$title已清理');
  }

  Future<void> _clearAllCache() async {
    if (!await _confirm('清除全部缓存？', '下载、收藏、歌单和账号数据不会受到影响。')) return;
    await CacheService.instance.clearAll();
    await _reload();
    _message('全部缓存已清理');
  }

  Future<void> _clearDownloads() async {
    if (!await _confirm('清空全部下载？', '已下载歌曲、歌词和未完成任务会被永久删除。')) return;
    await CacheService.instance.clearDownloads();
    await _reload();
    _message('下载内容已清空');
  }

  Future<bool> _confirm(String title, String content) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _cacheLimitLabel(int bytes) => bytes == 0
      ? '自动管理'
      : CacheService.formatBytes(bytes).replaceAll('.0 ', ' ');

  String _downloadQualityLabel(String value) =>
      value == 'follow' ? '跟随播放音质' : AppConfig.qualityLabels[value] ?? value;
}
