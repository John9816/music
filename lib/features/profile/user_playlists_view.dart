import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/services/user_playlist_library.dart';
import '../../widgets/glass.dart';
import '../playlists/playlist_import_view.dart';
import 'user_library_view.dart';

enum UserPlaylistFilter { all, owned, favorites }

/// 用户歌单目录，点击歌单后加载其中的歌曲。
class UserPlaylistsView extends StatefulWidget {
  const UserPlaylistsView({
    super.key,
    this.filter = UserPlaylistFilter.all,
  });

  final UserPlaylistFilter filter;

  @override
  State<UserPlaylistsView> createState() => _UserPlaylistsViewState();
}

class _UserPlaylistsViewState extends State<UserPlaylistsView> {
  Future<List<Map<String, dynamic>>>? _future;
  Future<List<Map<String, dynamic>>>? _loadingFuture;

  @override
  void initState() {
    super.initState();
    UserPlaylistLibrary.instance.addListener(_onLibraryChanged);
    _future = _startLoad();
  }

  @override
  void dispose() {
    UserPlaylistLibrary.instance.removeListener(_onLibraryChanged);
    super.dispose();
  }

  void _onLibraryChanged() => _reload();

  Future<List<Map<String, dynamic>>>? _startLoad() {
    final token = context.read<AuthController>().token;
    if (token == null) return null;

    final future = Future<List<Map<String, dynamic>>>.sync(
      () => UserApi().getUserPlaylists(token),
    );
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

  Future<List<Map<String, dynamic>>>? _reload() {
    if (!mounted) return null;
    final future = _startLoad();
    if (future == null) return null;
    if (!identical(_future, future)) {
      setState(() {
        _future = future;
      });
    }
    return future;
  }

  Future<void> _openImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlaylistImportView()),
    );
  }

  void _openPlaylist(Map<String, dynamic> playlist) {
    final token = context.read<AuthController>().token;
    final id = userPlaylistId(playlist);
    if (token == null || id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserLibraryView(
          title: userPlaylistName(playlist),
          loader: () async {
            final items = await UserApi().getUserPlaylistSongs(id, token);
            return items.map(itemToSong).toList();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    return Scaffold(
      appBar: GAppBar(
        title: switch (widget.filter) {
          UserPlaylistFilter.favorites => '收藏的歌单',
          _ => '我的歌单',
        },
        onBack: () => Navigator.of(context).maybePop(),
        actions: widget.filter == UserPlaylistFilter.favorites
            ? const []
            : [
                GIconButton(
                  icon: Icons.file_download_outlined,
                  tooltip: '导入歌单',
                  size: 18,
                  padding: 9,
                  onTap: _openImport,
                ),
              ],
      ),
      body: future == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return GEmptyState(
                    icon: Icons.error_outline_rounded,
                    text: '歌单加载失败',
                    onRetry: _reload,
                  );
                }
                final playlists = snapshot.data ?? const [];
                final owned = playlists
                    .where(UserApi.isOwnedPlaylist)
                    .toList(growable: false);
                final favorites = playlists
                    .where(UserApi.isFavoritePlaylist)
                    .toList(growable: false);
                final visibleOwned =
                    widget.filter != UserPlaylistFilter.favorites
                        ? owned
                        : const <Map<String, dynamic>>[];
                final visibleFavorites =
                    widget.filter != UserPlaylistFilter.owned
                        ? favorites
                        : const <Map<String, dynamic>>[];
                if (visibleOwned.isEmpty && visibleFavorites.isEmpty) {
                  return GEmptyState(
                    icon: widget.filter == UserPlaylistFilter.favorites
                        ? Icons.bookmark_border_rounded
                        : Icons.queue_music_outlined,
                    text: widget.filter == UserPlaylistFilter.favorites
                        ? '还没有收藏的歌单'
                        : '还没有歌单',
                    onRetry: widget.filter == UserPlaylistFilter.favorites
                        ? _reload
                        : _openImport,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    final future = _reload();
                    if (future != null) await future;
                  },
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      if (visibleOwned.isNotEmpty) ...[
                        const _PlaylistSectionTitle('我的歌单'),
                        ...visibleOwned.map(_playlistTile),
                      ],
                      if (visibleFavorites.isNotEmpty) ...[
                        const _PlaylistSectionTitle('收藏的歌单'),
                        ...visibleFavorites.map(_playlistTile),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _playlistTile(Map<String, dynamic> playlist) {
    final count = (playlist['trackCount'] as num?)?.toInt();
    return GListTile(
      leading: const Icon(Icons.queue_music_rounded),
      title: Text(userPlaylistName(playlist)),
      subtitle: count == null ? null : Text('$count 首歌曲'),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => _openPlaylist(playlist),
    );
  }
}

class _PlaylistSectionTitle extends StatelessWidget {
  const _PlaylistSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
