import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/music_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../../widgets/playlist_card.dart';
import '../playlists/playlist_detail_view.dart';
import '../profile/login_view.dart';
import '../search/artist_names_link.dart';

/// 首页：问候 + 今日电台 + 快捷入口 + 正在流行 + 精选歌单
class HomeView extends StatefulWidget {
  const HomeView({super.key, this.onOpenSearch, this.onOpenLibrary});

  final VoidCallback? onOpenSearch;
  final VoidCallback? onOpenLibrary;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final MusicApi _api = MusicApi();
  late Future<List<Song>> _dailyFuture;
  late Future<List<Playlist>> _playlistsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _loadDaily();
    _loadPlaylists();
  }

  void _loadDaily() {
    final source = context.read<SettingsController>().source;
    _dailyFuture = _api.getDailyRecommend(source: source);
  }

  void _loadPlaylists() {
    final source = context.read<SettingsController>().source;
    _playlistsFuture = _api.getTopPlaylists(
      source: source,
      limit: 10,
    );
  }

  void _reload() => setState(_load);

  void _retryDaily() => setState(_loadDaily);

  void _retryPlaylists() => setState(_loadPlaylists);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        try {
          await Future.wait([_dailyFuture, _playlistsFuture]);
        } catch (_) {}
      },
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: _GreetingHeader()),
          SliverToBoxAdapter(child: _buildRadioSection(context)),
          SliverToBoxAdapter(
            child: FutureBuilder<List<Song>>(
              future: _dailyFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(height: 180, child: GLoading());
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return _LoadErrorSection(
                    title: '正在流行',
                    onRetry: _retryDaily,
                  );
                }
                final songs = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader('正在流行', subtitle: '今天值得留意的声音'),
                    SizedBox(
                      height: 166,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: songs.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, i) => _TrendingCard(
                          song: songs[i],
                          rank: i + 1,
                          onTap: () => _play(context, songs, i),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<List<Playlist>>(
              future: _playlistsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(height: 180, child: GLoading());
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return _LoadErrorSection(
                    title: '精选歌单',
                    onRetry: _retryPlaylists,
                  );
                }
                final playlists = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader('精选歌单', subtitle: '换一种节奏，继续听下去'),
                    SizedBox(
                      height: 196,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: playlists.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, i) => SizedBox(
                          width: 132,
                          child: PlaylistCard(
                            playlist: playlists[i],
                            onTap: () => _openDetail(context, playlists[i]),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  Widget _buildRadioSection(BuildContext context) {
    return FutureBuilder<List<Song>>(
      future: _dailyFuture,
      builder: (context, snapshot) {
        final radioSong = (snapshot.data != null && snapshot.data!.isNotEmpty)
            ? snapshot.data!.first
            : null;
        if (radioSong == null) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 760;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: desktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 138,
                            child: _RadioCard(song: radioSong),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 250,
                          child: Column(
                            children: [
                              _QuickActionCard(
                                icon: Icons.search_rounded,
                                label: '搜索',
                                tall: true,
                                onTap: widget.onOpenSearch,
                              ),
                              const SizedBox(height: 12),
                              _QuickActionCard(
                                icon: Icons.library_music_rounded,
                                label: '资料库',
                                tall: true,
                                onTap: widget.onOpenLibrary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _RadioCard(song: radioSong),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _QuickActionCard(
                                icon: Icons.search_rounded,
                                label: '搜索',
                                onTap: widget.onOpenSearch,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _QuickActionCard(
                                icon: Icons.library_music_rounded,
                                label: '资料库',
                                onTap: widget.onOpenLibrary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  void _play(BuildContext context, List<Song> songs, int index) {
    context.read<PlayerController>().playQueue(songs, index: index);
  }

  void _openDetail(BuildContext context, Playlist pl) {
    final source = context.read<SettingsController>().source;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailView(
          playlist: pl,
          loader: () => MusicApi().getPlaylistDetail(pl.id, source: source),
        ),
      ),
    );
  }
}

class _LoadErrorSection extends StatelessWidget {
  const _LoadErrorSection({required this.title, required this.onRetry});

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(RadiusToken.lg),
          border: Border.all(color: glassHairline(context)),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 21, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$title加载失败，请检查网络后重试',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            GButton(
              label: '重试',
              small: true,
              filled: false,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// 问候区：小号时间问候 + 大号用户名，与桌面端视觉层级一致。
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader();

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return '夜深了';
    if (h < 12) return '早上好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final scheme = Theme.of(context).colorScheme;
    final name = auth.username;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: TypeScale.semibold,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  auth.isLoggedIn ? name ?? '欢迎回来' : '今天想听点什么？',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pageTitleStyle(context),
                ),
              ],
            ),
          ),
          if (!auth.isLoggedIn)
            GButton(
              label: '登录',
              small: true,
              filled: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginView()),
              ),
            ),
        ],
      ),
    );
  }
}

/// 今日电台卡片
class _RadioCard extends StatelessWidget {
  const _RadioCard({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GPressScale(
      onTap: () => context.read<PlayerController>().playQueue([song]),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RadiusToken.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [
                    scheme.primary.withValues(alpha: 0.30),
                    scheme.primary.withValues(alpha: 0.08),
                    scheme.surfaceContainer.withValues(alpha: 0.6),
                  ]
                : [
                    AppBrand.red.withValues(alpha: 0.14),
                    AppBrand.red.withValues(alpha: 0.04),
                    scheme.surfaceContainer,
                  ],
          ),
          border: Border.all(color: glassHairline(context)),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: dark ? 0.14 : 0.08),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: AsyncCover(
                  url: song.album.picUrl,
                  size: 84,
                  radius: 14,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '今日电台',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: TypeScale.semibold,
                              color: scheme.primary,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: TypeScale.bold,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ArtistNamesLink(
                      artists: song.artists,
                      source: song.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 播放按钮
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppBrand.gradient(scheme.primary),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 28,
                  color: dark ? Colors.black : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 快捷入口卡片（搜索/资料库）
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    this.onTap,
    this.tall = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: Container(
        height: tall ? 63 : null,
        padding: EdgeInsets.symmetric(
          horizontal: tall ? 18 : 0,
          vertical: tall ? 0 : 13,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RadiusToken.lg),
          color: glassFill(context, alpha: 0.05),
          border: Border.all(color: glassHairline(context)),
        ),
        child: Row(
          mainAxisAlignment:
              tall ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: AppBrand.red),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: TypeScale.semibold,
              ),
            ),
            if (tall) ...[
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 正在流行：横滑歌曲卡（排名角标 + 封面 + 歌名）
class _TrendingCard extends StatelessWidget {
  const _TrendingCard({
    required this.song,
    required this.rank,
    required this.onTap,
  });

  final Song song;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: ShadowToken.card(context, radius: 12),
                  ),
                  child: AsyncCover(
                    url: song.album.picUrl,
                    size: 112,
                    radius: 14,
                  ),
                ),
                // 排名角标
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: TypeScale.bold,
                        color: rank <= 3 ? AppBrand.red : Colors.white,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              song.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: TypeScale.semibold,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            ArtistNamesLink(
              artists: song.artists,
              source: song.source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
