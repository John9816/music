import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/music_api.dart';
import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/utils/toast_helper.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../../widgets/song_row.dart';
import '../playlists/playlist_detail_view.dart';
import '../search/artist_names_link.dart';

/// 发现页：问候 + 主推横幅 + 每日推荐 + 最新专辑
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
  late Future<(List<Song>, List<Album>)> _future;
  Future<(List<Song>, List<Album>)>? _loadingFuture;
  (List<Song>, List<Album>)? _lastData;
  bool _albumAtStart = true;
  bool _albumAtEnd = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? MusicApi();
    _albumController.addListener(_syncAlbumScrollState);
    _future = _startLoad();
  }

  @override
  void dispose() {
    _albumController
      ..removeListener(_syncAlbumScrollState)
      ..dispose();
    super.dispose();
  }

  Future<(List<Song>, List<Album>)> _load() async {
    final source = context.read<SettingsController>().source;
    final results = await Future.wait<Object>([
      _api.getDailyRecommend(source: source),
      _api.getNewestAlbums(source: source),
    ]);
    return (results[0] as List<Song>, results[1] as List<Album>);
  }

  Future<(List<Song>, List<Album>)> _startLoad() {
    final existing = _loadingFuture;
    if (existing != null) return existing;

    final future = _load().then((data) {
      _lastData = data;
      return data;
    });
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

  Future<void> _reload() async {
    if (!mounted) return;
    final future = _startLoad();
    if (identical(_future, future)) return;
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      if (!mounted || _lastData == null) return;
      showAppToast(
        context,
        '刷新失败，请检查网络后重试',
        action: SnackBarAction(label: '重试', onPressed: _reload),
      );
    }
  }

  double _featureHeight(BuildContext context) {
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
    return Scaffold(
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              _lastData == null) {
            // 骨架屏匹配真实布局：页头 + Hero卡 + 专辑横条 + 歌曲列表
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: GPageHeader(
                    title: widget.title,
                    subtitle: widget.subtitle ?? '${_greeting()}，看看今天的新鲜声音',
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
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
                          )),
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SectionHeader('最新专辑')),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height:
                        164 + MediaQuery.textScalerOf(context).scale(13) * 1.35,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      scrollDirection: Axis.horizontal,
                      itemCount: 5,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, _) => const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GSkeleton(
                            width: 140,
                            height: 140,
                            radius: RadiusToken.sm,
                          ),
                          SizedBox(height: 8),
                          GSkeleton(width: 140, height: 13),
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                const SliverToBoxAdapter(
                  child: GSkeletonList(itemCount: 5),
                ),
              ],
            );
          }
          if (snapshot.hasError && _lastData == null) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: GPageHeader(
                      title: widget.title,
                      subtitle: widget.subtitle ?? '${_greeting()}，看看今天的新鲜声音',
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: GEmptyState(
                      icon: Icons.wifi_off,
                      text: '加载失败，请检查网络后重试',
                      onRetry: _reload,
                    ),
                  ),
                ],
              ),
            );
          }
          final (daily, albums) = _lastData ?? snapshot.data!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncAlbumScrollState();
          });
          final desktop = MediaQuery.sizeOf(context).width >= 600;
          return RefreshIndicator(
            onRefresh: _reload,
            child: CustomScrollView(
              key: const PageStorageKey('discover-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: GPageHeader(
                    title: widget.title,
                    subtitle: widget.subtitle ?? '${_greeting()}，看看今天的新鲜声音',
                    actions: desktop
                        ? [
                            GIconButton(
                              icon: Icons.refresh_rounded,
                              tooltip: '刷新',
                              disabled: snapshot.connectionState !=
                                  ConnectionState.done,
                              onTap: _reload,
                            ),
                          ]
                        : null,
                  ),
                ),
                SliverToBoxAdapter(child: _buildHero(context, daily)),
                SliverToBoxAdapter(
                  child: SectionHeader(
                    '最新专辑',
                    action: _buildAlbumHeaderAction(context, albums.length),
                  ),
                ),
                SliverToBoxAdapter(
                  child: albums.isEmpty
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 132),
                          child: const GEmptyState(
                            icon: Icons.album_outlined,
                            text: '暂时没有新专辑',
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final textScaler = MediaQuery.textScalerOf(context);
                            final scaledTextHeight = textScaler.scale(13.0);
                            final height =
                                140 + 8 + scaledTextHeight * 1.35 + 16;
                            return SizedBox(
                              height: height,
                              child: ListView.separated(
                                controller: _albumController,
                                scrollDirection: Axis.horizontal,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                itemCount: albums.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 14),
                                itemBuilder: (context, i) => _AlbumCard(
                                  album: albums[i],
                                  key: ValueKey(albums[i].detailId),
                                  onTap: () => _openAlbum(context, albums[i]),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                SliverToBoxAdapter(
                  child: SectionHeader(
                    '每日推荐',
                    subtitle: daily.isEmpty ? null : '根据你的口味精选',
                    action: daily.isEmpty
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
                if (daily.isEmpty)
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
                    padding: const EdgeInsets.symmetric(horizontal: 12),
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
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          );
        },
      ),
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
    final scheme = Theme.of(context).colorScheme;
    final hero = daily.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: SizedBox(
        height: _featureHeight(context),
        child: Row(
          children: [
            GPressScale(
              onTap: () => _play(context, daily, 0),
              child: Semantics(
                label: '播放 ${hero.name}',
                child: AsyncCover(url: hero.album.picUrl, size: 112, radius: 8),
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
                      fontSize: TypeScale.small,
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
                            fontSize: TypeScale.body,
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
    return GPressScale(
      onTap: onTap,
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AsyncCover(url: album.picUrl, size: 140, radius: 8),
            ),
            const SizedBox(height: 8),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
