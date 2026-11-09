import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/music_api.dart';
import '../../core/config/app_config.dart';
import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/song_download_service.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../../widgets/song_action_menu.dart';
import '../../widgets/song_row.dart';
import '../../core/utils/image_cache_manager.dart';
import '../search/artist_names_link.dart';

enum PlaylistDetailKind { playlist, album }

/// Desktop playlist detail matching the persistent sidebar/player shell.
class PlaylistDetailView extends StatefulWidget {
  const PlaylistDetailView({
    super.key,
    required this.playlist,
    this.kind = PlaylistDetailKind.playlist,
    this.loader,
    this.userApi,
    this.musicApi,
  });

  final Playlist playlist;
  final PlaylistDetailKind kind;

  /// Custom loader used by charts; regular playlists use playlist/detail.
  final Future<List<Song>> Function()? loader;

  /// Tests and previews can supply a deterministic account API.
  final UserApi? userApi;
  final MusicApi? musicApi;

  @override
  State<PlaylistDetailView> createState() => _PlaylistDetailViewState();
}

class _PlaylistDetailViewState extends State<PlaylistDetailView> {
  late final MusicApi _api;
  List<Song> _pagedSongs = [];
  int _nextOffset = 0;
  int _loadGeneration = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  String? _moreError;
  bool get _paged =>
      widget.loader == null && AppConfig.isQishui(_playlistSource());
  late UserApi _userApi;
  late Future<List<Song>> _future;
  Future<List<Song>>? _loadingFuture;
  bool _isFavorite = false;
  bool _favoriteLoading = false;
  bool _isAdded = false;
  bool _descriptionExpanded = false;
  bool _searchOpen = false;
  String _searchQuery = '';
  bool _mobileTitleVisible = false;
  bool _mobilePlayHeaderPinned = false;
  bool _reverseOrder = false;
  bool _downloadAllBusy = false;
  final ScrollController _mobileScrollController = ScrollController();
  final GlobalKey _mobileHeroKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _api = widget.musicApi ?? MusicApi();
    _userApi = widget.userApi ?? UserApi();
    _future = _startLoad();
    _mobileScrollController.addListener(_updateMobileTitle);
    _mobileScrollController.addListener(_onPageScroll);
    if (_supportsPlaylistFavorites) unawaited(_loadFavoriteState());
  }

  @override
  void dispose() {
    _mobileScrollController
      ..removeListener(_updateMobileTitle)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlaylistDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.detailId != widget.playlist.detailId ||
        oldWidget.playlist.source != widget.playlist.source ||
        oldWidget.kind != widget.kind) {
      _isFavorite = false;
      _favoriteLoading = false;
      _isAdded = false;
      _descriptionExpanded = false;
      _searchOpen = false;
      _searchQuery = '';
      _mobileTitleVisible = false;
      _mobilePlayHeaderPinned = false;
      _reverseOrder = false;
      _loadingFuture = null;
      _reload();
      if (_supportsPlaylistFavorites) unawaited(_loadFavoriteState());
    }
  }

  bool get _supportsPlaylistFavorites =>
      widget.kind == PlaylistDetailKind.playlist;

  Future<List<Song>> _load() async {
    if (widget.loader != null) return widget.loader!();
    if (_paged) {
      final generation = ++_loadGeneration;
      _hasMore = false;
      _loadingMore = false;
      _moreError = null;
      final page = await _api.getPlaylistPage(widget.playlist.detailId,
          source: _playlistSource());
      if (mounted && generation == _loadGeneration) {
        _pagedSongs = page.songs;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        WidgetsBinding.instance.addPostFrameCallback((_) => _onPageScroll());
      }
      return page.songs;
    }
    return _api.getPlaylistDetail(
      widget.playlist.id,
      source: _playlistSource(),
    );
  }

  void _onPageScroll() {
    if (!mounted ||
        !_paged ||
        !_mobileScrollController.hasClients ||
        _moreError != null) {
      return;
    }
    if (_mobileScrollController.position.extentAfter < 600) _loadMore();
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    final generation = _loadGeneration;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await _api.getPlaylistPage(widget.playlist.detailId,
          source: _playlistSource(), offset: _nextOffset);
      if (!mounted || generation != _loadGeneration) return;
      final songs = {for (final s in _pagedSongs) '${s.source}:${s.id}': s};
      final before = songs.length;
      for (final s in page.songs) {
        songs['${s.source}:${s.id}'] = s;
      }
      setState(() {
        _pagedSongs = songs.values.toList();
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore && songs.length > before;
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _moreError = error.toString());
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Widget _pagingFooter() => SliverToBoxAdapter(
      child: !_paged
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                  child: _loadingMore
                      ? const CircularProgressIndicator()
                      : _moreError != null
                          ? TextButton(
                              onPressed: _loadMore,
                              child: const Text('加载更多失败，点击重试'))
                          : _hasMore
                              ? TextButton(
                                  onPressed: _loadMore,
                                  child: const Text('继续加载'))
                              : Text('已加载 ${_pagedSongs.length} 首'))));

  Future<List<Song>> _startLoad() {
    final existing = _loadingFuture;
    if (existing != null) return existing;

    final future = _load();
    _loadingFuture = future;
    future.then<void>(
      (songs) {
        if (identical(_loadingFuture, future)) {
          _loadingFuture = null;
          // 预加载前10个封面
          if (songs.isNotEmpty) {
            final coverUrls = songs.map((s) => s.album.picUrl).toList();
            ImageCacheManager.preloadCovers(coverUrls, limit: 10);
          }
        }
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
    if (!_supportsPlaylistFavorites) return;
    final token = context.read<AuthController>().token;
    if (token == null) return;
    try {
      final source = _playlistSource();
      final status = await _userApi.getPlaylistFavoriteStatus(
        source,
        widget.playlist.detailId,
        token,
      );
      if (!mounted || !_supportsPlaylistFavorites) return;
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
          widget.playlist.detailId,
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
          widget.playlist.detailId,
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

  void _updateMobileTitle() {
    final hero = _mobileHeroKey.currentContext?.findRenderObject();
    if (hero is! RenderBox || !hero.hasSize) return;
    final pinned = _mobileScrollController.hasClients &&
        _mobileScrollController.offset >= hero.size.height - GToolbar.height;
    if ((pinned != _mobileTitleVisible || pinned != _mobilePlayHeaderPinned) &&
        mounted) {
      setState(() {
        _mobileTitleVisible = pinned;
        _mobilePlayHeaderPinned = pinned;
      });
    }
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) _searchQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < GBreakpoints.sidebar) {
      return _buildMobile(context);
    }
    return _buildDesktop(context);
  }

  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _PlaylistTopBar(
        title: widget.playlist.name,
        onBack: () => Navigator.of(context).maybePop(),
        searchOpen: _searchOpen,
        onSearch: _toggleSearch,
        onSearchChanged: (value) => setState(() => _searchQuery = value),
        onMore: _showMoreActions,
      ),
      body: FutureBuilder<List<Song>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(
              padding: EdgeInsets.only(
                  top: GToolbar.height + MediaQuery.paddingOf(context).top),
              child: const GSkeletonList(itemCount: 8),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: EdgeInsets.only(
                  top: GToolbar.height + MediaQuery.paddingOf(context).top),
              child: GEmptyState(
                icon: Icons.error_outline_rounded,
                text: '加载失败，请检查网络后重试',
                onRetry: _reload,
              ),
            );
          }

          final allSongs = _paged &&
                  snapshot.connectionState == ConnectionState.done &&
                  !snapshot.hasError
              ? _pagedSongs
              : snapshot.data ?? const <Song>[];
          final query = _searchQuery.trim().toLowerCase();
          final songs = query.isEmpty
              ? allSongs
              : allSongs
                  .where((song) =>
                      song.name.toLowerCase().contains(query) ||
                      song.artistNames.toLowerCase().contains(query))
                  .toList(growable: false);
          return LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 720;
              final horizontal = desktop ? 20.0 : 18.0;
              return CustomScrollView(
                controller: _mobileScrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      (desktop ? 78 : 82) + MediaQuery.paddingOf(context).top,
                      horizontal,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _PlaylistHeader(
                        playlist: widget.playlist,
                        kind: widget.kind,
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
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: GEmptyState(
                        icon: Icons.queue_music_rounded,
                        text: widget.kind == PlaylistDetailKind.album
                            ? '专辑中没有歌曲'
                            : '歌单为空',
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
                  _pagingFooter(),
                  const SliverToBoxAdapter(child: SizedBox(height: 30)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final mobileScheme = Theme.of(context).colorScheme;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateMobileTitle();
    });
    return Scaffold(
      backgroundColor: mobileScheme.surfaceContainerLowest,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _PlaylistAmbientBackground(),
          SafeArea(
            bottom: false,
            child: FutureBuilder<List<Song>>(
              future: _future,
              builder: (context, snapshot) {
                final loadedSongs = _paged &&
                        snapshot.connectionState == ConnectionState.done &&
                        !snapshot.hasError
                    ? _pagedSongs
                    : snapshot.data ?? const <Song>[];
                final query = _searchQuery.trim().toLowerCase();
                var visibleSongs = query.isEmpty
                    ? loadedSongs
                    : loadedSongs
                        .where(
                          (song) =>
                              song.name.toLowerCase().contains(query) ||
                              song.artistNames.toLowerCase().contains(query) ||
                              song.album.name.toLowerCase().contains(query),
                        )
                        .toList(growable: false);
                if (_reverseOrder) {
                  visibleSongs = visibleSongs.reversed.toList(growable: false);
                }
                return Stack(
                  children: [
                    _buildMobileScrollBody(
                      context,
                      snapshot: snapshot,
                      allSongs: loadedSongs,
                      visibleSongs: visibleSongs,
                    ),
                    if (_mobilePlayHeaderPinned)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: GToolbar.height,
                        child: Container(
                          key: const ValueKey(
                            'mobile-play-panel-pinned-surface',
                          ),
                          alignment: Alignment.topCenter,
                          color: mobileScheme.surfaceContainerLowest,
                          child: _MobilePlayAllPanel(
                            key: const ValueKey('mobile-play-panel-pinned'),
                            color: mobileScheme.surfaceContainerLowest,
                            loading: snapshot.connectionState !=
                                ConnectionState.done,
                            downloadBusy: _downloadAllBusy,
                            compact: true,
                            isFavorite: _isFavorite,
                            favoriteLoading: _favoriteLoading,
                            onFavorite: _supportsPlaylistFavorites
                                ? _toggleFavorite
                                : null,
                            onPlay: visibleSongs.isEmpty
                                ? null
                                : () => context
                                    .read<PlayerController>()
                                    .playQueue(visibleSongs),
                            onDownload: loadedSongs.isEmpty
                                ? null
                                : () => _downloadAll(loadedSongs),
                          ),
                        ),
                      ),
                    _MobilePlaylistTopBar(
                      title: widget.playlist.name,
                      titleVisible: _mobileTitleVisible,
                      searchOpen: _searchOpen,
                      onBack: () => Navigator.of(context).maybePop(),
                      onSearch: _toggleSearch,
                      onSearchChanged: (value) =>
                          setState(() => _searchQuery = value),
                      onMore: _showMobileMoreActions,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileScrollBody(
    BuildContext context, {
    required AsyncSnapshot<List<Song>> snapshot,
    required List<Song> allSongs,
    required List<Song> visibleSongs,
  }) {
    const panelColor = Colors.transparent;
    final current = context.select<PlayerController, Song?>((p) => p.current);
    return CustomScrollView(
      controller: _mobileScrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: _MobilePlaylistHero(
            key: _mobileHeroKey,
            playlist: widget.playlist,
            kind: widget.kind,
            songs: allSongs,
            loading: snapshot.connectionState != ConnectionState.done,
          ),
        ),
        SliverToBoxAdapter(
          child: _MobilePlayAllPanel(
            key: const ValueKey('mobile-play-panel-expanded'),
            color: panelColor,
            loading: snapshot.connectionState != ConnectionState.done,
            downloadBusy: _downloadAllBusy,
            isFavorite: _isFavorite,
            favoriteLoading: _favoriteLoading,
            onFavorite: _supportsPlaylistFavorites ? _toggleFavorite : null,
            onPlay: visibleSongs.isEmpty
                ? null
                : () =>
                    context.read<PlayerController>().playQueue(visibleSongs),
            onDownload: allSongs.isEmpty ? null : () => _downloadAll(allSongs),
          ),
        ),
        if (widget.playlist.description?.trim().isNotEmpty == true)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: InkWell(
                onTap: () => setState(
                  () => _descriptionExpanded = !_descriptionExpanded,
                ),
                child: Text(
                  widget.playlist.description!.trim(),
                  maxLines: _descriptionExpanded ? null : 2,
                  overflow: _descriptionExpanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        if (current != null)
          SliverToBoxAdapter(
            child: _MobileContinueRow(
              song: current,
              color: panelColor,
              onTap: context.read<PlayerController>().togglePlay,
            ),
          ),
        if (snapshot.connectionState != ConnectionState.done)
          const SliverToBoxAdapter(
            child: ColoredBox(
              color: panelColor,
              child: SizedBox(
                height: 260,
                child: GSkeletonList(itemCount: 4),
              ),
            ),
          )
        else if (snapshot.hasError)
          SliverToBoxAdapter(
            child: ColoredBox(
              color: panelColor,
              child: SizedBox(
                height: 260,
                child: GEmptyState(
                  icon: Icons.error_outline_rounded,
                  text: '加载失败，请检查网络后重试',
                  onRetry: _reload,
                ),
              ),
            ),
          )
        else if (visibleSongs.isEmpty)
          SliverToBoxAdapter(
            child: ColoredBox(
              color: panelColor,
              child: SizedBox(
                height: 260,
                child: GEmptyState(
                  icon: Icons.queue_music_rounded,
                  text: _searchQuery.trim().isNotEmpty
                      ? '没有找到相关歌曲'
                      : widget.kind == PlaylistDetailKind.album
                          ? '专辑中没有歌曲'
                          : '歌单为空',
                ),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: visibleSongs.length,
            itemBuilder: (context, index) {
              return RepaintBoundary(
                child: _MobilePlaylistSongRow(
                  song: visibleSongs[index],
                  songs: visibleSongs,
                  index: index,
                  color: panelColor,
                ),
              );
            },
          ),
        _pagingFooter(),
        const SliverToBoxAdapter(
          child: ColoredBox(
            color: panelColor,
            child: SizedBox(height: 104),
          ),
        ),
      ],
    );
  }

  Future<void> _downloadAll(List<Song> songs) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('下载全部歌曲'),
        content: Text('将下载歌单中的 ${songs.length} 首歌曲。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('下载'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _downloadAllBusy = true);
    final quality = context.read<SettingsController>().downloadQuality;
    var completed = 0;
    try {
      for (final song in songs) {
        await SongDownloadService.instance.download(song, quality: quality);
        completed++;
      }
      if (mounted) {
        _showMessage('全部歌曲已下载');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('已下载 $completed 首，${_errorText(error, '下载失败')}');
      }
    } finally {
      if (mounted) setState(() => _downloadAllBusy = false);
    }
  }

  void _showMoreActions() {
    showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(999, 58, 12, 0),
      items: const [
        PopupMenuItem(value: 'refresh', child: Text('刷新详情')),
      ],
    ).then((value) {
      if (value == 'refresh' && mounted) _reload();
    });
  }

  void _showMobileMoreActions() {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.sizeOf(context).width - 20,
        MediaQuery.paddingOf(context).top + GToolbar.height,
        20,
        0,
      ),
      items: [
        const PopupMenuItem(value: 'filter', child: Text('筛选歌曲')),
        PopupMenuItem(
          value: 'sort',
          child: Text(_reverseOrder ? '恢复原排序' : '倒序排列'),
        ),
        const PopupMenuItem(value: 'refresh', child: Text('刷新详情')),
      ],
    ).then((value) {
      if (!mounted) return;
      switch (value) {
        case 'filter':
          if (!_searchOpen) _toggleSearch();
        case 'sort':
          setState(() => _reverseOrder = !_reverseOrder);
        case 'refresh':
          _reload();
      }
    });
  }
}

class _PlaylistAmbientBackground extends StatelessWidget {
  const _PlaylistAmbientBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey('mobile-playlist-ambient-background'),
      color: scheme.surfaceContainerLowest,
    );
  }
}

class _MobilePlaylistTopBar extends StatelessWidget {
  const _MobilePlaylistTopBar({
    required this.title,
    required this.titleVisible,
    required this.searchOpen,
    required this.onBack,
    required this.onSearch,
    required this.onSearchChanged,
    required this.onMore,
  });

  final String title;
  final bool titleVisible;
  final bool searchOpen;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overArtwork = !titleVisible && !searchOpen;
    final foreground = overArtwork ? Colors.white : scheme.onSurface;
    final buttonBackground =
        overArtwork ? Colors.black.withValues(alpha: 0.36) : Colors.transparent;
    final bar = AnimatedContainer(
      key: const ValueKey('mobile-playlist-top-bar-surface'),
      duration: Motion.fast,
      height: GToolbar.height,
      color: titleVisible || searchOpen ? scheme.surfaceContainerLowest : null,
      child: GToolbar(
        leading: GBackButton(
            onTap: onBack, tint: foreground, backgroundColor: buttonBackground),
        centerTitle: !searchOpen,
        title: searchOpen
            ? TextField(
                autofocus: true,
                onChanged: onSearchChanged,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: '搜索歌曲或歌手',
                  hintStyle: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.56),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
              )
            : IgnorePointer(
                child: AnimatedOpacity(
                  opacity: titleVisible ? 1 : 0,
                  duration: Motion.fast,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
        actions: [
          GToolbarButton(
            icon: searchOpen ? Icons.close_rounded : Icons.search_rounded,
            tooltip: searchOpen ? '关闭搜索' : '搜索歌曲',
            tint: foreground,
            backgroundColor: buttonBackground,
            onTap: onSearch,
          ),
          GToolbarButton(
            icon: Icons.more_horiz_rounded,
            tooltip: '更多',
            tint: foreground,
            backgroundColor: buttonBackground,
            onTap: onMore,
          ),
        ],
      ),
    );
    if (!titleVisible) return bar;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: bar,
      ),
    );
  }
}

class _MobilePlaylistHero extends StatelessWidget {
  const _MobilePlaylistHero({
    super.key,
    required this.playlist,
    required this.kind,
    required this.songs,
    required this.loading,
  });

  final Playlist playlist;
  final PlaylistDetailKind kind;
  final List<Song> songs;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final creator = playlist.creatorName?.trim();
    final viewport = MediaQuery.sizeOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The artwork remains prominent in portrait while leaving room for
        // the controls on short landscape displays. Text determines the rest
        // of the header height, including when accessibility text is enlarged.
        final artworkSpace = (constraints.maxWidth * 0.46)
            .clamp(96.0, (viewport.height * 0.30).clamp(96.0, 232.0));
        return Stack(
          children: [
            Positioned.fill(
              child: AsyncCover(
                key: const ValueKey('mobile-playlist-hero-cover'),
                url: playlist.coverUrl,
                size: double.infinity,
                radius: 0,
                placeholderAlignment: const Alignment(0, -0.6),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.40, 0.78, 1],
                      colors: [
                        Colors.black.withValues(alpha: 0.12),
                        scheme.surfaceContainerLowest.withValues(alpha: 0.08),
                        scheme.surfaceContainerLowest.withValues(alpha: 0.88),
                        scheme.surfaceContainerLowest,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: artworkSpace),
                  Text(
                    playlist.name,
                    key: const ValueKey('mobile-playlist-hero-title'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 24,
                      fontWeight: TypeScale.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    creator == null || creator.isEmpty
                        ? (kind == PlaylistDetailKind.album ? '专辑' : '歌单创建者')
                        : creator,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 16,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    loading
                        ? '正在加载歌曲'
                        : '${playlist.trackCount ?? songs.length}首 · ${_formatPlaylistDuration(songs)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  if (playlist.playCount != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_formatPlayCount(playlist.playCount!)}次播放',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MobilePlayAllPanel extends StatelessWidget {
  const _MobilePlayAllPanel({
    super.key,
    required this.color,
    required this.loading,
    required this.downloadBusy,
    required this.isFavorite,
    required this.favoriteLoading,
    required this.onPlay,
    required this.onDownload,
    required this.onFavorite,
    this.compact = false,
  });

  final Color color;
  final bool loading;
  final bool downloadBusy;
  final bool isFavorite;
  final bool favoriteLoading;
  final VoidCallback? onPlay;
  final VoidCallback? onDownload;
  final VoidCallback? onFavorite;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: color,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, compact ? 6 : 12, 20, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaledLabel = MediaQuery.textScalerOf(context).scale(16);
            final stackActions = constraints.maxWidth < scaledLabel * 4 + 160;
            final playButton = FilledButton.icon(
              onPressed: onPlay,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.onSurface.withValues(alpha: 0.18),
                foregroundColor: scheme.onSurface,
                disabledBackgroundColor:
                    scheme.onSurface.withValues(alpha: 0.08),
                disabledForegroundColor: scheme.onSurfaceVariant,
                minimumSize: const Size(144, 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: const StadiumBorder(),
                side: BorderSide(
                  color: scheme.onSurface.withValues(alpha: 0.12),
                ),
                textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
                      fontSize: 16,
                      fontWeight: TypeScale.semibold,
                      height: 1.2,
                    ),
              ),
              icon: loading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 24),
              label: const Text('播放全部'),
            );
            final download = _MobileToolButton(
              icon: Icons.download_rounded,
              tooltip: '下载全部',
              busy: downloadBusy,
              onTap: onDownload,
            );
            final favorite = onFavorite == null
                ? null
                : _MobileToolButton(
                    icon: isFavorite
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    tooltip: isFavorite ? '取消收藏' : '收藏歌单',
                    busy: favoriteLoading,
                    selected: isFavorite,
                    selectedColor: AppBrand.favoriteRed,
                    onTap: onFavorite,
                  );
            if (stackActions) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  playButton,
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      download,
                      if (favorite != null) ...[
                        const SizedBox(width: 16),
                        favorite,
                      ],
                    ],
                  ),
                ],
              );
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                download,
                const SizedBox(width: 12),
                Flexible(child: playButton),
                if (favorite != null) ...[
                  const SizedBox(width: 12),
                  favorite,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MobileToolButton extends StatelessWidget {
  const _MobileToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
    this.selected = false,
    this.selectedColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;
  final bool selected;
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GPressScale(
        onTap: busy ? null : onTap,
        disabled: busy || onTap == null,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected
                ? selectedColor?.withValues(alpha: 0.14) ?? scheme.onSurface
                : scheme.onSurface.withValues(alpha: 0.10),
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox.square(
                  dimension: 19,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  icon,
                  size: 25,
                  color: selected
                      ? selectedColor ?? scheme.surfaceContainerLowest
                      : scheme.onSurface.withValues(
                          alpha: onTap == null ? 0.38 : 0.86,
                        ),
                ),
        ),
      ),
    );
  }
}

class _MobileContinueRow extends StatelessWidget {
  const _MobileContinueRow({
    required this.song,
    required this.color,
    required this.onTap,
  });

  final Song song;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: color,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              GIconButton(
                icon: Icons.play_arrow_rounded,
                tooltip: '继续播放',
                size: 22,
                padding: 7,
                backgroundColor: Colors.transparent,
                onTap: onTap,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: '继续播放：',
                        style: TextStyle(fontWeight: TypeScale.semibold),
                      ),
                      TextSpan(text: '${song.name}-${song.artistNames}'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.66),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobilePlaylistSongRow extends StatelessWidget {
  const _MobilePlaylistSongRow({
    required this.song,
    required this.songs,
    required this.index,
    required this.color,
  });

  final Song song;
  final List<Song> songs;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(
        key: ValueKey('mobile-playlist-song-${song.id}'),
        color: color,
        child: SongRow(
          song: song,
          index: index + 1,
          padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
          onTap: () =>
              context.read<PlayerController>().playQueue(songs, index: index),
        ),
      );
}

String _formatPlaylistDuration(List<Song> songs) {
  final totalMs = songs.fold<int>(0, (sum, song) => sum + song.durationMs);
  final duration = Duration(milliseconds: totalMs);
  if (duration.inHours >= 5) return '大于5小时';
  if (duration.inHours > 0) {
    return '${duration.inHours}小时${duration.inMinutes.remainder(60)}分钟';
  }
  return '${duration.inMinutes}分钟';
}

String _formatPlayCount(int count) {
  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(1)}亿';
  }
  if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
  return '$count';
}

class _PlaylistTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _PlaylistTopBar({
    required this.title,
    required this.onBack,
    required this.searchOpen,
    required this.onSearch,
    required this.onSearchChanged,
    required this.onMore,
  });

  final String title;
  final VoidCallback onBack;
  final bool searchOpen;
  final VoidCallback onSearch;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onMore;

  @override
  Size get preferredSize => const Size.fromHeight(GToolbar.height);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor.withValues(
                  alpha: dark ? 0.72 : 0.78,
                ),
          ),
          foregroundDecoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: glassHairline(context))),
          ),
          child: SafeArea(
            bottom: false,
            child: GToolbar(
              leading: GBackButton(onTap: onBack),
              centerTitle: !searchOpen,
              title: searchOpen
                  ? TextField(
                      autofocus: true,
                      onChanged: onSearchChanged,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: '搜索歌曲或歌手',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    )
                  : Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                GToolbarButton(
                  icon: searchOpen ? Icons.close_rounded : Icons.search_rounded,
                  tooltip: searchOpen ? '关闭搜索' : '搜索歌曲',
                  onTap: onSearch,
                ),
                GToolbarButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: '更多',
                  onTap: onMore,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader({
    required this.playlist,
    required this.kind,
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
  final PlaylistDetailKind kind;
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
      kind: kind,
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
      showCollectionActions: kind == PlaylistDetailKind.playlist,
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
    required this.kind,
    required this.songs,
    required this.descriptionExpanded,
    required this.showDescription,
    required this.onToggleDescription,
  });

  final Playlist playlist;
  final PlaylistDetailKind kind;
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
          kind == PlaylistDetailKind.album ? '专辑' : '歌单',
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
    required this.showCollectionActions,
  });

  final List<Song> songs;
  final bool desktop;
  final bool isFavorite;
  final bool favoriteLoading;
  final bool isAdded;
  final VoidCallback onFavorite;
  final VoidCallback onAdd;
  final bool showCollectionActions;

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
        if (showCollectionActions) ...[
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
              color: scheme.onPrimary,
            ),
            const SizedBox(width: 5),
            Text(
              '全部播放',
              style: TextStyle(
                color: scheme.onPrimary,
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
