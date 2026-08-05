import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../widgets/glass.dart';
import '../playlists/playlist_import_view.dart';
import 'user_library_view.dart';

/// 用户歌单目录，点击歌单后加载其中的歌曲。
class UserPlaylistsView extends StatefulWidget {
  const UserPlaylistsView({super.key});

  @override
  State<UserPlaylistsView> createState() => _UserPlaylistsViewState();
}

class _UserPlaylistsViewState extends State<UserPlaylistsView> {
  Future<List<Map<String, dynamic>>>? _future;
  Future<List<Map<String, dynamic>>>? _loadingFuture;

  @override
  void initState() {
    super.initState();
    _future = _startLoad();
  }

  Future<List<Map<String, dynamic>>>? _startLoad() {
    final token = context.read<AuthController>().token;
    if (token == null) return null;

    final existing = _loadingFuture;
    if (existing != null) return existing;

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
      MaterialPageRoute(
          builder: (_) => PlaylistImportView(onImported: _reload)),
    );
    if (mounted) _reload();
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
        title: '我的歌单',
        onBack: () => Navigator.of(context).maybePop(),
        actions: [
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
                if (playlists.isEmpty) {
                  return GEmptyState(
                    icon: Icons.queue_music_outlined,
                    text: '还没有歌单',
                    onRetry: _openImport,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    final future = _reload();
                    if (future != null) await future;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final count = (playlist['trackCount'] as num?)?.toInt();
                      return GListTile(
                        leading: const Icon(Icons.queue_music_rounded),
                        title: Text(userPlaylistName(playlist)),
                        subtitle: count == null ? null : Text('$count 首歌曲'),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => _openPlaylist(playlist),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
