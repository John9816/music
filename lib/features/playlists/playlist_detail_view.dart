import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/music_api.dart';
import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../../widgets/song_action_menu.dart';
import '../search/artist_names_link.dart';

/// Desktop playlist detail matching the persistent sidebar/player shell.
class PlaylistDetailView extends StatefulWidget {
  const PlaylistDetailView({
    super.key,
    required this.playlist,
    this.loader,
    this.userApi,
  });

  final Playlist playlist;

  /// Custom loader used by charts; regular playlists use playlist/detail.
  final Future<List<Song>> Function()? loader;

  /// Tests and previews can supply a deterministic account API.
  final UserApi? userApi;

  @override
  State<PlaylistDetailView> createState() => _PlaylistDetailViewState();
}

class _PlaylistDetailViewState extends State<PlaylistDetailView> {
  final MusicApi _api = MusicApi();
  late UserApi _userApi;
  late Future<List<Song>> _future;
  Future<List<Song>>? _loadingFuture;
  bool _isFavorite = false;
  bool _favoriteLoading = false;
  bool _isAdded = false;
  bool _descriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    _userApi = widget.userApi ?? UserApi();
    _future = _startLoad();
    unawaited(_loadFavoriteState());
  }

  @override
  void didUpdateWidget(covariant PlaylistDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.id != widget.playlist.id) {
      _isFavorite = false;
      _favoriteLoading = false;
      _isAdded = false;
      _descriptionExpanded = false;
      _loadingFuture = null;
      _reload();
      unawaited(_loadFavoriteState());
    }
  }

  Future<List<Song>> _load() async {
    if (widget.loader != null) return widget.loader!();
    return _api.getPlaylistDetail(
      widget.playlist.id,
      source: _playlistSource(),
    );
  }

  Future<List<Song>> _startLoad() {
    final existing = _loadingFuture;
    if (existing != null) return existing;

    final future = _load();
    _loadingFuture = future;
    future.then<void>(
      (_) {
        if (identical(_loadingFuture, future)) _loadingFuture = null;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_loadingFuture, future)) _loadingFuture = null;
      },
    );
    return future;
  }

  void _reload() {
    if (!mounted) return;
    final future = _startLoad();
    if (identical(_future, future)) return;
    setState(() => _future = future);
  }

  Future<void> _loadFavoriteState() async {
    final token = context.read<AuthController>().token;
    if (token == null) return;
    try {
      final source = _playlistSource();
      final status = await _userApi.getPlaylistFavoriteStatus(
        source,
        widget.playlist.id.toString(),
        token,
      );
      if (!mounted) return;
      setState(() {
        _isFavorite = status['favorite'] == true;
        _isAdded = _isFavorite;
      });
    } catch (_) {
      // 收藏状态查询失败不影响歌单详情加载。
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteLoading) return;
    final token = context.read<AuthController>().token;
    if (token == null) {
      _showMessage('请先登录后再收藏歌单');
      return;
    }
    setState(() => _favoriteLoading = true);
    try {
      if (_isFavorite) {
        await _userApi.removePlaylistFavorite(
          _playlistSource(),
          widget.playlist.id.toString(),
          token,
        );
        if (!mounted) return;
        setState(() {
          _isFavorite = false;
          _isAdded = false;
        });
        _showMessage('已取消收藏');
      } else {
        await _userApi.addPlaylistFavorite(
          _playlistSource(),
          widget.playlist.id.toString(),
          token,
        );
        if (!mounted) return;
        setState(() {
          _isFavorite = true;
          _isAdded = true;
        });
        _showMessage('歌单已收藏');
      }
    } catch (error) {
      _showMessage(_errorText(error, _isFavorite ? '取消收藏失败' : '收藏歌单失败'));
    } finally {
      if (mounted) setState(() => _favoriteLoading = false);
    }
  }

  /// “加入我的歌单”和顶部收藏使用同一份线上歌单收藏记录。
  /// 保留独立入口是为了兼容参考布局，但不能只更新本地 UI 状态。
  Future<void> _toggleAdded() async {
    await _toggleFavorite();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
        ),
      );
  }

  String _errorText(Object error, String fallback) {
    final text = error.toString().replaceFirst(RegExp(r'^Exception: '), '');
    return text.isEmpty ? fallback : text;
  }

  String _playlistSource() {
    final source = widget.playlist.source?.trim();
    return source == null || source.isEmpty
        ? context.read<SettingsController>().source
        : source;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _PlaylistTopBar(
        title: widget.playlist.name,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: FutureBuilder<List<Song>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.only(top: 56),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.only(top: 56),
              child: GEmptyState(
                icon: Icons.error_outline_rounded,
                text: '加载失败，请检查网络后重试',
                onRetry: _reload,
              ),
            );
          }

          final songs = snapshot.data ?? const <Song>[];
          return LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 720;
              final horizontal = desktop ? 20.0 : 18.0;
              return CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      desktop ? 70 : 74,
                      horizontal,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _PlaylistHeader(
                        playlist: widget.playlist,
                        songs: songs,
                        desktop: desktop,
                        isFavorite: _isFavorite,
                        favoriteLoading: _favoriteLoading,
                        isAdded: _isAdded,
                        descriptionExpanded: _descriptionExpanded,
                        onFavorite: _toggleFavorite,
                        onAdd: _toggleAdded,
                        onToggleDescription: () => setState(
                          () => _descriptionExpanded = !_descriptionExpanded,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      desktop ? 16 : 28,
                      horizontal,
                      12,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        '歌曲',
                        style: TextStyle(
                          fontSize: desktop ? 20 : 24,
                          fontWeight: TypeScale.bold,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                  if (songs.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: GEmptyState(
                        icon: Icons.queue_music_rounded,
                        text: '歌单为空',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: horizontal),
                      sliver: SliverList.builder(
                        itemCount: songs.length,
                        itemBuilder: (context, index) => _PlaylistSongRow(
                          index: index,
                          song: songs[index],
                          desktop: desktop,
                          onTap: () => context
                              .read<PlayerController>()
                              .playQueue(songs, index: index),
                          songs: songs,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 30)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PlaylistTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _PlaylistTopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final windowControlsInset = macOSWindowControlsInset(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor.withValues(
                  alpha: dark ? 0.72 : 0.78,
                ),
            border: Border(
              bottom: BorderSide(color: glassHairline(context)),
            ),
          ),
          child: Row(
            children: [
              SizedBox(width: 4 + windowControlsInset),
              GIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: '返回',
                size: 20,
                padding: 14,
                backgroundColor: Colors.transparent,
                onTap: onBack,
              ),
              const SizedBox(width: 19),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: TypeScale.semibold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader({
    required this.playlist,
    required this.songs,
    required this.desktop,
    required this.isFavorite,
    required this.favoriteLoading,
    required this.isAdded,
    required this.descriptionExpanded,
    required this.onFavorite,
    required this.onAdd,
    required this.onToggleDescription,
  });

  final Playlist playlist;
  final List<Song> songs;
  final bool desktop;
  final bool isFavorite;
  final bool favoriteLoading;
  final bool isAdded;
  final bool descriptionExpanded;
  final VoidCallback onFavorite;
  final VoidCallback onAdd;
  final VoidCallback onToggleDescription;

  @override
  Widget build(BuildContext context) {
    final coverSize = desktop ? 200.0 : 128.0;
    final cover = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(desktop ? 20 : 18),
        boxShadow: ShadowToken.cover(context, radius: desktop ? 18 : 22),
      ),
      child: AsyncCover(
        url: playlist.coverUrl,
        size: coverSize,
        radius: desktop ? 20 : 18,
      ),
    );
    final information = _HeaderInformation(
      playlist: playlist,
      songs: songs,
      descriptionExpanded: descriptionExpanded,
      showDescription: desktop,
      onToggleDescription: onToggleDescription,
    );
    final actions = _HeaderActions(
      songs: songs,
      desktop: desktop,
      isFavorite: isFavorite,
      favoriteLoading: favoriteLoading,
      isAdded: isAdded,
      onFavorite: onFavorite,
      onAdd: onAdd,
    );

    if (!desktop) {
      final description = playlist.description?.trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover,
              const SizedBox(width: 16),
              Expanded(child: information),
            ],
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 14),
            _PlaylistDescription(
              description: description,
              expanded: descriptionExpanded,
              onToggle: onToggleDescription,
            ),
          ],
          const SizedBox(height: 18),
          actions,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cover,
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  information,
                  const SizedBox(height: 20),
                  actions,
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 64),
      ],
    );
  }
}

