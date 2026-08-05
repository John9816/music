import 'dart:io' show Platform;
import 'dart:math' show pi;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/song.dart';
import '../../core/player/lrc_parser.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/sleep_timer.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../profile/login_view.dart';
import '../profile/profile_view.dart';
import '../search/artist_names_link.dart';
import 'queue_view.dart';

enum _PlayerPane { lyrics, queue }

/// 全屏播放页：左侧封面与播放控制，右侧歌词/队列原位切换。
class PlayerView extends StatefulWidget {
  const PlayerView({super.key});

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  _PlayerPane _pane = _PlayerPane.lyrics;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final current = player.current;
    if (current == null) {
      return const Scaffold(body: Center(child: Text('暂无播放')));
    }
    final wide = MediaQuery.sizeOf(context).width >= 820;

    return Scaffold(
      backgroundColor: wide ? null : Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _AmbientBackground(
            coverUrl: current.album.picUrl,
            immersive: !wide,
          ),
          SafeArea(
            top: !Platform.isMacOS,
            child: Column(
              children: [
                _TopBar(song: wide ? null : current),
                Expanded(
                  child: wide
                      ? Row(
                          children: [
                            Expanded(
                              flex: 9,
                              child: _CoverAndControls(
                                song: current,
                                pane: _pane,
                                onPaneChanged: (pane) {
                                  setState(() => _pane = pane);
                                },
                              ),
                            ),
                            Expanded(
                              flex: 11,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(8, 8, 34, 26),
                                child: AnimatedSwitcher(
                                  duration: Motion.normal,
                                  child: _pane == _PlayerPane.lyrics
                                      ? _LyricView(
                                          key: const ValueKey('lyrics'),
                                          lrc: player.lyric,
                                        )
                                      : const _InlineQueueView(
                                          key: ValueKey('queue'),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : _MobilePlayer(song: current),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 氛围背景：模糊封面 + 深色/浅色蒙层 + 顶部品牌渐变
class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground({
    required this.coverUrl,
    this.immersive = false,
  });

  final String? coverUrl;
  final bool immersive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 模糊封面铺底
        ClipRect(
          child: Transform.scale(
            scale: immersive ? 1.22 : 1.08,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: immersive ? 54 : 70,
                sigmaY: immersive ? 54 : 70,
              ),
              child:
                  AsyncCover(url: coverUrl, size: double.infinity, radius: 0),
            ),
          ),
        ),
        // 蒙层：保证文字可读
        ColoredBox(
          color: immersive
              ? const Color(0xA6191718)
              : dark
                  ? Colors.black.withValues(alpha: 0.68)
                  : Colors.white.withValues(alpha: 0.82),
        ),
        // 顶部品牌渐变氛围
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                immersive
                    ? Colors.black.withValues(alpha: 0.34)
                    : scheme.primary.withValues(alpha: dark ? 0.20 : 0.10),
                immersive ? const Color(0x1A000000) : Colors.transparent,
                if (immersive) Colors.black.withValues(alpha: 0.48),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 顶部栏仅保留关闭按钮，让内容和原生红绿灯共享顶边。
class _TopBar extends StatelessWidget {
  const _TopBar({this.song});

  final Song? song;

  @override
  Widget build(BuildContext context) {
    final mobile = song != null;
    return SizedBox(
      height: Platform.isMacOS ? 42 : 58,
      child: mobile
          ? Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 6,
                  child: _ImmersiveIconButton(
                    icon: Icons.keyboard_arrow_down_rounded,
                    tooltip: '收起播放器',
                    size: 30,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 68),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        song!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: TypeScale.semibold,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        song!.artistNames,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.54),
                          fontSize: 11.5,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 6,
                  child: _ImmersiveIconButton(
                    icon: Icons.queue_music_rounded,
                    tooltip: '播放队列',
                    size: 23,
                    onTap: () => showQueueSheet(context),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                const Spacer(),
                GIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '关闭播放器',
                  size: 25,
                  padding: 11,
                  filled: true,
                  backgroundColor: glassFill(context, alpha: 0.10),
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 18),
              ],
            ),
    );
  }
}

/// 手机端播放器：沉浸歌词与唱片两种状态原位切换。
class _MobilePlayer extends StatefulWidget {
  const _MobilePlayer({required this.song});

  final Song song;

  @override
  State<_MobilePlayer> createState() => _MobilePlayerState();
}

class _MobilePlayerState extends State<_MobilePlayer> {
  bool _showLyrics = true;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    return Column(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Motion.emphasized,
            switchOutCurve: Curves.easeInCubic,
            child: _showLyrics
                ? _LyricView(
                    key: ValueKey('mobile-lyrics-${widget.song.id}'),
                    lrc: player.lyric,
                    immersive: true,
                  )
                : _MobileDiscStage(
                    key: ValueKey('mobile-disc-${widget.song.id}'),
                    song: widget.song,
                  ),
          ),
        ),
        if (player.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: _PlaybackErrorBanner(
              message: player.error!,
              actionLabel: _playbackActionLabel(player),
              onAction: () => _handlePlaybackError(context, player),
            ),
          ),
        _MobileControls(
          song: widget.song,
          showingLyrics: _showLyrics,
          onToggleView: () => setState(() => _showLyrics = !_showLyrics),
        ),
      ],
    );
  }
}

class _MobileDiscStage extends StatelessWidget {
  const _MobileDiscStage({super.key, required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final width = MediaQuery.sizeOf(context).width;
    final coverSize = (width * 0.72).clamp(230.0, 310.0);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DiscCover(
              url: song.album.picUrl,
              size: coverSize,
              playing: player.playing,
            ),
            const SizedBox(height: 34),
            Text(
              song.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: TypeScale.bold,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              song.artistNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileControls extends StatelessWidget {
  const _MobileControls({
    required this.song,
    required this.showingLyrics,
    required this.onToggleView,
  });

  final Song song;
  final bool showingLyrics;
  final VoidCallback onToggleView;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _FavoriteBtn(song: song, immersive: true),
              _ImmersiveIconButton(
                icon: showingLyrics
                    ? Icons.album_outlined
                    : Icons.lyrics_outlined,
                tooltip: showingLyrics ? '切换到唱片' : '切换到歌词',
                size: 22,
                onTap: onToggleView,
              ),
              _ImmersiveIconButton(
                icon: Icons.timer_outlined,
                tooltip: '睡眠定时',
                size: 22,
                onTap: () => _showSleepTimer(context),
              ),
              _ImmersiveIconButton(
                icon: Icons.queue_music_rounded,
                tooltip: '播放队列',
                size: 23,
                onTap: () => showQueueSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const _ProgressRow(immersive: true),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              const SizedBox(width: 46, height: 46),
              _ImmersiveIconButton(
                icon: Icons.skip_previous_rounded,
                tooltip: '上一首',
                size: 34,
                onTap: player.previous,
              ),
              _PlayPauseButton(
                playing: player.playing,
                loading: player.loading,
                onTap: player.togglePlay,
                large: true,
                immersive: true,
              ),
              _ImmersiveIconButton(
                icon: Icons.skip_next_rounded,
                tooltip: '下一首',
                size: 34,
                onTap: player.next,
              ),
              const SizedBox(width: 46, height: 46),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImmersiveIconButton extends StatelessWidget {
  const _ImmersiveIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 22,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GPressScale(
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              icon,
              size: size,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ),
      ),
    );
  }
}

/// 宽屏：封面 + 歌名 + 控制（左侧）
class _CoverAndControls extends StatelessWidget {
  const _CoverAndControls({
    required this.song,
    required this.pane,
    required this.onPaneChanged,
  });

  final Song song;
  final _PlayerPane pane;
  final ValueChanged<_PlayerPane> onPaneChanged;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverSize = (constraints.maxHeight * 0.43).clamp(220.0, 340.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(42, 18, 28, 24),
          child: Center(
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: ShadowToken.cover(context, radius: 38),
                    ),
                    child: AsyncCover(
                      url: song.album.picUrl,
                      size: coverSize,
                      radius: 12,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: TypeScale.heavy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ArtistNamesLink(
                              artists: song.artists,
                              source: song.source,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _FavoriteBtn(song: song),
                    ],
                  ),
                  if (player.error != null) ...[
                    const SizedBox(height: 14),
                    _PlaybackErrorBanner(
                      message: player.error!,
                      actionLabel: _playbackActionLabel(player),
                      onAction: () => _handlePlaybackError(context, player),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const _ProgressRow(),
                  const SizedBox(height: 13),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GIconButton(
                        icon: Icons.skip_previous_rounded,
                        tooltip: '上一首',
                        size: 34,
                        padding: 10,
                        onTap: player.previous,
                      ),
                      _PlayPauseButton(
                        playing: player.playing,
                        loading: player.loading,
                        onTap: player.togglePlay,
                        large: true,
                      ),
                      GIconButton(
                        icon: Icons.skip_next_rounded,
                        tooltip: '下一首',
                        size: 34,
                        padding: 10,
                        onTap: player.next,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _PlayerVolume(),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _PaneButton(
                        icon: Icons.lyrics_outlined,
                        selected: pane == _PlayerPane.lyrics,
                        onTap: () => onPaneChanged(_PlayerPane.lyrics),
                      ),
                      _PaneButton(
                        icon: Icons.timer_outlined,
                        onTap: () => _showSleepTimer(context),
                      ),
                      _PaneButton(
                        icon: Icons.queue_music_rounded,
                        selected: pane == _PlayerPane.queue,
                        onTap: () => onPaneChanged(_PlayerPane.queue),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PaneButton extends StatelessWidget {
  const _PaneButton({
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              selected ? glassFill(context, alpha: 0.16) : Colors.transparent,
          border: selected
              ? Border.all(color: Colors.white.withValues(alpha: 0.14))
              : null,
        ),
        child: Icon(icon, size: 21, color: scheme.onSurface),
      ),
    );
  }
}

class _PlayerVolume extends StatefulWidget {
  const _PlayerVolume();

  @override
  State<_PlayerVolume> createState() => _PlayerVolumeState();
}

class _PlayerVolumeState extends State<_PlayerVolume> {
  double? _dragFraction;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final volume = context.select<PlayerController, double>((p) => p.volume);
    final displayedVolume = _dragFraction ?? volume;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.volume_mute_rounded,
            size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              void update(double dx, {bool preview = false}) {
                final value =
                    (dx / constraints.maxWidth).clamp(0.0, 1.0).toDouble();
                if (preview) setState(() => _dragFraction = value);
                player.setVolume(value);
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => update(d.localPosition.dx),
                onHorizontalDragStart: (_) =>
                    setState(() => _dragFraction = volume),
                onHorizontalDragUpdate: (d) =>
                    update(d.localPosition.dx, preview: true),
                onHorizontalDragEnd: (_) =>
                    setState(() => _dragFraction = null),
                onHorizontalDragCancel: () =>
                    setState(() => _dragFraction = null),
                child: SizedBox(
                  height: 18,
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          Container(
                            height: 5,
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                          FractionallySizedBox(
                            widthFactor: displayedVolume.clamp(0.0, 1.0),
                            child: Container(height: 5, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Icon(Icons.volume_up_rounded, size: 16, color: scheme.onSurfaceVariant),
      ],
    );
  }
}

void _showSleepTimer(BuildContext context) {
  final timer = context.read<SleepTimer>();
  final player = context.read<PlayerController>();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '睡眠定时',
              style: TextStyle(fontSize: 17, fontWeight: TypeScale.bold),
            ),
          ),
          if (timer.isActive)
            GListTile(
              leading: const Icon(Icons.timer_off_outlined),
              title: Text('取消定时 · 剩余 ${timer.displayText}'),
              onTap: () {
                timer.stop();
                Navigator.of(sheetContext).pop();
              },
            ),
          for (final minutes in [15, 30, 45, 60, 90])
            GListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text('$minutes 分钟后暂停'),
              onTap: () {
                timer.start(
                  Duration(minutes: minutes),
                  onTimeout: player.pause,
                );
                Navigator.of(sheetContext).pop();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _InlineQueueView extends StatelessWidget {
  const _InlineQueueView({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final queue = context.select<PlayerController, List<Song>>((p) => p.queue);
    final queueIndex =
        context.select<PlayerController, int>((p) => p.queueIndex);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 28, 12, 12),
          child: Row(
            children: [
              const Text(
                '接下来播放',
                style: TextStyle(fontSize: 18, fontWeight: TypeScale.bold),
              ),
              const Spacer(),
              Text(
                '${queue.length} 首',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: queue.isEmpty
              ? Center(
                  child: Text(
                    '播放队列为空',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final song = queue[index];
                    final current = index == queueIndex;
                    return GPressScale(
                      onTap: () => player.playAt(index),
                      child: AnimatedContainer(
                        duration: Motion.fast,
                        height: 58,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: current
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Row(
                          children: [
                            AsyncCover(
                              url: song.album.picUrl,
                              size: 42,
                              radius: 7,
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
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: current
                                          ? TypeScale.bold
                                          : TypeScale.semibold,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  ArtistNamesLink(
                                    artists: song.artists,
                                    source: song.source,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (current)
                              Icon(
                                Icons.graphic_eq_rounded,
                                size: 18,
                                color: scheme.onSurface,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

String _playbackActionLabel(PlayerController player) {
  if (player.requiresMembership) return '去兑换 VIP';
  if (player.requiresLogin) return '去登录';
  return '重试';
}

void _handlePlaybackError(BuildContext context, PlayerController player) {
  if (player.requiresMembership) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileView()),
    );
  } else if (player.requiresLogin) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginView()),
    );
  } else {
    player.retry();
  }
}

class _PlaybackErrorBanner extends StatelessWidget {
  const _PlaybackErrorBanner({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(RadiusToken.md),
        border: Border.all(color: scheme.error.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
          ),
          const SizedBox(width: 6),
          GButton(
            label: actionLabel,
            small: true,
            filled: false,
            onTap: onAction,
          ),
        ],
      ),
    );
  }
}

/// 主播放/暂停按钮（暗色主题白色圆钮）
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.playing,
    required this.loading,
    required this.onTap,
    this.large = false,
    this.immersive = false,
  });

  final bool playing;
  final bool loading;
  final VoidCallback onTap;
  final bool large;
  final bool immersive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = large ? 64.0 : 56.0;
    return GPressScale(
      onTap: loading ? null : onTap,
      disabled: loading,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: immersive || dark ? Colors.white : scheme.primary,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: immersive || dark ? Colors.black : Colors.white,
                ),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: size * 0.52,
                color: immersive || dark ? Colors.black : Colors.white,
              ),
      ),
    );
  }
}

/// 收藏按钮：登录后红心状态 + 点击收藏/取消，未登录提示先登录
class _FavoriteBtn extends StatefulWidget {
  const _FavoriteBtn({required this.song, this.immersive = false});

  final Song song;
  final bool immersive;

  @override
  State<_FavoriteBtn> createState() => _FavoriteBtnState();
}

class _FavoriteBtnState extends State<_FavoriteBtn> {
  bool _fav = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _FavoriteBtn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) _refresh();
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) {
      if (mounted) setState(() => _fav = false);
      return;
    }
    try {
      final items = await UserApi().getFavorites(token);
      if (!mounted) return;
      setState(() {
        _fav = items.any(
          (e) =>
              e['songId'] == widget.song.id &&
              e['source'] == widget.song.source,
        );
      });
    } catch (_) {}
  }

  Future<void> _toggle() async {
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再收藏')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (_fav) {
        await UserApi()
            .removeFavorite(widget.song.id, widget.song.source, token);
      } else {
        await UserApi().addFavorite(widget.song, token);
      }
      if (mounted) {
        setState(() => _fav = !_fav);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_fav ? '已收藏' : '已取消收藏')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: _busy ? null : _toggle,
      disabled: _busy,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.immersive
              ? Colors.transparent
              : glassFill(context, alpha: 0.05),
          border: widget.immersive
              ? null
              : Border.all(color: glassHairline(context)),
        ),
        child: _busy
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                _fav ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                size: 22,
                color: _fav
                    ? AppBrand.favoriteRed
                    : widget.immersive
                        ? Colors.white.withValues(alpha: 0.92)
                        : scheme.onSurface,
              ),
      ),
    );
  }
}

/// 旋转碟片封面（播放时匀速旋转，暂停时停住）
class _DiscCover extends StatefulWidget {
  const _DiscCover({
    required this.url,
    required this.size,
    required this.playing,
  });

  final String? url;
  final double size;
  final bool playing;

  @override
  State<_DiscCover> createState() => _DiscCoverState();
}

class _DiscCoverState extends State<_DiscCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late bool _wasPlaying;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    _wasPlaying = widget.playing;
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _DiscCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing != _wasPlaying) {
      _wasPlaying = widget.playing;
      if (widget.playing) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * pi,
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 1.2,
          ),
          boxShadow: ShadowToken.cover(context, radius: 32),
        ),
        padding: EdgeInsets.all(widget.size * 0.07),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AsyncCover(
              url: widget.url,
              size: widget.size * 0.86,
              radius: widget.size * 0.43,
            ),
            // 中心轴帽
            Container(
              width: widget.size * 0.10,
              height: widget.size * 0.10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerLowest,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 进度条 + 时间（高频刷新，独立订阅 position/duration）
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({this.immersive = false});

  final bool immersive;

  @override
  Widget build(BuildContext context) {
    final duration =
        context.select<PlayerController, Duration?>((p) => p.duration);
    final player = context.read<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final timeStyle = TextStyle(
      fontSize: 11,
      color: immersive
          ? Colors.white.withValues(alpha: 0.48)
          : scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? player.position;
        final total = duration ?? Duration.zero;
        final remaining = total > position ? total - position : Duration.zero;
        return Row(
          children: [
            Text(_fmt(position), style: timeStyle),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Theme(
                  data: immersive
                      ? Theme.of(context).copyWith(
                          colorScheme: Theme.of(context).colorScheme.copyWith(
                                primary: Colors.white,
                                onSurface: Colors.white,
                              ),
                        )
                      : Theme.of(context),
                  child: GProgressBar(
                    position: position,
                    duration: duration ?? Duration.zero,
                    onSeek: player.seek,
                    height: 4,
                  ),
                ),
              ),
            ),
            Text('-${_fmt(remaining)}', style: timeStyle),
          ],
        );
      },
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 歌词视图：当前行高亮，自动滚动居中
class _LyricView extends StatefulWidget {
  const _LyricView({
    super.key,
    required this.lrc,
    this.immersive = false,
  });

