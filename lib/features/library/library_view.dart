import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/services/song_download_service.dart';
import '../../core/services/user_playlist_library.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../playlists/create_playlist_dialog.dart';
import '../playlists/playlist_import_view.dart';
import '../profile/user_playlists_view.dart';
import '../profile/user_library_view.dart';
import '../profile/login_view.dart';
import 'downloads_view.dart';

/// Responsive overview of the user's playlists, favorites and offline music.
class LibraryView extends StatefulWidget {
  const LibraryView({
    super.key,
    required this.onOpenFavorites,
    required this.onOpenHistory,
    this.api,
    this.downloadService,
  });

  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenHistory;
  final UserApi? api;
  final SongDownloadService? downloadService;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  late final UserApi _api = widget.api ?? UserApi();
  late final SongDownloadService _downloads =
      widget.downloadService ?? SongDownloadService.instance;
  late final AuthController _auth;
  Future<_LibraryData>? _future;
  _LibraryData? _lastData;
  late int _lastSessionGeneration;
  int _sessionVersion = 0;
  int _requestVersion = 0;
  bool _downloadsReady = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthController>();
    _lastSessionGeneration = _auth.sessionGeneration;
    _auth.addListener(_onSessionChanged);
    UserPlaylistLibrary.instance.addListener(_onPlaylistLibraryChanged);
    _downloads.addListener(_onDownloadsChanged);
    _future = _loadLibrary();
    unawaited(_loadDownloads());
  }

  @override
  void dispose() {
    UserPlaylistLibrary.instance.removeListener(_onPlaylistLibraryChanged);
    _auth.removeListener(_onSessionChanged);
    _downloads.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onPlaylistLibraryChanged() {
    if (!mounted) return;
    unawaited(_refresh());
  }

  void _onSessionChanged() {
    if (!mounted || _lastSessionGeneration == _auth.sessionGeneration) return;
    _lastSessionGeneration = _auth.sessionGeneration;
    _lastData = null;
    _sessionVersion++;
    unawaited(_refresh());
  }

  void _onDownloadsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDownloads() async {
    try {
      await _downloads.initialize();
      if (mounted) setState(() => _downloadsReady = true);
    } catch (_) {
      // The download manager owns recovery; the overview must not invent a count.
    }
  }

  Future<_LibraryData> _loadLibrary() async {
    final request = ++_requestVersion;
    final session = _auth.sessionGeneration;
    final token = _auth.token;
    if (token == null) return const _LibraryData([]);
    final favorites = _api.getFavorites(token).then<int?>(
          (songs) => songs.length,
          onError: (Object _, StackTrace __) => null,
        );
    final playlists = await _api.getOwnedPlaylists(token);
    final data = _LibraryData(playlists, favoriteCount: await favorites);
    if (mounted &&
        request == _requestVersion &&
        session == _auth.sessionGeneration) {
      _lastData = data;
    }
    return data;
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final future = _loadLibrary();
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      // FutureBuilder presents the failure together with a retry action.
    }
  }

  Future<bool> _ensureSignedIn() async {
    if (_auth.isLoggedIn) return true;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginView()),
    );
    return mounted && _auth.isLoggedIn;
  }

  Future<void> _openCreatePlaylist() async {
    if (_creating) return;
    _creating = true;
    try {
      if (!await _ensureSignedIn() || !mounted) return;
      final session = _auth.sessionGeneration;
      final name = await showDialog<String>(
        context: context,
        builder: (_) => const CreatePlaylistDialog(),
      );
      final token = _auth.token;
      if (name == null ||
          name.isEmpty ||
          !mounted ||
          token == null ||
          session != _auth.sessionGeneration) {
        return;
      }
      try {
        await _api.createPlaylist(name, null, token);
        if (!mounted || session != _auth.sessionGeneration) return;
        _message('歌单已创建');
      } catch (_) {
        if (!mounted || session != _auth.sessionGeneration) return;
        _message('歌单创建失败，请稍后重试');
      }
    } finally {
      _creating = false;
    }
  }

  void _openImport() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PlaylistImportView(),
      ),
    );
  }

  Future<void> _openUserPlaylists() async {
    if (!await _ensureSignedIn()) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserPlaylistsView(api: _api)),
    );
  }

  void _openPlaylist(Map<String, dynamic> playlist) {
    final token = _auth.token;
    final id = userPlaylistId(playlist);
    if (token == null || id == null) return;
    final source = playlist['source']?.toString().trim();
    final sourceId = playlist['sourceId']?.toString().trim();
    final canSync = source != null &&
        source != 'local' &&
        source.isNotEmpty &&
        sourceId != null &&
        sourceId.isNotEmpty;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UserLibraryView(
        title: userPlaylistName(playlist),
        loader: () async {
          final items = await _api.getUserPlaylistSongs(id, token);
          return items.map(itemToSong).toList();
        },
        onSync: canSync ? () => _api.syncPlaylist(id, token) : null,
        onRemove: (song) async {
          final recordId = song.libraryId;
          if (recordId == null || recordId.isEmpty) {
            throw StateError('歌曲记录暂不可用，请刷新歌单');
          }
          await _api.deleteUserPlaylistSong(id, recordId, token);
        },
      ),
    ));
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final current = context.select<PlayerController, Song?>((p) => p.current);

    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final desktop = constraints.maxWidth >= GBreakpoints.contentSplit;
        final platform = Theme.of(context).platform;
        final mobile = platform == TargetPlatform.android ||
            platform == TargetPlatform.iOS;
        final padding = desktop && !mobile ? 24.0 : 20.0;
        return FutureBuilder<_LibraryData>(
          key: ValueKey(_sessionVersion),
          future: _future,
          builder: (context, snapshot) {
            final data = _auth.isLoggedIn ? snapshot.data ?? _lastData : null;
            final playlists = data?.playlists ?? const <Map<String, dynamic>>[];
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final hasError = snapshot.hasError && _auth.isLoggedIn;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _LibraryHeader(
                      onImport: _openImport,
                      onCreate: _openCreatePlaylist,
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    sliver: SliverToBoxAdapter(
                      child: _LibraryGrid(
                        flat: mobile,
                        playlistCount: data?.playlists.length,
                        favoriteCount: data?.favoriteCount,
                        downloadCount: _downloadsReady
                            ? _downloads.downloads.length
                            : null,
                        downloadingCount: _downloads.progress.length,
                        signedIn: _auth.isLoggedIn,
                        current: current,
                        onFavorites: widget.onOpenFavorites,
                        onHistory: widget.onOpenHistory,
                        onPlaylists: _openUserPlaylists,
                        onDownloads: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const DownloadsView()),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: mobile
                          ? EdgeInsets.zero
                          : EdgeInsets.fromLTRB(padding, 28, padding, 14),
                      child: SectionHeader(
                        '我的歌单',
                        subtitle: playlists.isEmpty
                            ? null
                            : '${playlists.length} 个歌单',
                        action: GIconButton(
                          icon: Icons.refresh_rounded,
                          tooltip: '刷新资料库',
                          onTap: loading ? null : _refresh,
                        ),
                      ),
                    ),
                  ),
                  if (hasError)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(padding, 0, padding, 16),
                        child: _LibraryNotice(
                          title: '资料库加载失败',
                          detail:
                              data == null ? '请检查网络连接后重试' : '已保留上次加载的内容，请重试更新',
                          action: '重试',
                          onTap: _refresh,
                        ),
                      ),
                    ),
                  if (!_auth.isLoggedIn)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: padding),
                        child: _LibraryNotice(
                          title: '登录后同步你的音乐',
                          detail: '在不同设备上查看收藏、歌单与播放历史',
                          action: '去登录',
                          onTap: _ensureSignedIn,
                        ),
                      ),
                    )
                  else if (loading && data == null)
                    const SliverToBoxAdapter(
                      child: SizedBox(
                          height: 120, child: Center(child: GLoading())),
                    )
                  else if (playlists.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      sliver: mobile
                          ? SliverLayoutBuilder(
                              builder: (context, constraints) {
                                final textScaler =
                                    MediaQuery.textScalerOf(context);
                                final columns =
                                    constraints.crossAxisExtent < 320 &&
                                            textScaler.scale(15) > 22.5
                                        ? 1
                                        : 2;
                                final coverSize = (constraints.crossAxisExtent -
                                        16 * (columns - 1)) /
                                    columns;
                                final cardHeight = coverSize +
                                    10 +
                                    textScaler.scale(15) * 1.25 * 2 +
                                    3 +
                                    textScaler.scale(13) * 1.2 +
                                    4;
                                return SliverGrid.builder(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 20,
                                    mainAxisExtent: cardHeight,
                                  ),
                                  itemCount: playlists.length,
                                  itemBuilder: (context, index) {
                                    final playlist = playlists[index];
                                    return _OwnedPlaylistRow(
                                      playlist: playlist,
                                      artworkFirst: true,
                                      onTap: () => _openPlaylist(playlist),
                                    );
                                  },
                                );
                              },
                            )
                          : SliverList.separated(
                              itemCount: playlists.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final playlist = playlists[index];
                                return _OwnedPlaylistRow(
                                  playlist: playlist,
                                  onTap: () => _openPlaylist(playlist),
                                );
                              },
                            ),
                    )
                  else if (!hasError)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: padding),
                        child: _PlaylistCallout(onCreate: _openCreatePlaylist),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}

