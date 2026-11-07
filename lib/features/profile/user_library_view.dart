import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/song_download_service.dart';
import '../../core/services/user_playlist_library.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../../widgets/song_action_menu.dart';
import '../search/artist_names_link.dart';

/// 通用的用户歌曲列表页（收藏 / 播放历史 / 歌单详情等）。
class UserLibraryView extends StatefulWidget {
  const UserLibraryView({
    super.key,
    required this.title,
    required this.loader,
    this.embedded = false,
    this.active = true,
    this.onRemove,
    this.onClear,
    this.onSync,
    this.kind = UserLibraryKind.playlist,
  });

  final String title;
  final Future<List<Song>> Function() loader;
  final bool embedded;
  final bool active;
  final Future<void> Function(Song song)? onRemove;
  final Future<void> Function(List<Song> songs)? onClear;
  final Future<void> Function()? onSync;
  final UserLibraryKind kind;

  @override
  State<UserLibraryView> createState() => _UserLibraryViewState();
}

/// Describes the source of this list explicitly. Titles are user content and
/// must not be used to decide whether a playlist is history or favorites.
enum UserLibraryKind { favorites, history, playlist }

class _UserLibraryViewState extends State<UserLibraryView> {
  Future<List<Song>>? _future;
  Future<List<Song>>? _loadingFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _mutating = false;
  bool _selectionMode = false;
  bool _searchOpen = false;
  bool _hasLoaded = false;
  List<Song> _loadedSongs = const <Song>[];
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    UserPlaylistLibrary.instance.addListener(_onLibraryChanged);
    if (widget.active) _future = _startLoad();
  }

  @override
  void didUpdateWidget(covariant UserLibraryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contentChanged = oldWidget.kind != widget.kind ||
        (widget.kind == UserLibraryKind.playlist &&
            oldWidget.title != widget.title);
    if (contentChanged) {
      _future = null;
      _loadingFuture = null;
      _loadedSongs = const <Song>[];
      _hasLoaded = false;
      _searchController.clear();
      _query = '';
      _searchOpen = false;
      _selectionMode = false;
      _selected.clear();
    }
    if (widget.active && (!oldWidget.active || contentChanged)) _reload();
  }

  @override
  void dispose() {
    UserPlaylistLibrary.instance.removeListener(_onLibraryChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onLibraryChanged() {
    if (!_history && widget.active) _reload();
  }

  bool get _favorites => widget.kind == UserLibraryKind.favorites;
  bool get _history => widget.kind == UserLibraryKind.history;

  Future<List<Song>> _startLoad() {
    final future = Future<List<Song>>.sync(widget.loader);
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

  Future<List<Song>>? _reload() {
    if (!mounted) return null;
    final future = _startLoad();
    if (!identical(_future, future)) {
      setState(() {
        _future = future;
      });
    }
    return future;
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: _libraryBackground(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GAppBar(
            onBack:
                widget.embedded ? null : () => Navigator.of(context).maybePop(),
            actions: [
              GIconButton(
                icon: _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                tooltip: _searchOpen ? '关闭搜索' : '搜索歌曲',
                size: 22,
                padding: 9,
                backgroundColor: Colors.transparent,
                onTap: _toggleSearch,
              ),
              Builder(
                builder: (buttonContext) => GIconButton(
                  icon: Icons.more_vert_rounded,
                  tooltip: '更多',
                  size: 22,
                  padding: 9,
                  backgroundColor: Colors.transparent,
                  onTap: () => _showMoreActions(buttonContext),
                ),
              ),
              if (widget.onRemove != null)
                GIconButton(
                  icon: _selectionMode
                      ? Icons.close_rounded
                      : Icons.checklist_rounded,
                  tooltip: _selectionMode ? '退出管理' : '管理歌曲',
                  size: 18,
                  padding: 9,
                  backgroundColor: Colors.transparent,
                  onTap: _selectionMode ? _exitSelection : _enterSelection,
                ),
              if (widget.onSync != null)
                GIconButton(
                  icon: Icons.sync_rounded,
                  tooltip: '同步歌单',
                  size: 18,
                  padding: 9,
                  backgroundColor: Colors.transparent,
                  onTap: _syncPlaylist,
                ),
            ],
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(body: content);
  }

  Future<void> _syncPlaylist() async {
    if (_mutating || widget.onSync == null) return;
    setState(() => _mutating = true);
    try {
      await widget.onSync!();
      if (!mounted) return;
      _message('歌单已同步');
      _reload();
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Color _libraryBackground(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainerLowest;
  }

  Widget _buildBody() {
    final future = _future;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<List<Song>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildImmersiveLibrary(
            _loadedSongs,
            history: _history,
            loading: !_hasLoaded,
            refreshing: _hasLoaded,
          );
        }
        if (snapshot.hasError) {
          if (_hasLoaded) {
            return _buildImmersiveLibrary(
              _loadedSongs,
              history: _history,
              refreshFailed: true,
            );
          }
          return GEmptyState(
            icon: Icons.error_outline_rounded,
            text: '加载失败，请稍后重试',
            onRetry: _reload,
          );
        }
        final songs = snapshot.data ?? const <Song>[];
        _hasLoaded = true;
        _loadedSongs = songs;
        if (_favorites) return _buildFavorites(songs);
        return _buildTrackList(songs, history: _history);
      },
    );
  }

  Widget _buildFavorites(List<Song> songs) {
    return _buildImmersiveLibrary(songs, history: false);
  }

  Future<void> _downloadAll(List<Song> songs) async {
    final service = context.read<SongDownloadService>();
    final quality = context.read<SettingsController>().downloadQuality;
    final pending = songs.where((song) => !service.isDownloaded(song)).toList();
    if (pending.isEmpty) {
      _message('这些歌曲都已下载');
      return;
    }
    _message('开始下载 ${pending.length} 首歌曲');
    var failed = 0;
    for (final song in pending) {
      try {
        await service.download(song, quality: quality);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    _message(failed == 0 ? '全部下载完成' : '下载完成，$failed 首失败');
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _buildTrackList(List<Song> songs, {required bool history}) {
    return _buildImmersiveLibrary(songs, history: history);
  }

  Widget _buildImmersiveLibrary(
    List<Song> songs, {
    required bool history,
    bool loading = false,
    bool refreshing = false,
    bool refreshFailed = false,
  }) {
    final visible = _visibleSongs(songs);
    final title = switch (widget.kind) {
      UserLibraryKind.favorites => '我喜欢的音乐',
      UserLibraryKind.history => '播放历史',
      UserLibraryKind.playlist => widget.title,
    };
    final emptyTitle = _query.trim().isEmpty
        ? switch (widget.kind) {
            UserLibraryKind.favorites => '还没有喜欢的歌曲',
            UserLibraryKind.history => '还没有播放记录',
            UserLibraryKind.playlist => '歌单为空',
          }
        : (history ? '没有匹配的播放记录' : '没有匹配的歌曲');

    final content = RefreshIndicator(
      onRefresh: _refreshFromUi,
      child: Stack(
        children: [
          const Positioned.fill(child: _LibraryTintBackground()),
          CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: MediaQuery.sizeOf(context).width < GBreakpoints.sidebar
                    ? EdgeInsets.zero
                    : const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: _LibraryHero(
                    title: title,
                    songs: songs,
                    history: history,
                    kind: widget.kind,
                    loading: loading,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _LibraryPlayBar(
                  songs: visible,
                  count: loading ? null : visible.length,
                  onPlay: visible.isEmpty
                      ? null
                      : () =>
                          context.read<PlayerController>().playQueue(visible),
                  onDownload:
                      visible.isEmpty ? null : () => _downloadAll(visible),
                  onClear: history && songs.isNotEmpty && widget.onClear != null
                      ? () => _clearHistory(songs)
                      : null,
                  onFilter: _toggleSearch,
                ),
              ),
              SliverToBoxAdapter(
                child: Offstage(
                  offstage: !_searchOpen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: _searchField(history: history),
                  ),
                ),
              ),
              if (_selectionMode)
                SliverToBoxAdapter(
                  child: _SongSelectionToolbar(
                    selectedCount: _selected.length,
                    totalCount: visible.length,
                    mutating: _mutating,
                    onSelectAll: () => _selectAll(visible),
                    onDelete: _selected.isEmpty
                        ? null
                        : () => _deleteSelected(visible),
                  ),
                ),
              if (loading)
                const SliverToBoxAdapter(
                  child: ExcludeSemantics(
                    child: GSkeletonList(
                      itemCount: 5,
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                  ),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LibraryEmptyState(
                    icon: _query.trim().isEmpty
                        ? switch (widget.kind) {
                            UserLibraryKind.history => Icons.history_rounded,
                            UserLibraryKind.favorites =>
                              Icons.favorite_border_rounded,
                            UserLibraryKind.playlist =>
                              Icons.queue_music_rounded,
                          }
                        : Icons.search_off_rounded,
                    title: emptyTitle,
                    subtitle: _query.trim().isEmpty
                        ? switch (widget.kind) {
                            UserLibraryKind.history => '播放过的歌曲会按时间出现在这里',
                            UserLibraryKind.favorites =>
                              '在歌曲菜单或播放器中点亮喜欢，音乐会出现在这里',
                            UserLibraryKind.playlist =>
                              '在歌曲菜单中选择“收藏到歌单”，添加到这个歌单',
                          }
                        : '换个歌曲或歌手名称试试',
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 18, 8),
                    child: Text(
                      history ? _historyGroupTitle(visible) : '歌曲',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: TypeScale.bold,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                  sliver: SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final song = visible[index];
                      final queueIndex = songs.indexOf(song);
                      return _LibrarySongRow(
                        index: widget.kind == UserLibraryKind.favorites
                            ? index + 1
                            : null,
                        song: song,
                        selected: _selected.contains(_songKey(song)),
                        selectionMode: _selectionMode,
                        onTap: _selectionMode
                            ? () => _toggleSelection(song)
                            : () => context
                                .read<PlayerController>()
                                .playQueue(songs, index: queueIndex),
                        onDelete: widget.onRemove == null || _selectionMode
                            ? null
                            : () => _removeSong(song),
                        removeLabel: _removeLabel,
                        showFavoriteAction:
                            !_favorites || widget.onRemove == null,
                        onSelect: () => _toggleSelection(song),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
          if (refreshing)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 2,
                semanticsLabel: '正在刷新列表',
              ),
            ),
        ],
      ),
    );
    return Column(
      children: [
        if (refreshFailed)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      '刷新失败，仍显示上次的内容',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                TextButton(onPressed: _reload, child: const Text('重试')),
              ],
            ),
          ),
        Expanded(child: content),
      ],
    );
  }

  void _showMoreActions(BuildContext buttonContext) {
    final button = buttonContext.findRenderObject() as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final anchor = button.localToGlobal(
      Offset(0, button.size.height),
      ancestor: overlay,
    );
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'refresh', child: Text('刷新列表')),
      if (_history && widget.onClear != null)
        const PopupMenuItem(value: 'clear', child: Text('清空播放历史')),
    ];
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        anchor & Size(button.size.width, 0),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: items,
    ).then((value) {
      if (!mounted) return;
      if (value == 'refresh') _reload();
      if (value == 'clear') _clearHistory(_loadedSongs);
    });
  }

  List<Song> _visibleSongs(List<Song> songs) {
    final normalized = _query.trim().toLowerCase();
    if (normalized.isEmpty) return songs;
    return songs
        .where((song) =>
            song.name.toLowerCase().contains(normalized) ||
            song.artistNames.toLowerCase().contains(normalized))
        .toList();
  }

  Widget _searchField({required bool history}) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      style: TextStyle(fontSize: 14, color: scheme.onSurface),
      cursorColor: scheme.primary,
      decoration: InputDecoration(
        hintText: history ? '搜索播放记录' : '搜索歌曲',
        hintStyle: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
        prefixIcon: Icon(Icons.search_rounded,
            size: 20, color: scheme.onSurfaceVariant),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.35)),
        ),
      ),
    );
  }

  String _historyGroupTitle(List<Song> songs) {
    if (songs.isEmpty) return '最近';
    final playedAt = songs.first.playedAt?.toLocal();
    if (playedAt == null) return '最近';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(playedAt.year, playedAt.month, playedAt.day);
    final difference = today.difference(day).inDays;
    if (difference <= 0) return '今天';
    if (difference == 1) return '昨天';
    return '更早';
  }

  Future<void> _refresh() async {
    final future = _reload();
    if (future != null) await future;
  }

  Future<void> _refreshFromUi() async {
    try {
      await _refresh();
    } catch (_) {
      // FutureBuilder displays a retry state while preserving cached content.
    }
  }

  String get _removeLabel => switch (widget.kind) {
        UserLibraryKind.playlist => '从歌单移除',
        UserLibraryKind.favorites => '取消喜欢',
        UserLibraryKind.history => '删除播放记录',
      };

  Future<void> _removeSong(Song song) async {
    final remove = widget.onRemove;
    if (remove == null || _mutating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$_removeLabel？'),
        content: Text('“${song.name}”'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_removeLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _mutating) return;
    setState(() => _mutating = true);
    try {
      await remove(song);
      if (!mounted) return;
      if (_favorites) {
        final player = context.read<PlayerController>();
        if (player.current?.id == song.id &&
            player.current?.source == song.source) {
          player.setLiked(false);
        }
      }
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _enterSelection() {
    if (_mutating || widget.onRemove == null) return;
    setState(() => _selectionMode = true);
  }

  void _exitSelection() {
    if (_mutating) return;
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  String _songKey(Song song) => '${song.source}:${song.id}:${song.libraryId}';

  void _toggleSelection(Song song) {
    final key = _songKey(song);
    setState(() {
      if (!_selected.add(key)) _selected.remove(key);
    });
  }

  void _selectAll(List<Song> songs) {
    setState(() {
      final keys = songs.map(_songKey).toSet();
      if (keys.isNotEmpty && _selected.containsAll(keys)) {
        _selected.removeAll(keys);
      } else {
        _selected.addAll(keys);
      }
    });
  }

  Future<void> _deleteSelected(List<Song> songs) async {
    final remove = widget.onRemove;
    if (remove == null || _mutating || _selected.isEmpty) return;
    final selected = songs
        .where((song) => _selected.contains(_songKey(song)))
        .toList(growable: false);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除所选歌曲？'),
            content: Text('将删除 ${selected.length} 首歌曲。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _mutating = true);
    var failed = 0;
    try {
      for (final song in selected) {
        try {
          await remove(song);
        } catch (_) {
          failed++;
        }
      }
      _selectionMode = false;
      _selected.clear();
      await _refresh();
      if (mounted) _message(failed == 0 ? '歌曲已删除' : '$failed 首歌曲删除失败');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _clearHistory(List<Song> songs) async {
    final clear = widget.onClear;
    if (clear == null || _mutating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空播放历史？'),
        content: const Text('此操作会删除当前账号的全部播放记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _mutating = true);
    try {
      await clear(songs);
      await _refresh();
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }
}

class _LibraryTintBackground extends StatelessWidget {
  const _LibraryTintBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(color: scheme.surfaceContainerLowest);
  }
}

class _LibraryHero extends StatelessWidget {
  const _LibraryHero({
    required this.title,
    required this.songs,
    required this.history,
    required this.kind,
    this.loading = false,
  });

  final String title;
  final List<Song> songs;
  final bool history;
  final UserLibraryKind kind;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final desktop = MediaQuery.sizeOf(context).width >= GBreakpoints.sidebar;
    final coverSize = desktop ? 200.0 : 132.0;
    final song = songs.isEmpty ? null : songs.first;
    final label = switch (kind) {
      UserLibraryKind.favorites => '我的音乐',
      UserLibraryKind.history => '最近播放',
      UserLibraryKind.playlist => '歌单',
    };
    final metadata = loading
        ? '正在加载歌曲…'
        : history
            ? '${songs.length} 首 · 按播放时间排序'
            : '${songs.length} 首歌曲';
    final placeholderIcon = switch (kind) {
      UserLibraryKind.history => Icons.history_rounded,
      UserLibraryKind.favorites => Icons.favorite_rounded,
      UserLibraryKind.playlist => Icons.queue_music_rounded,
    };
    if (!desktop) {
      final viewport = MediaQuery.sizeOf(context);
      final artworkSpace = (viewport.width * 0.46)
          .clamp(96.0, (viewport.height * 0.30).clamp(96.0, 232.0));
      return Stack(
        children: [
          Positioned.fill(
            child: loading
                ? const GSkeleton(radius: 0)
                : song == null
                    ? ColoredBox(
                        color: scheme.primaryContainer,
                        child: Align(
                          alignment: const Alignment(0, -0.55),
                          child: Icon(
                            placeholderIcon,
                            size: 80,
                            color: scheme.primary,
                          ),
                        ),
                      )
                    : AsyncCover(
                        url: song.album.picUrl,
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
                    stops: const [0, 0.4, 0.78, 1],
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
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: TypeScale.bold,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$label · $metadata',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: coverSize,
          height: coverSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(desktop ? 18 : 14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: loading
              ? const GSkeleton(radius: 18)
              : song == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(desktop ? 18 : 14),
                      ),
                      child: Icon(
                        placeholderIcon,
                        size: coverSize * 0.34,
                        color: scheme.primary,
                      ),
                    )
                  : AsyncCover(
                      url: song.album.picUrl,
                      size: coverSize,
                      radius: desktop ? 18 : 14,
                    ),
        ),
        SizedBox(width: desktop ? 26 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: TypeScale.semibold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: desktop ? 30 : 25,
                  height: 1.08,
                  fontWeight: TypeScale.heavy,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                metadata,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LibraryPlayBar extends StatelessWidget {
  const _LibraryPlayBar({
    required this.songs,
    required this.count,
    required this.onPlay,
    required this.onDownload,
    required this.onClear,
    required this.onFilter,
  });

  final List<Song> songs;
  final int? count;
  final VoidCallback? onPlay;
  final VoidCallback? onDownload;
  final VoidCallback? onClear;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPlay != null;
    if (MediaQuery.sizeOf(context).width < GBreakpoints.sidebar) {
      final playButton = FilledButton.icon(
        onPressed: onPlay,
        style: FilledButton.styleFrom(
          backgroundColor: scheme.onSurface.withValues(alpha: 0.18),
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(144, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.12)),
          textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
                fontSize: 16,
                fontWeight: TypeScale.semibold,
                height: 1.2,
              ),
        ),
        icon: const Icon(Icons.play_arrow_rounded, size: 24),
        label: const Text('播放全部'),
      );
      final download = GIconButton(
        icon: Icons.download_rounded,
        tooltip: '全部下载',
        size: 24,
        padding: 12,
        backgroundColor: Colors.transparent,
        onTap: onDownload,
        disabled: onDownload == null,
      );
      final trailing = GIconButton(
        icon:
            onClear == null ? Icons.tune_rounded : Icons.delete_outline_rounded,
        tooltip: onClear == null ? '筛选歌曲' : '清空播放历史',
        size: 24,
        padding: 12,
        backgroundColor: Colors.transparent,
        onTap: onClear ?? onFilter,
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth <
              MediaQuery.textScalerOf(context).scale(16) * 4 + 160) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                playButton,
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [download, const SizedBox(width: 16), trailing],
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
              const SizedBox(width: 12),
              trailing,
            ],
          );
        }),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 14),
      child: Row(
        children: [
          GPressScale(
            onTap: onPlay,
            disabled: !enabled,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled
                    ? scheme.primary
                    : scheme.primary.withValues(alpha: 0.35),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 30,
                color: scheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GPressScale(
              onTap: onPlay,
              disabled: !enabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '播放全部',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: TypeScale.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    count == null ? '正在加载…' : '$count 首歌曲',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          GIconButton(
            icon: Icons.download_rounded,
            tooltip: '全部下载',
            size: 23,
            padding: 10,
            backgroundColor: Colors.transparent,
            tint: enabled ? scheme.onSurface : scheme.outline,
            onTap: onDownload,
            disabled: !enabled,
          ),
          GIconButton(
            icon: onClear == null
                ? Icons.tune_rounded
                : Icons.delete_outline_rounded,
            tooltip: onClear == null ? '筛选歌曲' : '清空播放历史',
            size: 23,
            padding: 10,
            backgroundColor: Colors.transparent,
            tint: onClear == null ? scheme.onSurface : scheme.error,
            onTap: onClear ?? onFilter,
          ),
        ],
      ),
    );
  }
}

class _SongSelectionToolbar extends StatelessWidget {
  const _SongSelectionToolbar({
    required this.selectedCount,
    required this.totalCount,
    required this.onSelectAll,
    required this.onDelete,
    this.mutating = false,
  });

  final int selectedCount;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback? onDelete;
  final bool mutating;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: mutating
          ? Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '正在处理...',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: Text('$selectedCount/$totalCount 已选')),
                TextButton(onPressed: onSelectAll, child: const Text('全选')),
                GIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: '删除所选歌曲',
                  size: 18,
                  padding: 9,
                  onTap: onDelete,
                ),
              ],
            ),
    );
  }
}

class _LibrarySongRow extends StatelessWidget {
  const _LibrarySongRow({
    required this.song,
    required this.onTap,
    this.index,
    this.onDelete,
    this.removeLabel = '从歌单移除',
    this.showFavoriteAction = true,
    this.selected = false,
    this.selectionMode = false,
    this.onSelect,
  });

  final Song song;
  final VoidCallback onTap;
  final int? index;
  final VoidCallback? onDelete;
  final String removeLabel;
  final bool showFavoriteAction;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        GPressScale(
          onTap: onTap,
          child: SizedBox(
            height: math.max(
              68,
              MediaQuery.textScalerOf(context).scale(16) * 1.3 +
                  MediaQuery.textScalerOf(context).scale(14) * 1.3 +
                  23,
            ),
            child: Row(
              children: [
                if (index != null)
                  SizedBox(
                    width: 34,
                    child: Text(
                      '$index',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                AsyncCover(
                  url: song.album.picUrl,
                  size: 48,
                  radius: 9,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.3,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 3),
                      ArtistNamesLink(
                        artists: song.artists,
                        source: song.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selectionMode)
                  Checkbox(
                    value: selected,
                    onChanged: (_) => onSelect?.call(),
                  )
                else
                  SongActionButton(
                    song: song,
                    onPlay: onTap,
                    onRemove: onDelete,
                    removeLabel: removeLabel,
                    showFavoriteAction: showFavoriteAction,
                  ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          indent: index == null ? 60 : 94,
          color: glassHairline(context),
        ),
      ],
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
        child: Transform.translate(
          offset: const Offset(0, -10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainer,
                ),
                child: Icon(icon, size: 27, color: scheme.outline),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: TypeScale.bold,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- helpers for converting user API items to Song ----

String? userPlaylistId(Map<String, dynamic> json) {
  final raw = json['id'] ?? json['playlistId'];
  if (raw is num) return raw.toInt().toString();
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  return null;
}

String userPlaylistName(Map<String, dynamic> json) {
  final name = json['name'] ?? json['playlistName'];
  return name is String && name.trim().isNotEmpty ? name.trim() : '未命名歌单';
}

Song itemToSong(Map<String, dynamic> json) {
  return Song.fromUserLibraryItem(json);
}
