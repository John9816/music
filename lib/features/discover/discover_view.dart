import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/music_api.dart';
import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../../widgets/song_row.dart';
import '../playlists/playlist_detail_view.dart';
import '../search/artist_names_link.dart';

/// 发现页：问候 + 主推横幅 + 最新专辑 + 每日推荐
class DiscoverView extends StatefulWidget {
  const DiscoverView({
    super.key,
    this.title = '发现',
    this.subtitle,
    this.api,
  });

  final String title;
  final String? subtitle;
  final MusicApi? api;

  @override
  State<DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<DiscoverView> {
  late final MusicApi _api;
  final ScrollController _albumController = ScrollController();
  final _daily = _DiscoverSection<Song>();
  final _albums = _DiscoverSection<Album>();
  bool _albumAtStart = true;
  bool _albumAtEnd = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? MusicApi();
    _albumController.addListener(_syncAlbumScrollState);
    _reloadDaily();
    _reloadAlbums();
  }

  @override
  void dispose() {
    _albumController
      ..removeListener(_syncAlbumScrollState)
      ..dispose();
    super.dispose();
  }

  Future<void> _reloadDaily() => _loadSection(
        _daily,
        () => _api.getDailyRecommend(
          source: context.read<SettingsController>().source,
        ),
      );

  Future<void> _reloadAlbums() => _loadSection(
        _albums,
        () => _api.getNewestAlbums(
          source: context.read<SettingsController>().source,
        ),
      );

