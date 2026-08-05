import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../search/artist_names_link.dart';

/// 通用的用户歌曲列表页（收藏 / 播放历史 / 歌单详情等）。
class UserLibraryView extends StatefulWidget {
  const UserLibraryView({
    super.key,
    required this.title,
    required this.loader,
    this.embedded = false,
    this.active = true,
    this.onBack,
    this.onRemove,
    this.onClear,
  });

  final String title;
  final Future<List<Song>> Function() loader;
  final bool embedded;
  final bool active;
  final VoidCallback? onBack;
  final Future<void> Function(Song song)? onRemove;
  final Future<void> Function(List<Song> songs)? onClear;

  @override
  State<UserLibraryView> createState() => _UserLibraryViewState();
}

class _UserLibraryViewState extends State<UserLibraryView> {
  Future<List<Song>>? _future;
  Future<List<Song>>? _loadingFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _future = _startLoad();
  }

  @override
  void didUpdateWidget(covariant UserLibraryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _favorites => widget.title.contains('喜欢');

  Future<List<Song>> _startLoad() {
    final existing = _loadingFuture;
    if (existing != null) return existing;

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

  @override
  Widget build(BuildContext context) {
    final content = ColoredBox(
      color: _libraryBackground(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LibraryTopBar(
            title: _favorites ? '我喜欢的音乐' : '最近播放',
            onBack: widget.onBack ??
                (widget.embedded
                    ? null
                    : () => Navigator.of(context).maybePop()),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(body: content);
  }

  Color _libraryBackground(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF251118)
        : Theme.of(context).colorScheme.surfaceContainerLowest;
  }

  Widget _buildBody() {
    final future = _future;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<List<Song>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return GEmptyState(
            icon: Icons.error_outline_rounded,
            text: '加载失败，请稍后重试',
            onRetry: _reload,
          );
        }
        final songs = snapshot.data ?? const <Song>[];
        return _favorites ? _buildFavorites(songs) : _buildHistory(songs);
      },
    );
  }

  Widget _buildFavorites(List<Song> songs) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _FavoritesHero(count: songs.length)),
          SliverToBoxAdapter(
            child: _FavoritesActions(
              enabled: songs.isNotEmpty,
              onPlay: songs.isEmpty
                  ? null
                  : () => context.read<PlayerController>().playQueue(songs),
            ),
          ),
          if (songs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _LibraryEmptyState(
                icon: Icons.favorite_border_rounded,
                title: '还没有喜欢的歌曲',
                subtitle: '在歌曲菜单或播放器中点亮喜欢，音乐会出现在这里',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              sliver: SliverList.builder(
                itemCount: songs.length,
                itemBuilder: (context, index) => _LibrarySongRow(
                  index: index + 1,
                  song: songs[index],
                  onTap: () => context
                      .read<PlayerController>()
                      .playQueue(songs, index: index),
                  onDelete: widget.onRemove == null
                      ? null
                      : () => _removeSong(songs[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistory(List<Song> songs) {
    final normalized = _query.trim().toLowerCase();
    final visible = normalized.isEmpty
        ? songs
        : songs
            .where((song) =>
                song.name.toLowerCase().contains(normalized) ||
                song.artistNames.toLowerCase().contains(normalized))
            .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '搜索播放记录',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF3A2930)
                          : Theme.of(context).colorScheme.surfaceContainer,
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
                        borderSide: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _DeleteHistoryButton(
                onTap: songs.isEmpty || widget.onClear == null || _mutating
                    ? null
                    : () => _clearHistory(songs),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? _LibraryEmptyState(
                  icon: normalized.isEmpty
                      ? Icons.history_rounded
                      : Icons.search_off_rounded,
                  title: normalized.isEmpty ? '还没有播放记录' : '没有匹配的播放记录',
                  subtitle:
                      normalized.isEmpty ? '播放过的歌曲会按时间出现在这里' : '换个歌曲或歌手名称试试',
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                    itemCount: visible.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _historyGroupTitle(visible),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: TypeScale.bold,
                            ),
                          ),
                        );
                      }
                      final song = visible[index - 1];
                      final queueIndex = songs.indexOf(song);
                      return _LibrarySongRow(
                        song: song,
                        onTap: () => context
                            .read<PlayerController>()
                            .playQueue(songs, index: queueIndex),
                        onDelete: widget.onRemove == null
                            ? null
                            : () => _removeSong(song),
                      );
                    },
                  ),
                ),
        ),
      ],
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

  Future<void> _removeSong(Song song) async {
    final remove = widget.onRemove;
    if (remove == null || _mutating) return;
    setState(() => _mutating = true);
    try {
      await remove(song);
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

class _LibraryTopBar extends StatelessWidget {
  const _LibraryTopBar({required this.title, this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            GIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: '返回',
              size: 20,
              padding: 10,
              backgroundColor: Colors.transparent,
              onTap: onBack,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: TypeScale.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritesHero extends StatelessWidget {
  const _FavoritesHero({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          Container(
            width: 118,
            height: 118,
            decoration: BoxDecoration(
              color: const Color(0xFF4F1424),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              size: 40,
              color: Color(0xFFFF375F),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '系统歌单',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFFF375F),
                    fontWeight: TypeScale.bold,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  '我喜欢的音乐',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: TypeScale.heavy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$count 首歌曲',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoritesActions extends StatelessWidget {
  const _FavoritesActions({required this.enabled, this.onPlay});

  final bool enabled;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: GPressScale(
              onTap: enabled ? onPlay : null,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: enabled
                      ? const Color(0xFFFF375F)
                      : const Color(0xFFB52749),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.play_arrow_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '全部播放',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: TypeScale.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 22),
          SizedBox(
            width: 119,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.download_for_offline_outlined,
                  size: 17,
                  color: scheme.outline,
                ),
                const SizedBox(width: 6),
                Text(
                  '全部下载',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: TypeScale.semibold,
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteHistoryButton extends StatelessWidget {
  const _DeleteHistoryButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final error = Theme.of(context).colorScheme.error;
    return GPressScale(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: error.withValues(alpha: enabled ? 0.14 : 0.06),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          size: 20,
          color: error.withValues(alpha: enabled ? 1 : 0.38),
        ),
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
  });

  final Song song;
  final VoidCallback onTap;
  final int? index;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        GPressScale(
          onTap: onTap,
          child: SizedBox(
            height: 64,
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
                          fontSize: 14,
                          fontWeight: TypeScale.semibold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      ArtistNamesLink(
                        artists: song.artists,
                        source: song.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                GIconButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: '更多',
                  size: 20,
                  padding: 8,
                  backgroundColor: Colors.transparent,
                  onTap: () {},
                ),
                if (onDelete != null)
                  GIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: '删除',
                    size: 19,
                    padding: 8,
                    tint: scheme.outline,
                    backgroundColor: Colors.transparent,
                    onTap: onDelete,
                  ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: glassHairline(context)),
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
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF321D24)
                      : scheme.surfaceContainer,
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
  final rawId = json['songId'] ?? json['id'];
  final id = rawId?.toString() ?? '';
  final name = (json['name'] ?? json['songName'])?.toString() ?? '';
  final artistNames = (json['artistName'] ?? json['artist'])?.toString() ?? '';
  final artists = artistNames
      .split(RegExp(r'[,/]'))
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .map((name) => Artist(id: 0, name: name))
      .toList();
  final rawCover = json['coverUrl'] ?? json['albumCover'];
  final coverUrl = rawCover == null || rawCover.toString().trim().isEmpty
      ? null
      : rawCover.toString();
  final durationMs = (json['durationMs'] as num?)?.toInt() ??
      ((json['durationSec'] as num?)?.toInt() ?? 0) * 1000;
  return Song(
    id: id,
    name: name,
    source: json['source']?.toString() ?? 'netease',
    artists: artists.isEmpty ? const [Artist(id: 0, name: '未知')] : artists,
    album: Album(
      id: 0,
      name: json['album']?.toString() ?? '',
      picUrl: coverUrl,
    ),
    durationMs: durationMs,
    libraryId: json['id']?.toString(),
    playedAt: DateTime.tryParse(json['playedAt']?.toString() ?? ''),
  );
}
