import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/music_social_api.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';

/// 从完整分享链接或裸 token 中提取 token。
String? shareTokenFromInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri != null && uri.hasScheme && text.contains('/')) {
    final segments = uri.pathSegments;
    final musicIndex = segments.indexOf('music');
    if (musicIndex >= 0 && musicIndex + 1 < segments.length) {
      return segments[musicIndex + 1];
    }
    if (segments.isNotEmpty) return segments.last;
  }
  return text;
}

/// 弹出输入框：粘贴完整分享链接或 token 后打开落地页。
void showShareInputSheet(BuildContext context) {
  final controller = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('打开分享歌曲'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '粘贴分享链接或 token',
          prefixIcon: Icon(Icons.link_rounded),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final token = shareTokenFromInput(controller.text);
            if (token == null || token.isEmpty) return;
            Navigator.of(dialogContext).pop();
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ShareSongView(token: token),
              ),
            );
          },
          child: const Text('打开'),
        ),
      ],
    ),
  );
}

/// 分享歌曲落地页：通过 token 读取公开分享快照，展示信息并提供播放入口。
/// 对应后端 GET /api/public/music/share/{token}。
class ShareSongView extends StatefulWidget {
  const ShareSongView({super.key, required this.token});

  final String token;

  @override
  State<ShareSongView> createState() => _ShareSongViewState();
}

class _ShareSongViewState extends State<ShareSongView> {
  final MusicSocialApi _api = MusicSocialApi();

  bool _loading = true;
  String? _error;
  PublicMusicShare? _share;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final share = await _api.viewShare(widget.token);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _share = share;
      });
    } on ShareExpiredException catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '分享链接已过期';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst(RegExp(r'^Exception: '), '');
      });
    }
  }

  Future<void> _play() async {
    final share = _share;
    if (share == null) return;
    final song = Song(
      id: share.songId,
      name: share.name,
      source: share.source,
      artists: share.artist.isEmpty
          ? const [Artist(id: 0, name: '未知歌手')]
          : share.artist
              .split(RegExp(r'[,/]'))
              .map((e) => Artist(id: 0, name: e.trim()))
              .where((e) => e.name.isNotEmpty)
              .toList(),
      album: Album(
        id: 0,
        name: share.album,
        picUrl: share.coverUrl,
      ),
      durationMs: (share.durationSec ?? 0) * 1000,
      availableQualities: share.requestedQuality == null
          ? const []
          : [share.requestedQuality!],
    );
    await context.read<PlayerController>().playQueue([song]);
    if (mounted) _message('已开始播放：${share.name}');
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const GAppBar(title: '分享的歌曲'),
      body: _buildBody(scheme),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_off_rounded, size: 48, color: scheme.outline),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final share = _share!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          AsyncCover(
            url: share.coverUrl,
            size: 240,
            radius: 20,
          ),
          const SizedBox(height: 24),
          Text(
            share.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            share.artist.isEmpty ? '未知歌手' : share.artist,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            share.album,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.outline),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.visibility_outlined, size: 16, color: scheme.outline),
              const SizedBox(width: 6),
              Text('已被浏览 ${share.viewCount} 次',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
            ],
          ),
          if (!share.playable && share.playError != null) ...[
            const SizedBox(height: 12),
            Text(
              '当前暂不可播放：${share.playError}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _play,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('播放这首歌'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(220, 48),
            ),
          ),
        ],
      ),
    );
  }
}
