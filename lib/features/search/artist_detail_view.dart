import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/artist_info_api.dart';
import '../../core/api/music_api.dart';
import '../../core/models/artist_info.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../../widgets/song_row.dart';

class ArtistDetailView extends StatefulWidget {
  const ArtistDetailView({
    super.key,
    required this.artistName,
    this.artistId,
    this.source = 'netease',
    this.initialImageUrl,
    this.initialTrackCount,
    this.loader,
    this.catalogLoader,
  });

  final String artistName;
  final String? artistId;
  final String source;
  final String? initialImageUrl;
  final int? initialTrackCount;

  /// 可注入加载器，便于测试和复用。
  final Future<ArtistInfo> Function()? loader;
  final Future<ArtistCatalog> Function()? catalogLoader;

  @override
  State<ArtistDetailView> createState() => _ArtistDetailViewState();
}

class _ArtistDetailViewState extends State<ArtistDetailView> {
  final MusicApi _musicApi = MusicApi();
  late Future<ArtistInfo> _infoFuture;
  late Future<ArtistCatalog> _catalogFuture;
  int _selectedTab = 0;
  bool _bioExpanded = false;

  @override
  void initState() {
    super.initState();
    _infoFuture = _fetchInfo();
    _catalogFuture = _fetchCatalog();
  }

  Future<ArtistInfo> _fetchInfo() =>
      widget.loader?.call() ?? ArtistInfoApi().getArtistInfo(widget.artistName);

  Future<ArtistCatalog> _fetchCatalog() =>
      widget.catalogLoader?.call() ??
      _musicApi.getArtistCatalog(
        widget.artistName,
        artistId: widget.artistId,
        source: widget.source,
      );

  void _reloadInfo() => setState(() => _infoFuture = _fetchInfo());

  void _reloadCatalog() => setState(() => _catalogFuture = _fetchCatalog());

  void _playSongs(List<Song> songs, {int index = 0}) {
    if (songs.isEmpty) return;
    context.read<PlayerController>().playQueue(songs, index: index);
  }

