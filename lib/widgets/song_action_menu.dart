import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api/user_api.dart';
import '../core/auth/auth_controller.dart';
import '../core/models/song.dart';
import '../core/player/player_controller.dart';
import '../core/services/song_download_service.dart';
import '../core/settings/settings_controller.dart';
import '../features/search/artist_names_link.dart';
import 'async_cover.dart';
import 'glass.dart';

class SongActionButton extends StatelessWidget {
  const SongActionButton({
    super.key,
    required this.song,
    this.onPlay,
    this.queueIndex,
  });

  final Song song;
  final FutureOr<void> Function()? onPlay;
  final int? queueIndex;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) => GIconButton(
        icon: Icons.more_horiz_rounded,
        tooltip: '更多：${song.name}',
        size: 20,
        padding: 9,
        backgroundColor: Colors.transparent,
        onTap: () => showSongActions(
          context,
          song: song,
          onPlay: onPlay,
          queueIndex: queueIndex,
          anchor: _globalRect(buttonContext),
        ),
      ),
    );
  }

  Rect? _globalRect(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
}

Future<void> showSongActions(
  BuildContext context, {
  required Song song,
  FutureOr<void> Function()? onPlay,
  int? queueIndex,
  Rect? anchor,
}) {
  final platform = Theme.of(context).platform;
  final desktop = switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux =>
      true,
    _ => false,
  };
  if (desktop && anchor != null && MediaQuery.sizeOf(context).width >= 720) {
    return showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: '关闭歌曲操作菜单',
      barrierColor: Colors.transparent,
      transitionDuration: Motion.normal,
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Motion.standard,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            alignment: Alignment.topRight,
            child: child,
          ),
        );
      },
      pageBuilder: (_, __, ___) => _DesktopSongActionRoute(
        anchor: anchor,
        child: _SongActionSheet(
          song: song,
          onPlay: onPlay,
          queueIndex: queueIndex,
          desktop: true,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _SongActionSheet(
      song: song,
      onPlay: onPlay,
      queueIndex: queueIndex,
    ),
  );
}

class _SongActionSheet extends StatefulWidget {
  const _SongActionSheet({
    required this.song,
    this.onPlay,
    this.queueIndex,
    this.desktop = false,
  });

  final Song song;
  final FutureOr<void> Function()? onPlay;
  final int? queueIndex;
  final bool desktop;

  @override
  State<_SongActionSheet> createState() => _SongActionSheetState();
}

