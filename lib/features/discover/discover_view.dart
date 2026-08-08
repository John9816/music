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
  late Future<(List<Song>, List<Album>)> _future;
  Future<(List<Song>, List<Album>)>? _loadingFuture;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? MusicApi();
    _future = _startLoad();
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

    final future = _load();
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

  void _reload() {
    if (!mounted) return;
    final future = _startLoad();
    if (identical(_future, future)) return;
    setState(() {
      _future = future;
    });
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return '夜深了';
    if (h < 12) return '早上好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const GLoading();
          }
          if (snapshot.hasError) {
            return GEmptyState(
              icon: Icons.wifi_off,
              text: '加载失败，请检查网络后重试',
              onRetry: _reload,
            );
          }
          final (daily, albums) = snapshot.data!;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: GPageHeader(
                  title: widget.title,
                  subtitle: widget.subtitle ?? '${_greeting()}，看看今天的新鲜声音',
                ),
              ),
              SliverToBoxAdapter(child: _buildHero(context, daily)),
              SliverToBoxAdapter(
                child: SectionHeader(
                  '最新专辑',
                  action: Text(
                    '${albums.length} 张',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 172,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: albums.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, i) => _AlbumCard(
                      album: albums[i],
                      onTap: () => _openAlbum(context, albums[i]),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SectionHeader(
                  '每日推荐',
                  subtitle: '根据你的口味精选',
                  action: Text(
                    '${daily.length} 首',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverList.builder(
                  itemCount: daily.length,
                  itemBuilder: (context, i) {
                    final song = daily[i];
                    return SongRow(
                      song: song,
                      leading: _RankCover(
                        index: i,
                        coverUrl: song.album.picUrl,
                        scheme: Theme.of(context).colorScheme,
                      ),
                      onTap: () => _play(context, daily, i),
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHero(BuildContext context, List<Song> daily) {
    if (daily.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final hero = daily.first;
    final wide = MediaQuery.sizeOf(context).width >= 560;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: GPressScale(
        onTap: () => _play(context, daily, 0),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(RadiusToken.md),
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
                border: Border.all(color: glassHairline(context)),
              ),
              height: wide ? 160 : null,
              padding: wide ? null : const EdgeInsets.all(16),
              child: wide
                  ? Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.22),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: AsyncCover(
                              url: hero.album.picUrl,
                              size: 132,
                              radius: RadiusToken.lg,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 18),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '今日主推',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.outline,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  hero.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: pageTitleStyle(context)
                                      .copyWith(fontSize: 20),
                                ),
                                const SizedBox(height: 4),
                                ArtistNamesLink(
                                  artists: hero.artists,
                                  source: hero.source,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13, color: scheme.outline),
                                ),
                                const SizedBox(height: 14),
                                GButton(
                                  label: '立即播放',
                                  icon: Icons.play_arrow,
                                  onTap: () => _play(context, daily, 0),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        AsyncCover(
                            url: hero.album.picUrl,
                            size: 118,
                            radius: RadiusToken.lg),
                        const SizedBox(height: 12),
                        Text(
                          '今日主推',
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.outline,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hero.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: pageTitleStyle(context).copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 2),
                        ArtistNamesLink(
                          artists: hero.artists,
                          source: hero.source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                        const SizedBox(height: 10),
                        GButton(
                          label: '立即播放',
                          icon: Icons.play_arrow,
                          onTap: () => _play(context, daily, 0),
                        ),
                      ],
                    ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '每日推荐',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
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
  const _AlbumCard({required this.album, required this.onTap});

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
              child: AsyncCover(url: album.picUrl, size: 140, radius: 14),
            ),
            const SizedBox(height: 8),
            Text(
              album.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
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