  final String lrc;
  final bool immersive;

  @override
  State<_LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends State<_LyricView> {
  final ScrollController _controller = ScrollController();
  List<LrcLine> _lines = const [];
  int _lastCurrentLine = -1;

  @override
  void initState() {
    super.initState();
    _lines = parseLrc(widget.lrc);
  }

  @override
  void didUpdateWidget(covariant _LyricView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lrc != widget.lrc) {
      _lines = parseLrc(widget.lrc);
      _lastCurrentLine = -1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_lines.isEmpty) {
      final loading = context.select<PlayerController, bool>((p) => p.loading);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading && widget.lrc.isEmpty) ...[
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.immersive
                      ? Colors.white.withValues(alpha: 0.72)
                      : scheme.primary,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              loading && widget.lrc.isEmpty
                  ? '歌词加载中'
                  : widget.lrc.isEmpty
                      ? '暂无歌词'
                      : widget.lrc,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.immersive
                    ? Colors.white.withValues(alpha: 0.55)
                    : scheme.onSurfaceVariant,
                fontSize: widget.immersive ? 16 : null,
              ),
            ),
          ],
        ),
      );
    }
    final player = context.read<PlayerController>();
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? player.position;
        final current = _currentLineFor(position);
        _scheduleScroll(current);
        final lineHeight = widget.immersive ? 68.0 : 58.0;
        return LayoutBuilder(
          builder: (context, constraints) {
            final verticalPadding = widget.immersive
                ? (constraints.maxHeight - lineHeight) / 2
                : 100.0;
            Widget list = ListView.builder(
              controller: _controller,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                vertical: verticalPadding.clamp(0.0, double.infinity),
                horizontal: widget.immersive ? 34 : 30,
              ),
              itemCount: _lines.length,
              itemBuilder: (context, i) {
                final isCurrent = i == current;
                return Semantics(
                  button: true,
                  label: '跳转到 ${_formatLyricTime(_lines[i].time)}',
                  child: GPressScale(
                    onTap: () => player.seek(_lines[i].time),
                    scale: 0.985,
                    child: SizedBox(
                      height: lineHeight,
                      child: Align(
                        alignment: widget.immersive
                            ? Alignment.center
                            : Alignment.centerLeft,
                        child: AnimatedDefaultTextStyle(
                          duration: Motion.normal,
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            fontSize: widget.immersive
                                ? isCurrent
                                    ? 24
                                    : 17
                                : isCurrent
                                    ? 21
                                    : 15,
                            fontWeight:
                                isCurrent ? TypeScale.bold : TypeScale.semibold,
                            color: widget.immersive
                                ? Colors.white.withValues(
                                    alpha: isCurrent ? 1 : 0.38,
                                  )
                                : isCurrent
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant
                                        .withValues(alpha: 0.42),
                            height: 1.28,
                          ),
                          textAlign: widget.immersive
                              ? TextAlign.center
                              : TextAlign.left,
                          child: Text(
                            _lines[i].text.isEmpty ? '· · ·' : _lines[i].text,
                            maxLines: 2,
                            textAlign: widget.immersive
                                ? TextAlign.center
                                : TextAlign.left,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
            if (widget.immersive) {
              list = ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0, 0.14, 0.82, 1],
                ).createShader(bounds),
                blendMode: BlendMode.dstIn,
                child: list,
              );
            }
            return list;
          },
        );
      },
    );
  }

  int _currentLineFor(Duration position) {
    var low = 0;
    var high = _lines.length - 1;
    var current = 0;
    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      if (_lines[middle].time <= position) {
        current = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return current;
  }

  void _scheduleScroll(int current) {
    if (current == _lastCurrentLine) return;
    final initialAlignment = _lastCurrentLine == -1;
    _lastCurrentLine = current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_controller.hasClients) {
        _lastCurrentLine = -1;
        _scheduleScroll(current);
        return;
      }
      final lineHeight = widget.immersive ? 68.0 : 58.0;
      final target = widget.immersive
          ? current * lineHeight
          : current * lineHeight -
              _controller.position.viewportDimension / 2 +
              lineHeight / 2;
      if ((_controller.offset - target).abs() > 12) {
        final clampedTarget =
            target.clamp(0.0, _controller.position.maxScrollExtent);
        if (initialAlignment) {
          _controller.jumpTo(clampedTarget);
        } else {
          _controller.animateTo(
            clampedTarget,
            duration: Motion.slow,
            curve: Motion.emphasized,
          );
        }
      }
    });
  }

  String _formatLyricTime(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