class _HeaderInformation extends StatelessWidget {
  const _HeaderInformation({
    required this.playlist,
    required this.songs,
    required this.descriptionExpanded,
    required this.showDescription,
    required this.onToggleDescription,
  });

  final Playlist playlist;
  final List<Song> songs;
  final bool descriptionExpanded;
  final bool showDescription;
  final VoidCallback onToggleDescription;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final creator = playlist.creatorName?.trim();
    final description = playlist.description?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '歌单',
          style: TextStyle(
            color: scheme.primary,
            fontSize: 12,
            fontWeight: TypeScale.bold,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          playlist.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: TypeScale.heavy,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          creator == null || creator.isEmpty ? '${songs.length} 首歌曲' : creator,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        if (showDescription &&
            description != null &&
            description.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PlaylistDescription(
            description: description,
            expanded: descriptionExpanded,
            onToggle: onToggleDescription,
          ),
        ],
      ],
    );
  }
}

class _PlaylistDescription extends StatelessWidget {
  const _PlaylistDescription({
    required this.description,
    required this.expanded,
    required this.onToggle,
  });

  final String description;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: Motion.normal,
          curve: Motion.standard,
          alignment: Alignment.topLeft,
          child: Text(
            description,
            maxLines: expanded ? null : 3,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 8),
        GPressScale(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  expanded ? '收起' : '展开全部',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: TypeScale.semibold,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderActions extends StatelessWidget {
  const _HeaderActions({
    required this.songs,
    required this.desktop,
    required this.isFavorite,
    required this.favoriteLoading,
    required this.isAdded,
    required this.onFavorite,
    required this.onAdd,
  });

  final List<Song> songs;
  final bool desktop;
  final bool isFavorite;
  final bool favoriteLoading;
  final bool isAdded;
  final VoidCallback onFavorite;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (desktop)
          SizedBox(
            width: 315,
            child: _PlayAllButton(
              enabled: songs.isNotEmpty,
              compact: true,
              onTap: () => context.read<PlayerController>().playQueue(songs),
            ),
          )
        else
          Expanded(
            child: _PlayAllButton(
              enabled: songs.isNotEmpty,
              onTap: () => context.read<PlayerController>().playQueue(songs),
            ),
          ),
        SizedBox(width: desktop ? 8 : 10),
        _CircleAction(
          icon: isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_outline_rounded,
          color: isFavorite ? AppBrand.favoriteRed : null,
          compact: desktop,
          loading: favoriteLoading,
          tooltip: isFavorite ? '取消收藏' : '收藏歌单',
          onTap: favoriteLoading ? null : onFavorite,
        ),
        SizedBox(width: desktop ? 6 : 8),
        _CircleAction(
          icon: isAdded
              ? Icons.playlist_add_check_rounded
              : Icons.playlist_add_rounded,
          color: isAdded ? scheme.primary : null,
          compact: desktop,
          tooltip: isAdded ? '从我的歌单移除' : '加入我的歌单',
          onTap: onAdd,
        ),
      ],
    );
  }
}

