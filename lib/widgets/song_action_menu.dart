import 'dart:async';
import 'dart:math' as math;
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
    this.onRemove,
    this.removeLabel = '从歌单移除',
    this.showFavoriteAction = true,
  });

  final Song song;
  final FutureOr<void> Function()? onPlay;
  final int? queueIndex;
  final FutureOr<void> Function()? onRemove;
  final String removeLabel;
  final bool showFavoriteAction;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) => GIconButton(
        icon: Icons.more_vert_rounded,
        tooltip: '更多：${song.name}',
        size: 20,
        padding: 9,
        backgroundColor: Colors.transparent,
        onTap: () => showSongActions(
          context,
          song: song,
          onPlay: onPlay,
          queueIndex: queueIndex,
          onRemove: onRemove,
          removeLabel: removeLabel,
          showFavoriteAction: showFavoriteAction,
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
  FutureOr<void> Function()? onRemove,
  String removeLabel = '从歌单移除',
  bool showFavoriteAction = true,
  bool downloadOnly = false,
  Rect? anchor,
}) {
  // App overlays use the complete app palette, outside the player's local
  // artwork theme, whose light container surfaces may be left unchanged.
  final overlayContext = Navigator.of(context, rootNavigator: true).context;
  final platform = Theme.of(context).platform;
  final desktop = switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux =>
      true,
    _ => false,
  };
  if (anchor != null) {
    return showGeneralDialog<void>(
      context: overlayContext,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: '关闭歌曲操作菜单',
      barrierColor: Colors.transparent,
      transitionDuration: PlatformMotion.duration(context, Motion.normal),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return _SongMenuTransition(animation: animation, child: child);
      },
      pageBuilder: (_, __, ___) => _AnchoredSongActionRoute(
        anchor: anchor,
        child: _SongActionSheet(
          song: song,
          onPlay: onPlay,
          queueIndex: queueIndex,
          onRemove: onRemove,
          removeLabel: removeLabel,
          showFavoriteAction: showFavoriteAction,
          downloadOnly: downloadOnly,
          desktop: desktop,
          anchored: true,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: overlayContext,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    sheetAnimationStyle: AnimationStyle(
      duration: PlatformMotion.duration(context, Motion.normal),
      reverseDuration: PlatformMotion.duration(context, Motion.normal),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: _SongActionSheet(
        song: song,
        onPlay: onPlay,
        queueIndex: queueIndex,
        onRemove: onRemove,
        removeLabel: removeLabel,
        showFavoriteAction: showFavoriteAction,
        downloadOnly: downloadOnly,
      ),
    ),
  );
}

class _SongMenuTransition extends StatefulWidget {
  const _SongMenuTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_SongMenuTransition> createState() => _SongMenuTransitionState();
}

class _SongMenuTransitionState extends State<_SongMenuTransition> {
  late CurvedAnimation _curve;

  void _createCurve() {
    _curve = CurvedAnimation(
      parent: widget.animation,
      curve: Motion.standard,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    _createCurve();
  }

  @override
  void didUpdateWidget(_SongMenuTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _curve.dispose();
      _createCurve();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(_curve),
          alignment: Alignment.topRight,
          child: widget.child,
        ),
      );
}

class _SongActionSheet extends StatefulWidget {
  const _SongActionSheet({
    required this.song,
    this.onPlay,
    this.queueIndex,
    this.onRemove,
    this.removeLabel = '从歌单移除',
    this.showFavoriteAction = true,
    this.desktop = false,
    this.anchored = false,
    this.downloadOnly = false,
  });

  final Song song;
  final FutureOr<void> Function()? onPlay;
  final int? queueIndex;
  final FutureOr<void> Function()? onRemove;
  final String removeLabel;
  final bool showFavoriteAction;
  final bool desktop;
  final bool anchored;
  final bool downloadOnly;

  @override
  State<_SongActionSheet> createState() => _SongActionSheetState();
}

class _SongActionSheetState extends State<_SongActionSheet> {
  final UserApi _userApi = UserApi();
  bool _liked = false;
  bool _favoriteRequested = false;
  bool _favoriteLoading = false;
  bool _playlistBusy = false;
  bool _playlistLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.song.source != 'local' &&
        !_favoriteRequested &&
        widget.showFavoriteAction &&
        !widget.downloadOnly) {
      _favoriteRequested = true;
      unawaited(_loadFavorite());
    }
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
    } finally {
      if (mounted) setState(() => _favoriteLoading = false);
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
    final scheme = Theme.of(context).colorScheme;
    final actions = <Widget>[
      if (!widget.downloadOnly) ...[
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
        if (widget.showFavoriteAction && widget.song.source != 'local')
          _action(
            _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            _liked ? '取消喜欢' : '喜欢',
            _favoriteLoading ? null : _toggleFavorite,
            color: _liked ? AppBrand.favoriteRed : null,
            loading: _favoriteLoading,
          ),
        if (widget.song.source != 'local')
          _action(
            Icons.playlist_add_rounded,
            '收藏到歌单',
            _playlistBusy ? null : _addToPlaylist,
            loading: _playlistLoading,
          ),
      ],
      if (widget.song.source == 'local')
        const Padding(padding: EdgeInsets.all(20), child: Text('这首歌曲已保存在本地音乐中'))
      else
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
          loading: downloading,
          downloaded: downloaded,
        ),
      if (!widget.downloadOnly && widget.onRemove != null) ...[
        const Divider(indent: 12, endIndent: 12),
        _action(
          Icons.remove_circle_outline_rounded,
          widget.removeLabel,
          () {
            final remove = widget.onRemove!;
            Navigator.of(context).pop();
            remove();
          },
          color: scheme.error,
        ),
      ],
    ];

    if (widget.anchored) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final scheme = Theme.of(context).colorScheme;
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: ShadowToken.card(
            context,
            radius: 24,
            opacity: dark ? 0.22 : 0.10,
          ),
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
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!widget.desktop) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.song.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: TypeScale.semibold)),
                              const SizedBox(height: 4),
                              ArtistNamesLink(
                                artists: widget.song.artists,
                                source: widget.song.source,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        const Divider(indent: 12, endIndent: 12),
                      ],
                      ...actions,
                    ],
                  ),
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
    bool loading = false,
    bool downloaded = false,
  }) {
    return ListTile(
      minTileHeight: widget.desktop ? 48 : 50,
      contentPadding:
          widget.desktop ? const EdgeInsets.symmetric(horizontal: 18) : null,
      leading: Icon(icon,
          color: color ?? Theme.of(context).colorScheme.onSurface,
          size: widget.desktop ? 21 : 24),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: widget.desktop ? 14 : 16,
          fontWeight: TypeScale.regular,
        ),
      ),
      trailing: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : downloaded
              ? Icon(Icons.check_rounded,
                  size: 18, color: Theme.of(context).colorScheme.primary)
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
    if (_favoriteLoading) return;
    final token = context.read<AuthController>().token;
    if (token == null) {
      _message('请先登录后再喜欢歌曲');
      return;
    }
    setState(() => _favoriteLoading = true);
    final nextLiked = !_liked;
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
      setState(() => _liked = nextLiked);
      final player = context.read<PlayerController>();
      if (player.current?.id == widget.song.id &&
          player.current?.source == widget.song.source) {
        player.setLiked(_liked);
      }
      _message(_liked ? '已加入喜欢的音乐' : '已取消喜欢');
    } catch (error) {
      _message(_errorText(error, '喜欢操作失败'));
    } finally {
      if (mounted) setState(() => _favoriteLoading = false);
    }
  }

  Future<void> _addToPlaylist() async {
    if (_playlistBusy) return;
    final token = context.read<AuthController>().token;
    if (token == null) {
      _message('请先登录后再收藏到歌单');
      return;
    }
    setState(() {
      _playlistBusy = true;
      _playlistLoading = true;
    });
    try {
      final playlists = await _userApi.getOwnedPlaylists(token);
      if (!mounted) return;
      setState(() => _playlistLoading = false);
      final selection = await showModalBottomSheet<Object>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        showDragHandle: true,
        sheetAnimationStyle: AnimationStyle(
          duration: PlatformMotion.duration(context, Motion.normal),
          reverseDuration: PlatformMotion.duration(context, Motion.normal),
        ),
        builder: (context) => _PlaylistChooser(playlists: playlists),
      );
      if (!mounted || selection == null) return;

      String? playlistId;
      String? playlistName;
      if (selection == _PlaylistChooser.createNew) {
        final name = await _createPlaylistName();
        if (!mounted || name == null) return;
        setState(() => _playlistLoading = true);
        final created = await _userApi.createPlaylist(name, null, token);
        playlistId = _playlistId(created);
        playlistName = name;
      } else if (selection is Map<String, dynamic>) {
        playlistId = _playlistId(selection);
        playlistName = _playlistName(selection);
      }
      if (playlistId == null) throw Exception('歌单数据缺少 ID');
      if (mounted) setState(() => _playlistLoading = true);
      await _userApi.addSongToPlaylist(playlistId, widget.song, token);
      _message('已收藏到歌单“${playlistName ?? '未命名歌单'}”');
    } catch (error) {
      _message(_errorText(error, '收藏到歌单失败'));
    } finally {
      if (mounted) {
        setState(() {
          _playlistBusy = false;
          _playlistLoading = false;
        });
      }
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

class _AnchoredSongActionRoute extends StatelessWidget {
  const _AnchoredSongActionRoute({required this.anchor, required this.child});

  final Rect anchor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    return CustomSingleChildLayout(
      delegate: _SongMenuLayout(
        anchor,
        EdgeInsets.fromLTRB(
          math.max(padding.left, insets.left),
          math.max(padding.top, insets.top),
          math.max(padding.right, insets.right),
          math.max(padding.bottom, insets.bottom),
        ),
      ),
      child: child,
    );
  }
}

