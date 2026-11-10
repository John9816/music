import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/local_music_service.dart';
import '../../widgets/glass.dart';
import '../../widgets/song_row.dart';

class LocalMusicView extends StatefulWidget {
  const LocalMusicView({super.key});
  @override
  State<LocalMusicView> createState() => _LocalMusicViewState();
}

class _LocalMusicViewState extends State<LocalMusicView> {
  final _service = LocalMusicService.instance;
  bool _busy = false, _loaded = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _service.initialize();
      await _service.startAutomaticScan();
      if (mounted) setState(() => _loaded = true);
    } catch (_) {
      if (mounted) setState(() => _error = '本地音乐读取失败');
    }
  }

  Future<void> _scan() async {
    await _service.scanDevice(requestPermission: true);
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final files = await openFiles(acceptedTypeGroups: [
        const XTypeGroup(
            label: '音频',
            extensions: ['mp3', 'flac', 'm4a', 'aac', 'ogg', 'wav', 'opus'],
            mimeTypes: ['audio/*'],
            uniformTypeIdentifiers: ['public.audio'])
      ]);
      if (files.isNotEmpty) await _service.importFiles(files);
    } catch (_) {
      _error = '导入失败，请选择可读取的音频文件';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: GAppBar(
            title: '本地音乐',
            onBack: () => Navigator.maybePop(context),
            actions: [
              if (_service.supportsDeviceScan)
                GToolbarButton(
                    icon: Icons.refresh_rounded, tooltip: '重新扫描', onTap: _scan),
              GToolbarButton(
                  icon: Icons.add_rounded,
                  tooltip: '导入音频',
                  disabled: _busy,
                  onTap: _import),
            ]),
        body: AnimatedBuilder(
            animation: _service,
            builder: (context, _) {
              final songs = _service.songs;
              return Column(children: [
                if (_busy || _service.scanning) const LinearProgressIndicator(),
                if (_service.supportsDeviceScan)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                    child: Row(children: [
                      Icon(
                          _service.devicePermissionGranted
                              ? Icons.check_circle_outline
                              : Icons.library_music_outlined,
                          size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                              _service.scanError ??
                                  (_service.devicePermissionGranted
                                      ? '已开启自动扫描 · ${songs.length} 首歌曲'
                                      : '允许访问音乐后，自动发现设备上的歌曲'),
                              style: Theme.of(context).textTheme.bodySmall)),
                      if (!_service.devicePermissionGranted)
                        TextButton(
                            onPressed: _service.scanning ? null : _scan,
                            child: const Text('开启扫描')),
                    ]),
                  ),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.all(20), child: Text(_error!)),
                Expanded(
                    child: !_loaded && _error == null
                        ? const Center(child: CircularProgressIndicator())
                        : songs.isEmpty
                            ? GEmptyState(
                                icon: Icons.audio_file_outlined,
                                text: '把设备上的音乐带到这里',
                                actionLabel: _service.supportsDeviceScan
                                    ? '扫描本地音乐'
                                    : '导入音频',
                                onRetry: _service.supportsDeviceScan
                                    ? _scan
                                    : _import)
                            : ListView.builder(
                                itemCount: songs.length,
                                itemBuilder: (context, index) => SongRow(
                                    song: songs[index],
                                    onTap: () => context
                                        .read<PlayerController>()
                                        .playQueue(songs, index: index),
                                    trailing: IconButton(
                                        tooltip: '从本地音乐移除',
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                        onPressed: () async {
                                          final song = songs[index];
                                          final confirmed = await showDialog<
                                                  bool>(
                                              context: context,
                                              builder: (dialog) => AlertDialog(
                                                      title:
                                                          const Text('移除这首歌？'),
                                                      content: Text(song.id
                                                              .startsWith(
                                                                  'device:')
                                                          ? '从列表隐藏这首歌，设备上的原始文件会保留。'
                                                          : '仅移除应用内的副本，原始文件会保留。'),
                                                      actions: [
                                                        TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    dialog,
                                                                    false),
                                                            child: const Text(
                                                                '取消')),
                                                        TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    dialog,
                                                                    true),
                                                            child: const Text(
                                                                '移除'))
                                                      ]));
                                          if (confirmed == true) {
                                            await _service.remove(song);
                                          }
                                        })))),
              ]);
            }),
      );
}