class _PlayAllButton extends StatelessWidget {
  const _PlayAllButton({
    required this.enabled,
    required this.onTap,
    this.compact = false,
  });

  final bool enabled;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      disabled: !enabled,
      onTap: onTap,
      child: Container(
        height: compact ? 32 : 40,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: enabled ? 1 : 0.4),
          borderRadius: BorderRadius.circular(compact ? 12 : 13),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow_rounded,
              size: compact ? 17 : 20,
              color: Colors.white,
            ),
            const SizedBox(width: 5),
            Text(
              '全部播放',
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 13 : 15,
                fontWeight: TypeScale.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.compact = false,
    this.loading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final bool compact;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GPressScale(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: glassFill(context, alpha: 0.08),
          ),
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: compact ? 16 : 19,
                  height: compact ? 16 : 19,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  icon,
                  size: compact ? 21 : 25,
                  color: color ?? scheme.onSurface,
                ),
        ),
      ),
    );
  }
}

class _PlaylistSongRow extends StatelessWidget {
  const _PlaylistSongRow({
    required this.index,
    required this.song,
    required this.desktop,
    required this.onTap,
    required this.songs,
  });

  final int index;
  final Song song;
  final bool desktop;
  final VoidCallback onTap;
  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: desktop ? 65 : 65,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Divider(
              height: 1,
              thickness: 1,
              color: glassHairline(context),
            ),
          ),
          Row(
            children: [
              SizedBox(
                width: desktop ? 27 : 34,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: desktop ? 12 : 13,
                    fontWeight: TypeScale.medium,
                  ),
                ),
              ),
              Expanded(
                child: GPressScale(
                  onTap: onTap,
                  scale: 0.99,
                  child: SizedBox(
                    height: desktop ? 64 : 64,
                    child: Row(
                      children: [
                        if (desktop) const SizedBox(width: 6),
                        AsyncCover(
                          url: song.album.picUrl,
                          size: desktop ? 46 : 46,
                          radius: desktop ? 9 : 10,
                        ),
                        SizedBox(width: desktop ? 12 : 13),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: desktop ? 14 : 15,
                                  fontWeight: TypeScale.semibold,
                                  height: 1.15,
                                ),
                              ),
                              SizedBox(height: desktop ? 2 : 4),
                              ArtistNamesLink(
                                artists: song.artists,
                                source: song.source,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: desktop ? 13 : 13,
                                  color: scheme.onSurfaceVariant,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SongActionButton(
                song: song,
                onPlay: () => context.read<PlayerController>().playQueue(
                      songs,
                      index: index,
                    ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ],
      ),
    );
  }
}