  Future<void> _loadSection<T>(
    _DiscoverSection<T> section,
    Future<List<T>> Function() loader,
  ) {
    final existing = section.loading;
    if (existing != null) return existing;
    if (!mounted) return Future<void>.value();

    // Each request owns its result and error; cached content stays mounted.
    final future = Future<List<T>>.sync(loader).then<void>(
      (data) {
        if (!mounted) return;
        setState(() {
          section.data = data;
          section.loading = null;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(() {
          section.error = error;
          section.loading = null;
        });
      },
    );
    setState(() {
      section.error = null;
      section.loading = future;
    });
    return future;
  }

  Future<void> _reload() async {
    await Future.wait([_reloadDaily(), _reloadAlbums()]);
  }

  double _featureHeight(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < GBreakpoints.compact) {
      return 268 + (MediaQuery.textScalerOf(context).scale(22) - 22) * 4;
    }
    final minimum =
        MediaQuery.sizeOf(context).width < GBreakpoints.compact ? 144.0 : 160.0;
    return (MediaQuery.textScalerOf(context).scale(20) * 5 + 24)
        .clamp(minimum, double.infinity)
        .toDouble();
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return '夜深了';
    if (h < 12) return '早上好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  void _syncAlbumScrollState() {
    if (!_albumController.hasClients) return;
    final position = _albumController.position;
    final atStart = position.pixels <= position.minScrollExtent + 0.5;
    final atEnd = position.pixels >= position.maxScrollExtent - 0.5;
    if (atStart == _albumAtStart && atEnd == _albumAtEnd) return;
    if (!mounted) return;
    setState(() {
      _albumAtStart = atStart;
      _albumAtEnd = atEnd;
    });
  }

  void _scrollAlbums(BuildContext context, int direction) {
    if (!_albumController.hasClients) return;
    final position = _albumController.position;
    final target =
        (position.pixels + position.viewportDimension * 0.82 * direction)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    final duration = PlatformMotion.duration(context, Motion.slow);
    if (duration == Duration.zero) {
      _albumController.jumpTo(target);
      return;
    }
    _albumController.animateTo(
      target,
      duration: duration,
      curve: PlatformMotion.curve(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daily = _daily.data;
    final albums = _albums.data;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncAlbumScrollState();
    });
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          key: const PageStorageKey('discover-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _buildHeader(
                context,
                refreshing: _daily.loading != null || _albums.loading != null,
              ),
            ),
            SliverToBoxAdapter(
              child: daily != null
                  ? _buildHero(context, daily)
                  : _daily.loading != null
                      ? _buildHeroSkeleton(context)
                      : const SizedBox.shrink(),
            ),
            SliverToBoxAdapter(
              child: SectionHeader(
                '最新专辑',
                action: albums == null
                    ? null
                    : _buildAlbumHeaderAction(context, albums.length),
              ),
            ),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  if (_albums.error != null)
                    _buildSectionError(
                      context,
                      title: '最新专辑',
                      hasData: albums != null,
                      onRetry: _reloadAlbums,
                    )
                  else
                    const SizedBox.shrink(),
                  if (albums != null)
                    _buildAlbums(context, albums)
                  else if (_albums.loading != null)
                    _buildAlbumSkeleton(context),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: SectionHeader(
                '每日推荐',
                subtitle: daily == null || daily.isEmpty ? null : '根据你的口味精选',
                action: daily == null || daily.isEmpty
                    ? null
                    : Text(
                        '${daily.length} 首',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
              ),
            ),
            SliverToBoxAdapter(
              child: _daily.error == null
                  ? const SizedBox.shrink()
                  : _buildSectionError(
                      context,
                      title: '每日推荐',
                      hasData: daily != null,
                      onRetry: _reloadDaily,
                    ),
            ),
            if (daily == null)
              SliverToBoxAdapter(
                child: _daily.loading == null
                    ? const SizedBox.shrink()
                    : const GSkeletonList(itemCount: 5),
              )
            else if (daily.isEmpty)
              SliverToBoxAdapter(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 150),
                  child: const GEmptyState(
                    icon: Icons.music_off_rounded,
                    text: '暂时没有推荐歌曲，稍后再来看看',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.zero,
                sliver: SliverList.builder(
                  itemCount: daily.length,
                  itemBuilder: (context, i) {
                    final song = daily[i];
                    // 首屏错峰淡入上浮；滚动复用不会重复播放。
                    return GListEntrance(
                      key: ValueKey('${song.source}:${song.id}'),
                      index: i,
                      child: SongRow(
                        song: song,
                        leading: MediaQuery.sizeOf(context).width >=
                                GBreakpoints.compact
                            ? _RankCover(
                                index: i,
                                coverUrl: song.album.picUrl,
                                scheme: Theme.of(context).colorScheme,
                              )
                            : null,
                        onTap: () => _play(context, daily, i),
                      ),
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
                child: SizedBox(
                    height: 24 + FloatingDockInsets.bottomOf(context))),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSkeleton(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < GBreakpoints.compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GSkeleton(
          width: double.infinity,
          height: _featureHeight(context),
          radius: 20,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: _featureHeight(context),
        child: const Row(
          children: [
            GSkeleton(width: 112, height: 112, radius: 8),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GSkeleton(width: 64, height: 12),
                  SizedBox(height: 12),
                  GSkeleton(width: double.infinity, height: 22),
                  SizedBox(height: 14),
                  GSkeleton(width: 88, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _albumSectionHeight(BuildContext context) =>
      _albumCoverSize(context) +
      26 +
      MediaQuery.textScalerOf(context).scale(_albumTitleSize(context)) * 1.35;

  Widget _buildAlbumSkeleton(BuildContext context) {
    return SizedBox(
      height: _albumSectionHeight(context),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GSkeleton(
              width: _albumCoverSize(context),
              height: _albumCoverSize(context),
              radius: 10,
            ),
            const SizedBox(height: 10),
            GSkeleton(
              width: _albumCoverSize(context),
              height: _albumTitleSize(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbums(BuildContext context, List<Album> albums) {
    if (albums.isEmpty) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 132),
        child: const GEmptyState(
          icon: Icons.album_outlined,
          text: '暂时没有新专辑',
        ),
      );
    }
    return SizedBox(
      height: _albumSectionHeight(context),
      child: ListView.separated(
        controller: _albumController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: albums.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) => _AlbumCard(
          album: albums[i],
          key: ValueKey(albums[i].detailId),
          onTap: () => _openAlbum(context, albums[i]),
        ),
      ),
    );
  }

  Widget _buildSectionError(
    BuildContext context, {
    required String title,
    required bool hasData,
    required VoidCallback onRetry,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title${hasData ? '刷新' : '加载'}失败，请稍后重试',
            style: TextStyle(
              fontSize: TypeScale.body,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          GButton(label: '重试$title', filled: false, onTap: onRetry),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {bool refreshing = false}) {
    if (_mobileLayout(context)) {
      return GPageHeader(
        title: widget.title,
        subtitle: widget.subtitle ?? '${_greeting()}，听点喜欢的',
      );
    }
    return GPageHeader(
      title: widget.title,
      subtitle: widget.subtitle ?? '${_greeting()}，看看今天的新鲜声音',
      actions: [
        GToolbarButton(
          icon: Icons.refresh_rounded,
          tooltip: '刷新',
          disabled: refreshing,
          onTap: _reload,
        ),
      ],
    );
  }

  Widget _buildAlbumHeaderAction(BuildContext context, int albumCount) {
    final count = Text(
      '$albumCount 张',
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
    final platform = Theme.of(context).platform;
    final desktop = platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
    if (!desktop) {
      return count;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        count,
        const SizedBox(width: 8),
        GIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: '上一组专辑',
          size: 18,
          padding: 7,
          disabled: _albumAtStart,
          backgroundColor: Colors.transparent,
          onTap: () => _scrollAlbums(context, -1),
        ),
        const SizedBox(width: 2),
        GIconButton(
          icon: Icons.arrow_forward_rounded,
          tooltip: '下一组专辑',
          size: 18,
          padding: 7,
          disabled: _albumAtEnd || albumCount == 0,
          backgroundColor: Colors.transparent,
          onTap: () => _scrollAlbums(context, 1),
        ),
      ],
    );
  }

  Widget _buildHero(BuildContext context, List<Song> daily) {
    if (daily.isEmpty) return const SizedBox.shrink();
    if (MediaQuery.sizeOf(context).width < GBreakpoints.compact) {
      return _buildFeaturedArtwork(context, daily);
    }
    final scheme = Theme.of(context).colorScheme;
    final hero = daily.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: _featureHeight(context),
        child: Row(
          children: [
            GPressScale(
              onTap: () => _play(context, daily, 0),
              child: Semantics(
                label: '播放 ${hero.name}',
                child:
                    AsyncCover(url: hero.album.picUrl, size: 112, radius: 10),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '今日主推',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: _mobileLayout(context) ? 13 : TypeScale.small,
                      fontWeight: TypeScale.medium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hero.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: TypeScale.title,
                      height: 1.15,
                      fontWeight: TypeScale.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ArtistNamesLink(
                          artists: hero.artists,
                          source: hero.source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize:
                                _mobileLayout(context) ? 15 : TypeScale.body,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GIconButton(
                        icon: Icons.play_arrow_rounded,
                        tooltip: '播放每日推荐',
                        filled: true,
                        onTap: () => _play(context, daily, 0),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedArtwork(BuildContext context, List<Song> daily) {
    final song = daily.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: _featureHeight(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AsyncCover(
                  url: song.album.picUrl, size: double.infinity, radius: 0),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xA6000000),
                        Color(0xA6000000),
                        Color(0x73000000),
                        Color(0xF2000000)
                      ],
                      stops: [0, 0.18, 0.4, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('今日主推',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: TypeScale.medium,
                          color: Colors.white,
                          height: 1.3,
                        )),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(song.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: TypeScale.semibold,
                                    height: 1.18,
                                    color: Colors.white)),
                            const SizedBox(height: 8),
                            ArtistNamesLink(
                                artists: song.artists,
                                source: song.source,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.3,
                                    color: Color(0xDDFFFFFF))),
                          ],
                        )),
                        const SizedBox(width: 14),
                        GIconButton(
                            icon: Icons.play_arrow_rounded,
                            tooltip: '播放每日推荐',
                            size: 27,
                            padding: 12,
                            tint: const Color(0xFF202126),
                            backgroundColor: Colors.white,
                            onTap: () => _play(context, daily, 0)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _play(BuildContext context, List<Song> songs, int index) {
    context.read<PlayerController>().playQueue(songs, index: index);
  }

  void _openAlbum(BuildContext context, Album album) {
    final source = context.read<SettingsController>().source;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailView(
          kind: PlaylistDetailKind.album,
          playlist: Playlist(
            id: album.id,
            name: album.name,
            source: source,
            coverUrl: album.picUrl,
          ),
          loader: () => _api.getAlbumDetail(
            album.detailId,
            source: source,
          ),
        ),
      ),
    );
  }
}

class _DiscoverSection<T> {
  List<T>? data;
  Object? error;
  Future<void>? loading;
}

/// 每日推荐：序号 + 封面（前 3 名红色高亮，网易云榜单风格）
class _RankCover extends StatelessWidget {
  const _RankCover({
    required this.index,
    required this.coverUrl,
    required this.scheme,
  });

  final int index;
  final String? coverUrl;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final top = index < 3;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 30,
          child: Text(
            '${index + 1}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: top ? 15 : 13,
              fontWeight: top ? FontWeight.w800 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: top ? scheme.primary : scheme.outline,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AsyncCover(url: coverUrl, size: 48, radius: 10),
        ),
      ],
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({super.key, required this.album, required this.onTap});

  final Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverSize = _albumCoverSize(context);
    return GPressScale(
      onTap: onTap,
      child: SizedBox(
        width: coverSize,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AsyncCover(url: album.picUrl, size: coverSize, radius: 10),
            const SizedBox(height: 10),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _albumTitleSize(context),
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _mobileLayout(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}

double _albumCoverSize(BuildContext context) =>
    _mobileLayout(context) ? 160 : 140;

double _albumTitleSize(BuildContext context) =>
    _mobileLayout(context) ? 15 : 13;
