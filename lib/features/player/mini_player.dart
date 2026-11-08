import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/player/playback_time.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../../widgets/playback_mode_button.dart';
import '../../widgets/floating_dock_surface.dart';
import '../search/artist_names_link.dart';
import 'desktop_player_panel.dart';
import 'player_view.dart';
import 'queue_view.dart';

/// 全局播放栏。桌面端横跨侧栏和内容区，窄屏保留紧凑控制。
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({
    super.key,
    this.sidebarWidth,
    this.collapsed = false,
    this.panel,
    this.onPanelChanged,
  });

  final double? sidebarWidth;
  final bool collapsed;
  final MiniPlayerPanel? panel;
  final ValueChanged<MiniPlayerPanel?>? onPanelChanged;

  static double mobileHeight(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return math.max(
      64.0,
      textScaler.scale(15.5) * 1.2 + 20,
    );
  }

  /// Shared with the shell so docked panels clear the entire playback bar.
  static double desktopHeight(BuildContext context) {
    final platform = Theme.of(context).platform;
    final touch =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final transportHeight = platform == TargetPlatform.android ? 48 : 44;
    final progressHeight = touch ? 44 : 28;
    final textScaler = MediaQuery.textScalerOf(context);
    return math.max(
      transportHeight + progressHeight + 8.0,
      (textScaler.scale(TypeScale.bodyLarge) + textScaler.scale(12.5)) * 1.4 +
          22,
    );
  }

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  bool _favoriteBusy = false;
  bool _playerOpen = false;

  Future<void> _openPlayer() async {
    if (_playerOpen) return;
    _playerOpen = true;
    try {
      await Navigator.of(context).push(
        buildPlayerRoute(
          reducedMotion: MediaQuery.disableAnimationsOf(context),
        ),
      );
    } finally {
      _playerOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = context.select<PlayerController, Song?>((p) => p.current);
    final duration = PlatformMotion.duration(context, Motion.normal);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= GBreakpoints.desktopPlayer &&
            widget.sidebarWidth != null;
        final height = widget.collapsed
            ? 60.0
            : desktop
                ? MiniPlayer.desktopHeight(context)
                : MiniPlayer.mobileHeight(context);
        final content = current == null
            ? const SizedBox.shrink(key: ValueKey('mini-player-empty'))
            : KeyedSubtree(
                key: const ValueKey('mini-player-active'),
                child: _surface(
                  context,
                  current,
                  desktop: desktop,
                  height: height,
                ),
              );
        if (duration == Duration.zero) return content;
        return AnimatedSize(
          duration: duration,
          curve: PlatformMotion.curve(context),
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: PlatformMotion.curve(context),
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: content,
          ),
        );
      },
    );
  }

  Widget _surface(
    BuildContext context,
    Song current, {
    required bool desktop,
    required double height,
  }) {
    if (widget.collapsed) {
      final error = context.select<PlayerController, String?>((p) => p.error);
      return FloatingDockSurface(
        surfaceKey: const ValueKey('mobile-player-disc-shortcut'),
        child: Tooltip(
          message: '打开播放器',
          child: Semantics(
            button: true,
            label: '打开播放器，${current.name}，${current.artistNames}'
                '${error == null ? '' : '，$error'}',
            onTap: _openPlayer,
            excludeSemantics: true,
            child: GPressScale(
              onTap: _openPlayer,
              scale: .92,
              borderRadius: BorderRadius.circular(999),
              child: SizedBox.square(
                dimension: 60,
                child: Center(child: _PlayerDisc(song: current, size: 50)),
              ),
            ),
          ),
        ),
      );
    }
    if (!desktop) {
      return FloatingDockSurface(
        surfaceKey: const ValueKey('mobile-mini-player-surface'),
        child: SizedBox(
          height: height,
          child: _compactBar(context, current),
        ),
      );
    }
    return Container(
      key: const ValueKey('desktop-mini-player-surface'),
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: glassHairline(context))),
      ),
      child: _desktopBar(context, current),
    );
  }

  // ignore: unused_element
  Widget _emptyDesktopBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.32);
    final trackAreaWidth = (widget.sidebarWidth ?? 264) + 64;
    Widget icon(IconData value, double size) =>
        Icon(value, size: size, color: muted);

    return Row(
      children: [
        SizedBox(
          width: trackAreaWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: icon(CupertinoIcons.music_note_2, 21),
                ),
                const SizedBox(width: 10),
                Text(
                  '暂未播放',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: TypeScale.semibold,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 80,
          child: icon(CupertinoIcons.heart, 21),
        ),
        SizedBox(
          width: 400,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                SizedBox(
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      icon(CupertinoIcons.shuffle, 16),
                      const SizedBox(width: 18),
                      icon(CupertinoIcons.backward_end_fill, 22),
                      const SizedBox(width: 18),
                      icon(CupertinoIcons.play_fill, 23),
                      const SizedBox(width: 18),
                      icon(CupertinoIcons.forward_end_fill, 22),
                      const SizedBox(width: 18),
                      icon(CupertinoIcons.repeat, 16),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text('0:00',
                        style: TextStyle(fontSize: 10.5, color: muted)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: muted.withValues(alpha: 0.48),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('-0:00',
                        style: TextStyle(fontSize: 10.5, color: muted)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: 260,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                icon(CupertinoIcons.volume_down, 18),
                const SizedBox(width: 9),
                Container(
                  width: 76,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 9),
                icon(CupertinoIcons.volume_up, 18),
                const SizedBox(width: 14),
                icon(CupertinoIcons.speaker_2, 19),
                const SizedBox(width: 13),
                icon(CupertinoIcons.text_bubble, 19),
                const SizedBox(width: 13),
                icon(CupertinoIcons.list_bullet, 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _desktopBar(BuildContext context, Song current) {
    final player = context.read<PlayerController>();
    final liked = context.select<PlayerController, bool>((p) => p.liked);
    final trackAreaWidth =
        ((widget.sidebarWidth ?? 264) + 64).clamp(220.0, 360.0);
    return Row(
      children: [
        SizedBox(
          width: trackAreaWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: _TrackIdentity(
              song: current,
              coverSize: 52,
              onTap: _openPlayer,
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Center(
            child: _PlayerIconButton(
              icon: liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
              size: 21,
              padding: 8,
              tooltip: liked ? '取消收藏' : '收藏歌曲',
              selected: liked,
              tint: liked ? AppBrand.favoriteRed : null,
              onTap:
                  _favoriteBusy ? null : () => _toggleFavorite(current, player),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _transportControls(context, player),
                const SizedBox(height: 2),
                _PlaybackTimeline(
                    key: ValueKey((current.source, current.id)),
                    showTimes: true),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 320,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _rightTools(context, player),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleFavorite(
    Song song,
    PlayerController player,
  ) async {
    final token = context.read<AuthController>().token;
    if (token == null) {
      _message('请先登录后再收藏');
      return;
    }
    final wasLiked = player.liked;
    setState(() => _favoriteBusy = true);
    try {
      if (wasLiked) {
        await UserApi().removeFavorite(song.id, song.source, token);
      } else {
        await UserApi().addFavorite(song, token);
      }
      if (!mounted || context.read<AuthController>().token != token) return;
      final current = player.current;
      if (current?.id != song.id || current?.source != song.source) return;
      player.setLiked(!wasLiked);
      _message(wasLiked ? '已取消收藏' : '已收藏');
    } catch (_) {
      _message('操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _compactBar(BuildContext context, Song current) {
    final player = context.read<PlayerController>();
    final platform = Theme.of(context).platform;
    final touch =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            Expanded(
              child: _CompactTrackIdentity(song: current, onTap: _openPlayer),
            ),
            const SizedBox(width: 2),
            if (touch || constraints.maxWidth >= 500)
              _PlayerIconButton(
                icon: CupertinoIcons.backward_end_fill,
                size: 21,
                padding: 7,
                tooltip: '上一首',
                onTap: player.previous,
              ),
            _PlayButton(player: player, size: 32, filled: touch),
            if (touch || constraints.maxWidth >= 380)
              _PlayerIconButton(
                icon: CupertinoIcons.forward_end_fill,
                size: 21,
                padding: 7,
                tooltip: '下一首',
                onTap: player.next,
              ),
            if (!touch)
              _PlayerIconButton(
                icon: CupertinoIcons.list_bullet,
                size: 20,
                padding: 7,
                tooltip: '播放队列',
                onTap: () => showQueueSheet(context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _transportControls(
    BuildContext context,
    PlayerController player,
  ) {
    final mode =
        context.select<PlayerController, PlaybackMode>((p) => p.playbackMode);
    return SizedBox(
      height: Theme.of(context).platform == TargetPlatform.android ? 48 : 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PlayerIconButton(
            icon: mode.icon,
            size: 20,
            padding: 8,
            tooltip: mode.label,
            onTap: player.cyclePlaybackMode,
          ),
          _PlayerIconButton(
            icon: CupertinoIcons.backward_end_fill,
            size: 20,
            padding: 6,
            tooltip: '上一首',
            onTap: player.previous,
          ),
          _PlayButton(player: player, size: 28),
          _PlayerIconButton(
            icon: CupertinoIcons.forward_end_fill,
            size: 20,
            padding: 6,
            tooltip: '下一首',
            onTap: player.next,
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _rightTools(BuildContext context, PlayerController player) {
    final volume = context.select<PlayerController, double>((p) => p.volume);
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxWidth < 200;
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _PlayerIconButton(
              icon: volume <= 0
                  ? CupertinoIcons.volume_off
                  : CupertinoIcons.volume_down,
              size: 18,
              padding: 6,
              tooltip: volume <= 0 ? '取消静音' : '静音',
              onTap: () => player.setVolume(volume <= 0 ? 0.7 : 0),
            ),
            if (!dense) ...[
              const SizedBox(width: 3),
              _VolumeBar(value: volume, onChanged: player.setVolume),
              const SizedBox(width: 5),
              Icon(
                CupertinoIcons.volume_up,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
            const SizedBox(width: 6),
            _PlayerIconButton(
              icon: CupertinoIcons.speaker_2,
              size: 19,
              padding: 6,
              tooltip: '打开播放器',
              onTap: _openPlayer,
            ),
            _PlayerIconButton(
              icon: CupertinoIcons.text_bubble,
              size: 19,
              padding: 6,
              tooltip: '歌词',
              selected: widget.panel == MiniPlayerPanel.lyrics,
              onTap: () => _togglePanel(MiniPlayerPanel.lyrics, _openPlayer),
            ),
            _PlayerIconButton(
              icon: CupertinoIcons.list_bullet,
              size: 20,
              padding: 6,
              tooltip: '播放队列',
              selected: widget.panel == MiniPlayerPanel.queue,
              onTap: () => _togglePanel(
                MiniPlayerPanel.queue,
                () => showQueueSheet(context),
              ),
            ),
          ],
        );
      },
    );
  }

  void _togglePanel(MiniPlayerPanel panel, VoidCallback fallback) {
    final onChanged = widget.onPanelChanged;
    if (onChanged == null) {
      fallback();
      return;
    }
    onChanged(widget.panel == panel ? null : panel);
  }
}

class _PlayerDisc extends StatelessWidget {
  const _PlayerDisc({required this.song, required this.size, super.key});

  final Song song;
  final double size;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final duration =
        context.select<PlayerController, Duration?>((value) => value.duration);
    final hasError =
        context.select<PlayerController, bool>((value) => value.error != null);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFA8BDC9), width: 1.6),
              gradient: const RadialGradient(
                colors: [
                  Color(0xFF18212A),
                  Color(0xFF18212A),
                  Color(0xFF7B8B98),
                  Color(0xFF17202A),
                  Color(0xFF536673),
                  Color(0xFF18212A),
                ],
                stops: [0, .62, .65, .71, .80, .86],
              ),
            ),
            alignment: Alignment.center,
            child: AsyncCover(
              url: song.album.picUrl,
              size: size * .57,
              radius: size,
            ),
          ),
          Positioned.fill(
            child: StreamBuilder<Duration>(
              stream: player.positionStream,
              initialData: player.position,
              builder: (context, snapshot) => CircularProgressIndicator(
                key: const ValueKey('mobile-player-disc-progress'),
                value: playbackProgressFraction(
                  snapshot.data ?? player.position,
                  duration ?? Duration.zero,
                ),
                strokeWidth: 1.4,
                color: const Color(0xFFB9CFDC),
                backgroundColor: const Color(0xFF728590).withValues(alpha: .35),
              ),
            ),
          ),
          if (hasError)
            Positioned(
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                key: const ValueKey('mobile-player-error-badge'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.error,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.priority_high_rounded,
                  size: 15,
                  color: Theme.of(context).colorScheme.onError,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayerIconButton extends StatelessWidget {
  const _PlayerIconButton({
    required this.icon,
    required this.onTap,
    required this.size,
    required this.padding,
    this.tint,
    this.tooltip,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double padding;
  final Color? tint;
  final String? tooltip;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final targetSize = switch (Theme.of(context).platform) {
      TargetPlatform.android => 48.0,
      _ => 44.0,
    };
    Widget button = GPressScale(
      onTap: onTap,
      scale: 0.92,
      borderRadius: BorderRadius.circular(RadiusToken.pill),
      child: SizedBox.square(
        dimension: targetSize,
        child: Center(
          child: AnimatedContainer(
            duration: PlatformMotion.duration(context, Motion.fast),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? scheme.onSurface.withValues(alpha: 0.11)
                  : Colors.transparent,
            ),
            child: Center(
              child: Icon(
                icon,
                size: size,
                color: tint ?? scheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: tooltip,
      onTap: onTap,
      excludeSemantics: true,
      child: button,
    );
  }
}

class _TrackIdentity extends StatelessWidget {
  const _TrackIdentity({
    required this.song,
    required this.coverSize,
    required this.onTap,
  });

  final Song song;
  final double coverSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loading = context.select<PlayerController, bool>((p) => p.loading);
    final error = context.select<PlayerController, String?>((p) => p.error);
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: coverSize,
            height: coverSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: ShadowToken.card(context, radius: 10),
            ),
            child: AsyncCover(
              url: song.album.picUrl,
              size: coverSize,
              radius: 8,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: TypeScale.bodyLarge,
                          fontWeight: TypeScale.semibold,
                        ),
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(width: 7),
                      const SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                if (error == null)
                  ArtistNamesLink(
                    artists: song.artists,
                    source: song.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else
                  Text(
                    error,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: scheme.error),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactTrackIdentity extends StatelessWidget {
  const _CompactTrackIdentity({required this.song, required this.onTap});

  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final error = context.select<PlayerController, String?>((p) => p.error);
    return Semantics(
      button: true,
      label:
          '${song.name}，${song.artistNames}${error == null ? '' : '，$error'}，打开播放器',
      onTap: onTap,
      excludeSemantics: true,
      child: GPressScale(
        onTap: onTap,
        scale: .98,
        borderRadius: BorderRadius.circular(999),
        child: Row(
          children: [
            _PlayerDisc(
              key: const ValueKey('mobile-mini-player-artwork'),
              song: song,
              size: 48,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: PlatformMotion.duration(context, Motion.normal),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: Text(
                  error ?? song.name,
                  key: ValueKey((song.source, song.id, song.name, error)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: error == null
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.error,
                    fontSize: 15.5,
                    fontWeight: TypeScale.semibold,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.player,
    required this.size,
    this.filled = false,
  });

  final bool filled;
  final PlayerController player;
  final double size;

  @override
  Widget build(BuildContext context) {
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final loading = context.select<PlayerController, bool>((p) => p.loading);
    final hasError =
        context.select<PlayerController, bool>((p) => p.error != null);
    final scheme = Theme.of(context).colorScheme;
    final minimumTargetSize = switch (Theme.of(context).platform) {
      TargetPlatform.android => 48.0,
      _ => 44.0,
    };
    final targetSize = filled ? 48.0 : math.max(size, minimumTargetSize);
    final foreground = filled ? const Color(0xFF182A38) : scheme.onSurface;
    final label = loading
        ? '正在加载'
        : hasError
            ? '重试'
            : playing
                ? '暂停'
                : '播放';
    final VoidCallback? onTap = loading
        ? null
        : hasError
            ? player.retry
            : player.togglePlay;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        enabled: !loading,
        onTap: onTap,
        excludeSemantics: true,
        child: GPressScale(
          onTap: onTap,
          scale: 0.94,
          borderRadius: BorderRadius.circular(RadiusToken.pill),
          child: Container(
            width: targetSize,
            height: targetSize,
            decoration: filled
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFCDDAE3),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: .7)),
                  )
                : null,
            child: Center(
              child: SizedBox(
                width: size,
                height: size,
                child: AnimatedSwitcher(
                  duration: PlatformMotion.duration(context, Motion.normal),
                  switchInCurve: Motion.standard,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale:
                          Tween<double>(begin: 0.86, end: 1).animate(animation),
                      child: child,
                    ),
                  ),
                  child: loading
                      ? Padding(
                          key: const ValueKey('mini-player-loading'),
                          padding: EdgeInsets.all(size * 0.28),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: foreground,
                          ),
                        )
                      : Icon(
                          hasError
                              ? CupertinoIcons.arrow_clockwise
                              : playing
                                  ? CupertinoIcons.pause_fill
                                  : CupertinoIcons.play_fill,
                          key: ValueKey(hasError
                              ? 'mini-player-retry'
                              : playing
                                  ? 'mini-player-pause'
                                  : 'mini-player-play'),
                          size: size * 0.82,
                          color: foreground,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackTimeline extends StatefulWidget {
  const _PlaybackTimeline({super.key, required this.showTimes});

  final bool showTimes;

  @override
  State<_PlaybackTimeline> createState() => _PlaybackTimelineState();
}

class _PlaybackTimelineState extends State<_PlaybackTimeline> {
  Duration? _previewPosition;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final duration =
        context.select<PlayerController, Duration?>((p) => p.duration) ??
            Duration.zero;
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final position = _previewPosition ?? snapshot.data ?? player.position;
        final time = PlaybackTime(
            position: position, duration: duration, padMinutes: false);
        final bar = GProgressBar(
          position: snapshot.data ?? player.position,
          duration: duration,
          bufferedPosition: player.bufferedPosition,
          onSeek: player.seek,
          onPreviewChanged: (value) => setState(() => _previewPosition = value),
          height: widget.showTimes ? 4 : 3,
          showThumb: false,
          activeColor: scheme.onSurface.withValues(alpha: 0.88),
        );

        if (!widget.showTimes) return bar;
        final timeStyle = TextStyle(
          fontSize: 10.5,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: scheme.onSurfaceVariant,
        );
        return Row(
          children: [
            Text(time.elapsed, style: timeStyle, maxLines: 1),
            const SizedBox(width: 10),
            Expanded(child: bar),
            const SizedBox(width: 10),
            Text(
              time.remaining,
              maxLines: 1,
              textAlign: TextAlign.end,
              style: timeStyle,
            ),
          ],
        );
      },
    );
  }
}

class _VolumeBar extends StatefulWidget {
  const _VolumeBar({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_VolumeBar> createState() => _VolumeBarState();
}

class _VolumeBarState extends State<_VolumeBar> {
  double? _dragFraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayedValue = _dragFraction ?? widget.value;
    return SizedBox(
      width: 76,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void update(double dx, {bool preview = false}) {
            final value =
                (dx / constraints.maxWidth).clamp(0.0, 1.0).toDouble();
            if (preview) setState(() => _dragFraction = value);
            widget.onChanged(value);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => update(details.localPosition.dx),
            onHorizontalDragStart: (_) =>
                setState(() => _dragFraction = widget.value),
            onHorizontalDragUpdate: (details) =>
                update(details.localPosition.dx, preview: true),
            onHorizontalDragEnd: (_) => setState(() => _dragFraction = null),
            onHorizontalDragCancel: () => setState(() => _dragFraction = null),
            child: SizedBox(
              height: 44,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      Container(
                        height: 4,
                        color: scheme.onSurface.withValues(alpha: 0.18),
                      ),
                      FractionallySizedBox(
                        widthFactor: displayedValue.clamp(0.0, 1.0),
                        child: Container(
                          height: 4,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