class _LibraryData {
  const _LibraryData(this.playlists, {this.favoriteCount});
  final List<Map<String, dynamic>> playlists;
  final int? favoriteCount;
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.onImport, required this.onCreate});

  final VoidCallback onImport;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => GPageHeader(
        title: '资料库',
        inlineActions: true,
        actions: [
          GToolbarButton(
            icon: CupertinoIcons.link,
            tooltip: '导入歌单',
            onTap: onImport,
          ),
          GToolbarButton(
            icon: CupertinoIcons.add,
            tooltip: '新建歌单',
            onTap: onCreate,
          ),
        ],
      );
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.flat,
    required this.playlistCount,
    required this.favoriteCount,
    required this.downloadCount,
    required this.downloadingCount,
    required this.signedIn,
    required this.current,
    required this.onFavorites,
    required this.onHistory,
    required this.onPlaylists,
    required this.onDownloads,
  });

  final bool flat;
  final int? playlistCount;
  final int? favoriteCount;
  final int? downloadCount;
  final int downloadingCount;
  final bool signedIn;
  final Song? current;
  final VoidCallback onFavorites;
  final VoidCallback onHistory;
  final VoidCallback onPlaylists;
  final VoidCallback onDownloads;

  @override
  Widget build(BuildContext context) {
    final items = [
      _LibraryCard(
        flat: flat,
        icon: CupertinoIcons.heart_fill,
        title: flat ? '喜欢的音乐' : '喜欢',
        subtitle: !signedIn
            ? '登录后查看'
            : favoriteCount == null
                ? '查看收藏的歌曲'
                : '$favoriteCount 首歌曲',
        accent: true,
        onTap: onFavorites,
      ),
      _LibraryCard(
        flat: flat,
        icon: CupertinoIcons.clock_fill,
        title: '播放历史',
        subtitle: '查看完整记录',
        coverUrl: current?.album.picUrl,
        onTap: onHistory,
      ),
      _LibraryCard(
        flat: flat,
        icon: CupertinoIcons.bookmark_fill,
        title: '我的歌单',
        subtitle: playlistCount == null ? '整理喜欢的音乐' : '$playlistCount 个歌单',
        onTap: onPlaylists,
      ),
      _LibraryCard(
        flat: flat,
        icon: CupertinoIcons.arrow_down_circle_fill,
        title: flat ? '下载的音乐' : '下载',
        subtitle: downloadCount == null
            ? '管理离线音乐'
            : downloadingCount > 0
                ? '$downloadCount 首已下载 · $downloadingCount 首进行中'
                : '$downloadCount 首已下载',
        onTap: onDownloads,
      ),
    ];

    if (flat) {
      return Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            items[index],
            if (index != items.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.45),
                ),
              ),
          ],
        ],
      );
    }

    final largeText = MediaQuery.textScalerOf(context).scale(15) > 21;
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 340 ||
          largeText && constraints.maxWidth < 600) {
        return Column(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 92),
                child: items[index],
              ),
              if (index != items.length - 1) const SizedBox(height: 8),
            ],
          ],
        );
      }

      return Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: items[0]),
                const SizedBox(width: 10),
                Expanded(child: items[1]),
              ],
            ),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: items[2]),
                const SizedBox(width: 10),
                Expanded(child: items[3]),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.flat,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = false,
    this.coverUrl,
  });

  final bool flat;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool accent;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (flat) {
      return GPressScale(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Icon(icon,
                    size: 24,
                    color: accent
                        ? AppBrand.favoriteRed
                        : scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.25,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
              ),
            ],
          ),
        ),
      );
    }
    return GPressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 14, 13, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent
                        ? AppBrand.favoriteRed.withValues(alpha: 0.12)
                        : scheme.onSurface.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    icon,
                    size: 14,
                    color: accent ? AppBrand.favoriteRed : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.1,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Positioned(
              top: 1,
              right: 0,
              child: coverUrl == null || coverUrl!.isEmpty
                  ? Icon(
                      CupertinoIcons.chevron_right,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    )
                  : AsyncCover(url: coverUrl, size: 38, radius: 7),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnedPlaylistRow extends StatelessWidget {
  const _OwnedPlaylistRow({
    required this.playlist,
    required this.onTap,
    this.artworkFirst = false,
  });

  final Map<String, dynamic> playlist;
  final VoidCallback onTap;
  final bool artworkFirst;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = playlist['coverImgUrl'] ??
        playlist['coverUrl'] ??
        playlist['picUrl'] ??
        playlist['cover'];
    final count = playlist['trackCount'] ?? playlist['songCount'];
    final subtitle = count == null
        ? (playlist['source'] == null || playlist['source'] == 'local'
            ? '自建歌单'
            : '导入歌单')
        : '$count 首歌曲';
    if (artworkFirst) {
      return GPressScale(
        onTap: userPlaylistId(playlist) == null ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: AsyncCover(
                url: cover?.toString(),
                size: double.infinity,
                radius: 10,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              userPlaylistName(playlist),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                height: 1.25,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.2,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return GPressScale(
      onTap: userPlaylistId(playlist) == null ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(RadiusToken.lg),
        ),
        child: Row(children: [
          AsyncCover(url: cover?.toString(), size: 52, radius: RadiusToken.sm),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(userPlaylistName(playlist),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: TypeScale.semibold)),
              const SizedBox(height: 5),
              Text(subtitle,
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          )),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant, size: 20),
        ]),
      ),
    );
  }
}

class _LibraryNotice extends StatelessWidget {
  const _LibraryNotice(
      {required this.title,
      required this.detail,
      required this.action,
      required this.onTap});

  final String title;
  final String detail;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GSurface(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: TypeScale.semibold)),
          const SizedBox(height: 6),
          Text(detail,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          GButton(label: action, onTap: onTap, small: true),
        ]),
      );
}

class _PlaylistCallout extends StatelessWidget {
  const _PlaylistCallout({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.music_note_2,
            size: 17,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '把喜欢的歌整理成自己的歌单',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onCreate,
            style: TextButton.styleFrom(
              foregroundColor: scheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              minimumSize: const Size(44, 44),
            ),
            child: const Text(
              '新建',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