  void _showAlbum(ArtistAlbum artistAlbum) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final height =
            math.min(MediaQuery.sizeOf(sheetContext).height * .78, 680.0);
        return SafeArea(
          top: false,
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Row(
                    children: [
                      AsyncCover(
                        url: artistAlbum.album.picUrl,
                        size: 64,
                        radius: RadiusToken.sm,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              artistAlbum.album.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: TypeScale.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('${artistAlbum.songs.length} 首歌曲'),
                          ],
                        ),
                      ),
                      GButton(
                        label: '播放',
                        icon: Icons.play_arrow_rounded,
                        small: true,
                        onTap: () => _playSongs(artistAlbum.songs),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: artistAlbum.songs.length,
                    itemBuilder: (context, index) => SongRow(
                      song: artistAlbum.songs[index],
                      onTap: () => _playSongs(artistAlbum.songs, index: index),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GAppBar(
        title: '歌手',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: FutureBuilder<ArtistInfo>(
        future: _infoFuture,
        builder: (context, infoSnapshot) {
          return FutureBuilder<ArtistCatalog>(
            future: _catalogFuture,
            builder: (context, catalogSnapshot) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 720;
                  final info = infoSnapshot.data;
                  final catalog = catalogSnapshot.data;
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      compact ? 18 : 36,
                      compact ? 24 : 34,
                      compact ? 18 : 36,
                      42,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ArtistHeader(
                              name: info?.name ?? widget.artistName,
                              imageUrl:
                                  info?.imageUrl ?? widget.initialImageUrl,
                              songCount: catalog?.songs.length ??
                                  widget.initialTrackCount,
                              albumCount: catalog?.albums.length,
                              compact: compact,
                              canPlay: catalog?.songs.isNotEmpty ?? false,
                              onPlay: () => _playSongs(catalog!.songs),
                            ),
                            const SizedBox(height: 30),
                            _buildTabs(catalog),
                            const SizedBox(height: 22),
                            _buildSelectedContent(
                              infoSnapshot,
                              catalogSnapshot,
                              compact: compact,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTabs(ArtistCatalog? catalog) {
    final songCount = catalog?.songs.length;
    final albumCount = catalog?.albums.length;
    return GSegmented(
      items: [
        '主页',
        songCount == null ? '歌曲' : '歌曲 $songCount',
        albumCount == null ? '专辑' : '专辑 $albumCount',
      ],
      selected: _selectedTab,
      onSelected: (index) => setState(() => _selectedTab = index),
    );
  }

  Widget _buildSelectedContent(
    AsyncSnapshot<ArtistInfo> infoSnapshot,
    AsyncSnapshot<ArtistCatalog> catalogSnapshot, {
    required bool compact,
  }) {
    return switch (_selectedTab) {
      0 => _buildOverview(infoSnapshot, catalogSnapshot, compact: compact),
      1 => _buildSongs(catalogSnapshot),
      _ => _buildAlbums(catalogSnapshot, compact: compact),
    };
  }

  Widget _buildOverview(
    AsyncSnapshot<ArtistInfo> infoSnapshot,
    AsyncSnapshot<ArtistCatalog> catalogSnapshot, {
    required bool compact,
  }) {
    final catalog = catalogSnapshot.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: '歌手简介',
          action: infoSnapshot.hasData && infoSnapshot.data!.profile.isNotEmpty
              ? GPressScale(
                  onTap: () => setState(() => _bioExpanded = !_bioExpanded),
                  child: Text(
                    _bioExpanded ? '收起' : '查看全部',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                )
              : null,
        ),
        _buildBio(infoSnapshot),
        const SizedBox(height: 30),
        _SectionTitle(
          title: '热门歌曲',
          action: catalog != null && catalog.songs.length > 5
              ? _TabAction(
                  label: '全部歌曲',
                  onTap: () => setState(() => _selectedTab = 1),
                )
              : null,
        ),
        _buildSongPreview(catalogSnapshot),
        const SizedBox(height: 30),
        _SectionTitle(
          title: '代表专辑',
          action: catalog != null && catalog.albums.length > (compact ? 2 : 4)
              ? _TabAction(
                  label: '全部专辑',
                  onTap: () => setState(() => _selectedTab = 2),
                )
              : null,
        ),
        _buildAlbumPreview(catalogSnapshot, compact: compact),
      ],
    );
  }

  Widget _buildBio(AsyncSnapshot<ArtistInfo> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const GLoading(padding: 18);
    }
    if (snapshot.hasError) {
      return _InlineError(
        message: snapshot.error.toString(),
        onRetry: _reloadInfo,
      );
    }
    final profile = snapshot.data?.profile ?? '';
    return Text(
      profile.isEmpty ? '暂无歌手简介' : profile,
      maxLines: _bioExpanded ? null : 5,
      overflow: _bioExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        height: 1.75,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildSongPreview(AsyncSnapshot<ArtistCatalog> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const GLoading(padding: 24);
    }
    if (snapshot.hasError) {
      return _InlineError(
        message: snapshot.error.toString(),
        onRetry: _reloadCatalog,
      );
    }
    final songs = snapshot.data?.songs ?? const <Song>[];
    if (songs.isEmpty) {
      return const _InlineEmpty(icon: Icons.music_off_rounded, text: '暂无歌曲');
    }
    final preview = songs.take(5).toList();
    return Column(
      children: [
        for (var index = 0; index < preview.length; index++)
          SongRow(
            song: preview[index],
            onTap: () => _playSongs(songs, index: index),
          ),
      ],
    );
  }

  Widget _buildAlbumPreview(
    AsyncSnapshot<ArtistCatalog> snapshot, {
    required bool compact,
  }) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const GLoading(padding: 24);
    }
    if (snapshot.hasError) {
      return _InlineError(
        message: snapshot.error.toString(),
        onRetry: _reloadCatalog,
      );
    }
    final albums = snapshot.data?.albums ?? const <ArtistAlbum>[];
    if (albums.isEmpty) {
      return const _InlineEmpty(icon: Icons.album_outlined, text: '暂无专辑');
    }
    return _AlbumGrid(
      albums: albums.take(compact ? 2 : 4).toList(),
      onTap: _showAlbum,
    );
  }

  Widget _buildSongs(AsyncSnapshot<ArtistCatalog> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const GLoading(padding: 60);
    }
    if (snapshot.hasError) {
      return GEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '歌曲加载失败',
        text: snapshot.error.toString(),
        onRetry: _reloadCatalog,
      );
    }
    final songs = snapshot.data?.songs ?? const <Song>[];
    if (songs.isEmpty) {
      return const GEmptyState(
        icon: Icons.music_off_rounded,
        text: '没有查询到该歌手的歌曲',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '全部歌曲',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
            GButton(
              label: '播放全部',
              icon: Icons.play_arrow_rounded,
              small: true,
              onTap: () => _playSongs(songs),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < songs.length; index++)
          SongRow(
            song: songs[index],
            onTap: () => _playSongs(songs, index: index),
          ),
      ],
    );
  }

  Widget _buildAlbums(
    AsyncSnapshot<ArtistCatalog> snapshot, {
    required bool compact,
  }) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const GLoading(padding: 60);
    }
    if (snapshot.hasError) {
      return GEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '专辑加载失败',
        text: snapshot.error.toString(),
        onRetry: _reloadCatalog,
      );
    }
    final albums = snapshot.data?.albums ?? const <ArtistAlbum>[];
    if (albums.isEmpty) {
      return const GEmptyState(
        icon: Icons.album_outlined,
        text: '没有查询到该歌手的专辑',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '全部专辑',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        _AlbumGrid(albums: albums, onTap: _showAlbum),
      ],
    );
  }
}

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({
    required this.name,
    required this.imageUrl,
    required this.songCount,
    required this.albumCount,
    required this.compact,
    required this.canPlay,
    required this.onPlay,
  });

  final String name;
  final String? imageUrl;
  final int? songCount;
  final int? albumCount;
  final bool compact;
  final bool canPlay;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final identity = Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          name,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: MediaQuery.sizeOf(context).width < 600 ? 28 : 34,
            fontWeight: TypeScale.heavy,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _countText(),
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        GButton(
          label: '播放热门歌曲',
          icon: Icons.play_arrow_rounded,
          onTap: canPlay ? onPlay : null,
        ),
      ],
    );

    if (compact) {
      return Center(
        child: Column(
          children: [
            _portrait(132),
            const SizedBox(height: 18),
            identity,
          ],
        ),
      );
    }
    return Row(
      children: [
        _portrait(174),
        const SizedBox(width: 28),
        Expanded(child: identity),
      ],
    );
  }

  String _countText() {
    final parts = <String>[];
    if (songCount != null) parts.add('$songCount 首歌曲');
    if (albumCount != null) parts.add('$albumCount 张专辑');
    return parts.isEmpty ? '歌手' : parts.join(' · ');
  }

  Widget _portrait(double size) => ClipOval(
        child: AsyncCover(
          url: imageUrl,
          size: size,
          radius: size / 2,
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: TypeScale.bold,
            ),
          ),
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _TabAction extends StatelessWidget {
  const _TabAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GPressScale(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({required this.albums, required this.onTap});

  final List<ArtistAlbum> albums;
  final ValueChanged<ArtistAlbum> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 840
            ? 5
            : constraints.maxWidth >= 600
                ? 4
                : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: albums.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 18,
            crossAxisSpacing: 16,
            childAspectRatio: .72,
          ),
          itemBuilder: (context, index) {
            final artistAlbum = albums[index];
            return GPressScale(
              onTap: () => onTap(artistAlbum),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: AsyncCover(
                      url: artistAlbum.album.picUrl,
                      size: double.infinity,
                      radius: RadiusToken.sm,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    artistAlbum.album.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: TypeScale.semibold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${artistAlbum.songs.length} 首歌曲',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 10),
        GButton(label: '重试', filled: false, small: true, onTap: onRetry),
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