class _SongActionSheetState extends State<_SongActionSheet> {
  final UserApi _userApi = UserApi();
  bool _liked = false;
  bool _favoriteLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_favoriteLoading) unawaited(_loadFavorite());
  }

  Future<void> _loadFavorite() async {
    final token = context.read<AuthController>().token;
    if (token == null) return;
    _favoriteLoading = true;
    try {
      final items = await _userApi.getFavorites(token);
      if (!mounted) return;
      setState(() {
        _liked = items.any((item) {
          final id = item['songId'] ?? item['id'];
          final source = item['source'] ?? 'netease';
          return id?.toString() == widget.song.id &&
              source.toString() == widget.song.source;
        });
      });
    } catch (_) {
      // 喜欢状态不影响其他歌曲操作。
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SongDownloadService.instance,
      builder: (context, _) => _buildActions(context),
    );
  }

  Widget _buildActions(BuildContext context) {
    final downloads = SongDownloadService.instance;
    final downloading = downloads.isDownloading(widget.song);
    final downloaded = downloads.isDownloaded(widget.song);
    final actions = <Widget>[
      _action(
        Icons.play_arrow_rounded,
        '播放',
        _play,
      ),
      _action(
        Icons.skip_next_rounded,
        '下一首播放',
        _playNext,
      ),
      _action(
        _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        _liked ? '取消喜欢' : '喜欢',
        _toggleFavorite,
        color: _liked ? AppBrand.favoriteRed : null,
      ),
      _action(
        Icons.playlist_add_rounded,
        '收藏到歌单',
        _addToPlaylist,
      ),
      _action(
        downloading
            ? Icons.downloading_rounded
            : downloaded
                ? Icons.download_done_rounded
                : Icons.download_rounded,
        downloading
            ? '下载中'
            : downloaded
                ? '已下载'
                : '下载',
        downloading || downloaded ? null : _download,
      ),
    ];

    if (widget.desktop) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final scheme = Theme.of(context).colorScheme;
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: ShadowToken.card(context, radius: 28, opacity: 0.24),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Material(
              color: scheme.surface.withValues(alpha: dark ? 0.90 : 0.92),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: glassHairline(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: actions,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: AsyncCover(
                url: widget.song.album.picUrl,
                size: 48,
                radius: 8,
              ),
              title: Text(
                widget.song.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: ArtistNamesLink(
                artists: widget.song.artists,
                source: widget.song.source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            ...actions,
          ],
        ),
      ),
    );
  }

  Widget _action(
    IconData icon,
    String title,
    VoidCallback? onTap, {
    Color? color,
  }) {
    return ListTile(
      minTileHeight: widget.desktop ? 48 : 50,
      contentPadding:
          widget.desktop ? const EdgeInsets.symmetric(horizontal: 18) : null,
      leading: Icon(icon, color: color, size: widget.desktop ? 21 : 24),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: widget.desktop ? 14 : null,
          fontWeight: widget.desktop ? TypeScale.medium : null,
        ),
      ),
      trailing: onTap == null
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: onTap,
    );
  }

  void _play() {
    final player = context.read<PlayerController>();
    Navigator.of(context).pop();
    final action = widget.onPlay;
    if (action != null) {
      action();
    } else {
      player.playQueue([widget.song]);
    }
  }

  void _playNext() {
    context.read<PlayerController>().playNext(
          widget.song,
          queueIndex: widget.queueIndex,
        );
    _message('已设为下一首播放');
  }

  Future<void> _toggleFavorite() async {
    final token = context.read<AuthController>().token;
    if (token == null) {
      _message('请先登录后再喜欢歌曲');
      return;
    }
    try {
      if (_liked) {
        await _userApi.removeFavorite(
          widget.song.id,
          widget.song.source,
          token,
        );
      } else {
        await _userApi.addFavorite(widget.song, token);
      }
      if (!mounted) return;
      setState(() => _liked = !_liked);
      final player = context.read<PlayerController>();
      if (player.current?.id == widget.song.id &&
          player.current?.source == widget.song.source) {
        player.setLiked(_liked);
      }
      _message(_liked ? '已加入喜欢的音乐' : '已取消喜欢');
    } catch (error) {
      _message(_errorText(error, '喜欢操作失败'));
    }
  }

  Future<void> _addToPlaylist() async {
    final token = context.read<AuthController>().token;
    if (token == null) {
      _message('请先登录后再收藏到歌单');
      return;
    }
    try {
      final playlists = await _userApi.getOwnedPlaylists(token);
      if (!mounted) return;
      final selection = await showModalBottomSheet<Object>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => _PlaylistChooser(playlists: playlists),
      );
      if (!mounted || selection == null) return;

      String? playlistId;
      String? playlistName;
      if (selection == _PlaylistChooser.createNew) {
        final name = await _createPlaylistName();
        if (!mounted || name == null) return;
        final created = await _userApi.createPlaylist(name, null, token);
        playlistId = _playlistId(created);
        playlistName = name;
      } else if (selection is Map<String, dynamic>) {
        playlistId = _playlistId(selection);
        playlistName = _playlistName(selection);
      }
      if (playlistId == null) throw Exception('歌单数据缺少 ID');
      await _userApi.addSongToPlaylist(playlistId, widget.song, token);
      _message('已收藏到歌单“${playlistName ?? '未命名歌单'}”');
    } catch (error) {
      _message(_errorText(error, '收藏到歌单失败'));
    }
  }

  Future<String?> _createPlaylistName() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '歌单名称'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    return name == null || name.isEmpty ? null : name;
  }

  Future<void> _download() async {
    try {
      final quality = context.read<SettingsController>().downloadQuality;
      final result = await SongDownloadService.instance.download(
        widget.song,
        quality: quality,
      );
      _message(result.alreadyExists ? '歌曲已在下载目录中' : '下载完成');
    } catch (error) {
      _message(_errorText(error, '下载失败'));
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _errorText(Object error, String fallback) {
    final text = error.toString().replaceFirst(RegExp(r'^Exception: '), '');
    return text.isEmpty ? fallback : text;
  }

  String? _playlistId(Map<String, dynamic> json) {
    final raw = json['id'] ?? json['playlistId'];
    if (raw != null && raw.toString().isNotEmpty) return raw.toString();
    final playlist = json['playlist'];
    return playlist is Map
        ? _playlistId(Map<String, dynamic>.from(playlist))
        : null;
  }

  String _playlistName(Map<String, dynamic> json) {
    return (json['name'] ?? json['playlistName'] ?? '未命名歌单').toString();
  }
}

class _DesktopSongActionRoute extends StatelessWidget {
  const _DesktopSongActionRoute({
    required this.anchor,
    required this.child,
  });

  static const menuWidth = 236.0;
  static const _menuHeight = 256.0;
  static const _margin = 12.0;

  final Rect anchor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxLeft = (constraints.maxWidth - menuWidth - _margin)
            .clamp(_margin, double.infinity)
            .toDouble();
        final left =
            (anchor.right - menuWidth).clamp(_margin, maxLeft).toDouble();
        final below = anchor.bottom + 6;
        final above = anchor.top - _menuHeight - 6;
        final preferredTop =
            below + _menuHeight <= constraints.maxHeight - _margin
                ? below
                : above;
        final maxTop = (constraints.maxHeight - _menuHeight - _margin)
            .clamp(_margin, double.infinity)
            .toDouble();
        final top = preferredTop.clamp(_margin, maxTop).toDouble();
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              child: child,
            ),
          ],
        );
      },
    );
  }
}

class _PlaylistChooser extends StatelessWidget {
  const _PlaylistChooser({required this.playlists});

  static const createNew = '__create_new_playlist__';
  final List<Map<String, dynamic>> playlists;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.65,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 2, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '收藏到歌单',
                style: TextStyle(fontSize: 17, fontWeight: TypeScale.bold),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('新建歌单'),
            onTap: () => Navigator.of(context).pop(createNew),
          ),
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('还没有歌单'),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return ListTile(
                    leading: const Icon(Icons.queue_music_rounded),
                    title: Text(
                      (playlist['name'] ?? playlist['playlistName'] ?? '未命名歌单')
                          .toString(),
                    ),
                    onTap: () => Navigator.of(context).pop(playlist),
                  );
                },
              ),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
