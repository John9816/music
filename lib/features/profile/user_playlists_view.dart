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
    this.api,
  });

  final UserPlaylistFilter filter;
  final UserApi? api;

  @override
  State<UserPlaylistsView> createState() => _UserPlaylistsViewState();
}

class _UserPlaylistsViewState extends State<UserPlaylistsView> {
  Future<List<Map<String, dynamic>>>? _future;
  Future<List<Map<String, dynamic>>>? _loadingFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;
  bool _mutating = false;

  UserApi get _api => widget.api ?? UserApi();

  @override
  void initState() {
    super.initState();
    UserPlaylistLibrary.instance.addListener(_onLibraryChanged);
    _future = _startLoad();
  }

  @override
  void dispose() {
    UserPlaylistLibrary.instance.removeListener(_onLibraryChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onLibraryChanged() => _reload();

  Future<List<Map<String, dynamic>>>? _startLoad() {
    final token = context.read<AuthController>().token;
    if (token == null) return null;

    final future = Future<List<Map<String, dynamic>>>.sync(
      () => _api.getUserPlaylists(token),
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

  Future<void> _refresh() async {
    final future = _reload();
    if (future != null) await future;
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
    final source = playlist['source']?.toString().trim();
    final sourceId = playlist['sourceId']?.toString().trim();
    final canSync = source != null &&
        source.isNotEmpty &&
        source != 'local' &&
        sourceId != null &&
        sourceId.isNotEmpty;
    final canDeleteItems = !UserApi.isFavoritePlaylist(playlist);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserLibraryView(
          title: userPlaylistName(playlist),
          kind: UserLibraryKind.playlist,
          loader: () async {
            final items = await _api.getUserPlaylistSongs(id, token);
            return items.map(itemToSong).toList();
          },
          onRemove: canDeleteItems
              ? (song) async {
                  final itemId = song.libraryId;
                  if (itemId == null || itemId.isEmpty) {
                    throw StateError('歌单歌曲缺少记录 ID');
                  }
                  await _api.deleteUserPlaylistSong(id, itemId, token);
                }
              : null,
          onSync: canSync
              ? () async {
                  await _api.syncPlaylist(id, token);
                }
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    final canImport = widget.filter != UserPlaylistFilter.favorites;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: GAppBar(
        title: switch (widget.filter) {
          UserPlaylistFilter.favorites => '收藏的歌单',
          _ => '我的歌单',
        },
        onBack: () => Navigator.of(context).maybePop(),
        actions: _selectionMode
            ? [
                GIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '退出管理',
                  size: 18,
                  padding: 9,
                  onTap: _exitSelection,
                ),
              ]
            : [
                GIconButton(
                  icon: Icons.checklist_rounded,
                  tooltip: '管理歌单',
                  size: 18,
                  padding: 9,
                  onTap: _enterSelection,
                ),
                if (canImport)
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
                final filteredOwned =
                    visibleOwned.where(_matchesQuery).toList(growable: false);
                final filteredFavorites = visibleFavorites
                    .where(_matchesQuery)
                    .toList(growable: false);
                final visible = [
                  ...filteredOwned,
                  ...filteredFavorites,
                ];
                return Column(
                  children: [
                    if (_selectionMode)
                      _SelectionToolbar(
                        selectedCount: _selected.length,
                        totalCount: visible.length,
                        onSelectAll: () => _selectAll(visible),
                        onDelete: _selected.isEmpty
                            ? null
                            : () => _deleteSelected(visible),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                      child: SizedBox(height: 40, child: _searchField()),
                    ),
                    Expanded(
                      child: filteredOwned.isEmpty && filteredFavorites.isEmpty
                          ? const GEmptyState(
                              icon: Icons.search_off_rounded,
                              text: '没有匹配的歌单',
                            )
                          : RefreshIndicator(
                              onRefresh: () async {
                                final future = _reload();
                                if (future != null) await future;
                              },
                              child: ListView(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                children: [
                                  if (filteredOwned.isNotEmpty) ...[
                                    const _PlaylistSectionTitle('我的歌单'),
                                    ...filteredOwned.map(
                                      (playlist) => _playlistTile(
                                        playlist,
                                        selected: _selected.contains(
                                          _playlistKey(playlist),
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (filteredFavorites.isNotEmpty) ...[
                                    const _PlaylistSectionTitle('收藏的歌单'),
                                    ...filteredFavorites.map(
                                      (playlist) => _playlistTile(
                                        playlist,
                                        selected: _selected.contains(
                                          _playlistKey(playlist),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  bool _matchesQuery(Map<String, dynamic> playlist) {
    final normalized = _query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return userPlaylistName(playlist).toLowerCase().contains(normalized);
  }

  Widget _searchField() {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      style: TextStyle(fontSize: 14, color: scheme.onSurface),
      cursorColor: scheme.primary,
      decoration: InputDecoration(
        hintText: '搜索歌单',
        hintStyle: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
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
          borderSide: BorderSide(
            color: scheme.primary.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }

  void _enterSelection() {
    if (_mutating) return;
    setState(() => _selectionMode = true);
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  String _playlistKey(Map<String, dynamic> playlist) {
    final id = userPlaylistId(playlist) ?? '';
    return '${playlist['source'] ?? 'local'}:$id';
  }

  void _selectAll(List<Map<String, dynamic>> playlists) {
    setState(() {
      final keys = playlists.map(_playlistKey).toSet();
      if (keys.isNotEmpty && _selected.containsAll(keys)) {
        _selected.removeAll(keys);
      } else {
        _selected.addAll(keys);
      }
    });
  }

  void _toggleSelection(Map<String, dynamic> playlist) {
    final key = _playlistKey(playlist);
    setState(() {
      if (!_selected.add(key)) _selected.remove(key);
    });
  }

  Future<void> _deleteOne(Map<String, dynamic> playlist, String token) async {
    if (UserApi.isFavoritePlaylist(playlist)) {
      final source = playlist['source']?.toString().trim() ?? '';
      final sourceId = playlist['sourceId']?.toString().trim() ?? '';
      if (source.isEmpty || sourceId.isEmpty) {
        throw StateError('收藏歌单缺少来源信息');
      }
      await _api.removePlaylistFavorite(source, sourceId, token);
      return;
    }
    final id = userPlaylistId(playlist);
    if (id == null) throw StateError('歌单缺少记录 ID');
    await _api.deleteUserPlaylist(id, token);
  }

  Future<void> _deleteSelected(
    List<Map<String, dynamic>> visible,
  ) async {
    if (_mutating || _selected.isEmpty) return;
    final selected = visible
        .where((playlist) => _selected.contains(_playlistKey(playlist)))
        .toList(growable: false);
    final confirmed = await _confirmDelete(
      title: '删除所选歌单？',
      content: '将处理 ${selected.length} 个歌单，此操作无法撤销。',
    );
    if (!confirmed || !mounted) return;
    final token = context.read<AuthController>().token;
    if (token == null) return;
    setState(() => _mutating = true);
    var failed = 0;
    try {
      for (final playlist in selected) {
        try {
          await _deleteOne(playlist, token);
        } catch (_) {
          failed++;
        }
      }
      _exitSelection();
      await _refresh();
      if (mounted) _message(failed == 0 ? '歌单已删除' : '$failed 个歌单删除失败');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _deleteSingle(Map<String, dynamic> playlist) async {
    if (_mutating) return;
    final confirmed = await _confirmDelete(
      title: UserApi.isFavoritePlaylist(playlist) ? '取消收藏歌单？' : '删除歌单？',
      content: UserApi.isFavoritePlaylist(playlist)
          ? '歌单会从收藏列表移除。'
          : '歌单及其中的歌曲会被永久删除。',
    );
    if (!confirmed || !mounted) return;
    final token = context.read<AuthController>().token;
    if (token == null) return;
    setState(() => _mutating = true);
    try {
      await _deleteOne(playlist, token);
      await _refresh();
      if (mounted) _message('歌单已删除');
    } catch (error) {
      if (mounted) _message('删除失败：$error');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<bool> _confirmDelete({
    required String title,
    required String content,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(content),
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
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _playlistTile(
    Map<String, dynamic> playlist, {
    required bool selected,
  }) {
    final count = (playlist['trackCount'] as num?)?.toInt();
    return GListTile(
      leading: const Icon(Icons.queue_music_rounded),
      title: Text(userPlaylistName(playlist)),
      subtitle: count == null ? null : Text('$count 首歌曲'),
      selected: selected,
      trailing: _selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelection(playlist),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: '删除歌单',
                  size: 18,
                  padding: 8,
                  tint: Theme.of(context).colorScheme.outline,
                  backgroundColor: Colors.transparent,
                  onTap: () => _deleteSingle(playlist),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
      onTap: _selectionMode
          ? () => _toggleSelection(playlist)
          : () => _openPlaylist(playlist),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.selectedCount,
    required this.totalCount,
    required this.onSelectAll,
    required this.onDelete,
  });

  final int selectedCount;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        children: [
          Text('$selectedCount/$totalCount 已选'),
          const Spacer(),
          TextButton(onPressed: onSelectAll, child: const Text('全选')),
          GIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: '删除所选歌单',
            size: 18,
            padding: 9,
            onTap: onDelete,
          ),
        ],
      ),
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