/// Measure the menu before positioning it: large text can grow or scroll
/// without placing an action outside the safe area.
class _SongMenuLayout extends SingleChildLayoutDelegate {
  const _SongMenuLayout(this.anchor, this.safePadding);

  final Rect anchor;
  final EdgeInsets safePadding;
  static const margin = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.min(
        280.0, constraints.maxWidth - safePadding.horizontal - margin * 2);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(
          0, constraints.maxHeight - safePadding.vertical - margin * 2),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final minLeft = safePadding.left + margin;
    final maxLeft = math.max(
        minLeft, size.width - safePadding.right - childSize.width - margin);
    final minTop = safePadding.top + margin;
    final maxTop = math.max(
        minTop, size.height - safePadding.bottom - childSize.height - margin);
    final below = anchor.bottom + 6;
    final top = below <= maxTop ? below : anchor.top - childSize.height - 6;
    return Offset((anchor.right - childSize.width).clamp(minLeft, maxLeft),
        top.clamp(minTop, maxTop));
  }

  @override
  bool shouldRelayout(_SongMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor || safePadding != oldDelegate.safePadding;
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
                style: TextStyle(fontSize: 18, fontWeight: TypeScale.semibold),
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

/// Direct playlist entry shared by the player's plus button.
Future<void> showAddSongToPlaylist(BuildContext context,
    {required Song song}) async {
  final token = context.read<AuthController>().token;
  final messenger = ScaffoldMessenger.of(context);
  if (token == null) {
    messenger.showSnackBar(const SnackBar(content: Text('请先登录后再收藏到歌单')));
    return;
  }
  try {
    final api = UserApi();
    final playlists = await api.getOwnedPlaylists(token);
    if (!context.mounted) return;
    final overlayContext = Navigator.of(context, rootNavigator: true).context;
    final selection = await showModalBottomSheet<Object>(
        context: overlayContext,
        useRootNavigator: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _PlaylistChooser(playlists: playlists));
    if (!context.mounted || !overlayContext.mounted || selection == null) {
      return;
    }
    Map<String, dynamic>? selected;
    String? name;
    if (selection == _PlaylistChooser.createNew) {
      name = await showDialog<String>(
          context: overlayContext, builder: (_) => const _NewPlaylistDialog());
      if (!context.mounted || name == null) return;
      selected = await api.createPlaylist(name, null, token);
    } else if (selection is Map<String, dynamic>) {
      selected = selection;
      name = (selection['name'] ?? selection['playlistName'])?.toString();
    }
    final nested = selected?['playlist'];
    final id = selected?['id'] ??
        selected?['playlistId'] ??
        (nested is Map ? nested['id'] : null);
    if (id == null) throw Exception('歌单数据缺少 ID');
    await api.addSongToPlaylist(id.toString(), song, token);
    if (context.mounted) {
      messenger
          .showSnackBar(SnackBar(content: Text('已收藏到歌单“${name ?? '未命名歌单'}”')));
    }
  } catch (_) {
    if (context.mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('收藏到歌单失败，请重试')));
    }
  }
}

class _NewPlaylistDialog extends StatefulWidget {
  const _NewPlaylistDialog();
  @override
  State<_NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<_NewPlaylistDialog> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void submit() {
    if (input.text.trim().isNotEmpty) Navigator.pop(context, input.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('新建歌单'),
          content: TextField(
              controller: input,
              autofocus: true,
              decoration: const InputDecoration(hintText: '歌单名称'),
              onSubmitted: (_) => submit()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(onPressed: submit, child: const Text('创建'))
          ]);
}
