import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/models/song.dart';
import '../../core/player/lrc_parser.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/sleep_timer.dart';
import '../../core/settings/settings_controller.dart';
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

    final content = Scaffold(
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
            child: wide
                ? Column(
                    children: [
                      const _TopBar(),
                      Expanded(
                        child: Row(
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
                        ),
                      ),
                    ],
                  )
                : _MobilePlayer(song: current),
          ),
        ],
      ),
    );
    if (wide) return content;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        // The player is edge-to-edge on phones; the black ambient surface
        // continues beneath the gesture indicator.
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: content,
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
              ? const Color(0x70191718)
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
                    ? Colors.black.withValues(alpha: 0.18)
                    : scheme.primary.withValues(alpha: dark ? 0.20 : 0.10),
                immersive ? const Color(0x1A000000) : Colors.transparent,
                if (immersive) Colors.black.withValues(alpha: 0.58),
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
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Platform.isMacOS ? 42 : 58,
      child: Row(
        children: [
          const Spacer(),
          GIconButton(
            icon: Icons.close_rounded,
            tooltip: '关闭播放器',
            size: 20,
            padding: 2,
            filled: true,
            backgroundColor: glassFill(context, alpha: 0.10),
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// 手机端播放器：上方页面横向切换，进度与播放控制始终固定。
class _MobilePlayer extends StatefulWidget {
  const _MobilePlayer({required this.song});

  final Song song;

  @override
  State<_MobilePlayer> createState() => _MobilePlayerState();
}

class _MobilePlayerState extends State<_MobilePlayer> {
  late final PageController _pageController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(covariant _MobilePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _page = 0;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showPage(int page) {
    if (_page == page) return;
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        return Column(
          children: [
            _MobilePlayerTopBar(
              song: widget.song,
              showingLyrics: _page == 1,
              compact: compact,
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  _MobileCoverStage(
                    key: ValueKey('mobile-cover-${widget.song.id}'),
                    song: widget.song,
                    compact: compact,
                    onOpenLyrics: () => _showPage(1),
                  ),
                  _LyricView(
                    key: ValueKey('mobile-lyrics-${widget.song.id}'),
                    lrc: player.lyric,
                    immersive: true,
                    compact: compact,
                    onBackgroundTap: () => _showPage(0),
                  ),
                ],
              ),
            ),
            _MobileControls(
              song: widget.song,
              error: player.error,
              showingLyrics: _page == 1,
              compact: compact,
              onTogglePage: () => _showPage(_page == 0 ? 1 : 0),
            ),
          ],
        );
      },
    );
  }
}

class _MobilePlayerTopBar extends StatelessWidget {
  const _MobilePlayerTopBar({
    required this.song,
    required this.showingLyrics,
    required this.compact,
  });

  final Song song;
  final bool showingLyrics;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: compact ? 48 : 68,
      child: Transform.translate(
        offset: Offset(0, compact ? -4 : -17),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 10,
              child: _ImmersiveIconButton(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: '收起播放器',
                size: compact ? 29 : 32,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            AnimatedSwitcher(
              duration: Motion.normal,
              child: showingLyrics
                  ? SizedBox(
                      key: const ValueKey('lyric-title'),
                      width: MediaQuery.sizeOf(context).width - 150,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 15 : 17,
                              fontWeight: TypeScale.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${song.artistNames}  关注',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: compact ? 11 : 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Text(
                      '心动',
                      key: const ValueKey('cover-title'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 16 : 18,
                        fontWeight: TypeScale.semibold,
                      ),
                    ),
            ),
            Positioned(
              right: 10,
              child: _ImmersiveIconButton(
                icon: Icons.replay_rounded,
                tooltip: '重新播放',
                size: compact ? 25 : 28,
                onTap: () =>
                    context.read<PlayerController>().seek(Duration.zero),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileCoverStage extends StatelessWidget {
  const _MobileCoverStage({
    super.key,
    required this.song,
    required this.compact,
    required this.onOpenLyrics,
  });

  final Song song;
  final bool compact;
  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDiscWidth = MediaQuery.sizeOf(context).width - 38;
        final composerHeight = compact ? 25.0 : 44.0;
        final topInset = compact ? 0.0 : 18.0;
        final discSize = math
            .min(
              maxDiscWidth,
              (constraints.maxHeight - composerHeight - topInset)
                  .clamp(150.0, 350.0),
            )
            .toDouble();
        return Semantics(
          container: true,
          button: true,
          label: '查看歌词',
          onTap: onOpenLyrics,
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenLyrics,
              child: Column(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  if (!compact) SizedBox(height: topInset),
                  SizedBox(
                    width: discSize,
                    height: discSize,
                    child: _VinylStage(song: song),
                  ),
                  SizedBox(height: compact ? 2 : 7),
                  Text(
                    '作曲：${song.artistNames}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: compact ? 12 : 15,
                      fontWeight: TypeScale.medium,
                    ),
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

class _VinylStage extends StatelessWidget {
  const _VinylStage({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: 0,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Positioned(
                  left: constraints.maxWidth * 0.04,
                  right: constraints.maxWidth * 0.04,
                  top: constraints.maxHeight * 0.15,
                  bottom: 0,
                  child: _SpinningVinyl(song: song),
                ),
              ],
            ),
          ),
        ),
        const Positioned.fill(child: CustomPaint(painter: _TonearmPainter())),
      ],
    );
  }
}

class _SpinningVinyl extends StatefulWidget {
  const _SpinningVinyl({required this.song});

  final Song song;

  @override
  State<_SpinningVinyl> createState() => _SpinningVinylState();
}

class _SpinningVinylState extends State<_SpinningVinyl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _syncRotation(context.read<PlayerController>().playing);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRotation(context.read<PlayerController>().playing);
  }

  void _syncRotation(bool playing) {
    if (playing && !_rotation.isAnimating) {
      _rotation.repeat();
    } else if (!playing && _rotation.isAnimating) {
      _rotation.stop();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncRotation(playing);
    });
    return RotationTransition(
      turns: _rotation,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _VinylPainter()),
          ),
          FractionallySizedBox(
            widthFactor: 0.59,
            heightFactor: 0.59,
            child: LayoutBuilder(
              builder: (context, constraints) => ClipOval(
                child: AsyncCover(
                  url: widget.song.album.picUrl,
                  size: constraints.maxWidth,
                  radius: constraints.maxWidth / 2,
                ),
              ),
            ),
          ),
          FractionallySizedBox(
            widthFactor: 0.035,
            heightFactor: 0.035,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF292929), Color(0xFF080808), Color(0xFF171717)],
          stops: [0, 0.72, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.55, radius * 0.003)
      ..color = Colors.white.withValues(alpha: 0.055);
    for (var index = 0; index < 19; index++) {
      final fraction = 0.62 + index * 0.019;
      canvas.drawCircle(center, radius * fraction, groovePaint);
    }
    canvas.drawCircle(
      center,
      radius * 0.985,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = Colors.white.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TonearmPainter extends CustomPainter {
  const _TonearmPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width * 0.58, size.height * 0.08);
    final path = Path()
      ..moveTo(pivot.dx, pivot.dy + size.height * 0.025)
      ..cubicTo(
        size.width * 0.59,
        size.height * 0.24,
        size.width * 0.62,
        size.height * 0.37,
        size.width * 0.72,
        size.height * 0.45,
      )
      ..lineTo(size.width * 0.79, size.height * 0.51);
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.035
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.22);
    final arm = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.025
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF4F3F1);
    canvas.drawPath(path, shadow);
    canvas.drawPath(path, arm);
    canvas.drawCircle(
      pivot,
      size.width * 0.059,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      pivot,
      size.width * 0.034,
      Paint()..color = const Color(0xFFF1F0EE),
    );
    canvas.save();
    canvas.translate(size.width * 0.79, size.height * 0.51);
    canvas.rotate(-0.78);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: size.width * 0.12,
          height: size.width * 0.065,
        ),
        Radius.circular(size.width * 0.012),
      ),
      Paint()..color = const Color(0xFFF4F3F1),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MobileControls extends StatelessWidget {
  const _MobileControls({
    required this.song,
    required this.error,
    required this.showingLyrics,
    required this.compact,
    required this.onTogglePage,
  });

  final Song song;
  final String? error;
  final bool showingLyrics;
  final bool compact;
  final VoidCallback onTogglePage;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final requestedQuality =
        context.select<SettingsController, String>((s) => s.quality);
    final quality = player.effectiveQuality ?? requestedQuality;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, compact ? 1 : 7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: compact ? 42 : 59,
            child: error != null
                ? _PlaybackErrorBanner(
                    message: error!,
                    actionLabel: _playbackActionLabel(player),
                    onAction: () => _handlePlaybackError(context, player),
                  )
                : showingLyrics
                    ? _LyricUtilityRow(compact: compact)
                    : _MobileSongSummary(song: song, compact: compact),
          ),
          _MobileProgressRow(
            qualityLabel: _mobileQualityLabel(quality),
            compact: compact,
            onQualityTap: () => _showPlaybackQualitySheet(context),
          ),
          SizedBox(height: compact ? 1 : 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ImmersiveIconButton(
                icon: player.loopMode.name == 'one'
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                tooltip: '循环模式',
                selected: player.loopMode.name != 'off',
                size: compact ? 22 : 25,
                buttonSize: compact ? 40 : 48,
                onTap: player.cycleLoopMode,
              ),
              _ImmersiveIconButton(
                icon: Icons.skip_previous_rounded,
                tooltip: '上一首',
                size: compact ? 32 : 38,
                buttonSize: compact ? 44 : 54,
                onTap: player.previous,
              ),
              _PlayPauseButton(
                playing: player.playing,
                loading: player.loading,
                onTap: player.togglePlay,
                large: true,
                immersive: true,
                compact: compact,
              ),
              _ImmersiveIconButton(
                icon: Icons.skip_next_rounded,
                tooltip: '下一首',
                size: compact ? 32 : 38,
                buttonSize: compact ? 44 : 54,
                onTap: player.next,
              ),
              _ImmersiveIconButton(
                icon: Icons.queue_music_rounded,
                tooltip: '播放队列',
                size: compact ? 24 : 27,
                buttonSize: compact ? 40 : 48,
                onTap: () => showQueueSheet(context),
              ),
            ],
          ),
          SizedBox(height: compact ? 0 : 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ImmersiveIconButton(
                icon: showingLyrics
                    ? Icons.album_outlined
                    : Icons.phone_iphone_rounded,
                tooltip: showingLyrics ? '返回封面' : '歌词',
                size: compact ? 20 : 22,
                buttonSize: compact ? 40 : 46,
                onTap: onTogglePage,
              ),
              _ImmersiveIconButton(
                icon: Icons.lightbulb_outline_rounded,
                tooltip: '睡眠定时',
                size: compact ? 21 : 24,
                buttonSize: compact ? 40 : 46,
                onTap: () => _showSleepTimer(context),
              ),
              _ImmersiveIconButton(
                icon: Icons.info_outline_rounded,
                tooltip: '歌曲百科',
                size: compact ? 21 : 24,
                buttonSize: compact ? 40 : 46,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('暂无歌曲百科')),
                ),
              ),
              _ImmersiveIconButton(
                icon: Icons.more_horiz_rounded,
                tooltip: '更多',
                size: compact ? 23 : 26,
                buttonSize: compact ? 40 : 46,
                onTap: () => showQueueSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileSongSummary extends StatelessWidget {
  const _MobileSongSummary({required this.song, required this.compact});

  final Song song;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
                  color: Colors.white,
                  fontSize: compact ? 16 : 19,
                  fontWeight: TypeScale.bold,
                ),
              ),
              SizedBox(height: compact ? 1 : 4),
              Text(
                '${song.artistNames}  关注',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: compact ? 11 : 13,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: compact ? 40 : 46,
          height: compact ? 40 : 46,
          child: _FavoriteBtn(song: song, immersive: true),
        ),
      ],
    );
  }
}

class _LyricUtilityRow extends StatelessWidget {
  const _LyricUtilityRow({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: 0.62);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(Icons.more_horiz_rounded, size: compact ? 22 : 25, color: color),
        Row(
          children: [
            Icon(Icons.favorite_border_rounded,
                size: compact ? 25 : 29, color: color),
            SizedBox(width: compact ? 24 : 34),
            Icon(Icons.mic_none_rounded, size: compact ? 24 : 27, color: color),
          ],
        ),
      ],
    );
  }
}

class _MobileProgressRow extends StatelessWidget {
  const _MobileProgressRow({
    required this.qualityLabel,
    required this.compact,
    required this.onQualityTap,
  });

  final String qualityLabel;
  final bool compact;
  final VoidCallback onQualityTap;

  @override
  Widget build(BuildContext context) {
    final duration =
        context.select<PlayerController, Duration?>((p) => p.duration);
    final player = context.read<PlayerController>();
    final timeStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.45),
      fontSize: compact ? 9 : 11,
      fontWeight: TypeScale.semibold,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? player.position;
        final total = duration ?? Duration.zero;
        return Column(
          children: [
            Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                      primary: Colors.white,
                      onPrimary: Colors.white,
                      surfaceContainerHighest:
                          Colors.white.withValues(alpha: 0.36),
                    ),
              ),
              child: GProgressBar(
                position: position,
                duration: total,
                onSeek: player.seek,
                height: compact ? 2 : 2.5,
              ),
            ),
            Transform.translate(
              offset: Offset(0, compact ? -4 : -2),
              child: Row(
                children: [
                  Text(_ProgressRow._fmt(position), style: timeStyle),
                  Expanded(
                    child: Tooltip(
                      message: '切换音质',
                      child: Semantics(
                        button: true,
                        label: '切换音质，当前$qualityLabel',
                        child: GPressScale(
                          onTap: onQualityTap,
                          child: SizedBox(
                            height: compact ? 20 : 24,
                            child: Center(
                              child: Text(
                                qualityLabel,
                                textAlign: TextAlign.center,
                                style: timeStyle.copyWith(
                                  color: Colors.white.withValues(alpha: 0.68),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(_ProgressRow._fmt(total), style: timeStyle),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

String _mobileQualityLabel(String quality) => switch (quality) {
      'standard' => AppConfig.qualityLabels['standard']!,
      'lossless' => AppConfig.qualityLabels['lossless']!,
      'hires' => AppConfig.qualityLabels['hires']!,
      _ => '高清臻音',
    };

Future<void> _showPlaybackQualitySheet(BuildContext context) async {
  final settings = context.read<SettingsController>();
  final player = context.read<PlayerController>();
  final selected = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.44),
    builder: (sheetContext) => _PlaybackQualitySheet(
      selected: player.effectiveQuality ?? settings.quality,
    ),
  );
  if (selected == null || selected == settings.quality || !context.mounted) {
    return;
  }

  final position = player.position;
  final wasPlaying = player.playing;
  await settings.setQuality(selected);
  if (!context.mounted || player.current == null) return;

  await player.retry();
  if (player.error == null) {
    await player.seek(position);
    if (!wasPlaying) await player.pause();
  }
  if (!context.mounted) return;
  final effectiveQuality = player.effectiveQuality ?? selected;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          effectiveQuality == selected
              ? '已切换为 ${_mobileQualityLabel(selected)}'
              : '${_mobileQualityLabel(selected)} 暂不可用，'
                  '已自动使用 ${_mobileQualityLabel(effectiveQuality)}',
        ),
        duration: const Duration(milliseconds: 1400),
      ),
    );
}

class _PlaybackQualitySheet extends StatelessWidget {
  const _PlaybackQualitySheet({required this.selected});

  final String selected;

  static const _options = [
    (id: 'auto', label: '智能选择', detail: '根据网络状况自动选择'),
    (id: 'standard', label: '标准音质', detail: '128Kbps'),
    (id: 'exhigh', label: '高清臻音', detail: '320Kbps'),
    (id: 'lossless', label: '无损 SQ', detail: 'FLAC 48kHz/16bit'),
    (id: 'hires', label: 'Hi-Res', detail: '最高 192kHz/24bit'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xF21A1918),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 9, bottom: 18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '当前歌曲音质',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: TypeScale.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (final option in _options)
              GPressScale(
                onTap: () => Navigator.of(context).pop(option.id),
                scale: 0.99,
                child: SizedBox(
                  height: 62,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          child: Icon(
                            option.id == 'hires'
                                ? Icons.graphic_eq_rounded
                                : option.id == 'lossless'
                                    ? Icons.album_outlined
                                    : Icons.music_note_rounded,
                            size: 20,
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: TypeScale.semibold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                option.detail,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.46),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (option.id == selected)
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
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
    this.buttonSize = 46,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final double buttonSize;
  final bool selected;

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
            width: buttonSize,
            height: buttonSize,
            child: Icon(
              icon,
              size: size,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white.withValues(alpha: 0.78),
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
    useRootNavigator: true,
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
    this.compact = false,
  });

  final bool playing;
  final bool loading;
  final VoidCallback onTap;
  final bool large;
  final bool immersive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = compact
        ? 52.0
        : large
            ? 64.0
            : 56.0;
    return GPressScale(
      onTap: loading ? null : onTap,
      disabled: loading,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: immersive
              ? Colors.transparent
              : dark
                  ? Colors.white
                  : scheme.primary,
          boxShadow: immersive
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: loading
            ? Padding(
                padding: EdgeInsets.all(immersive ? 18 : 20),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: immersive
                      ? Colors.white
                      : dark
                          ? Colors.black
                          : Colors.white,
                ),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: size * (immersive ? 0.78 : 0.52),
                color: immersive
                    ? Colors.white.withValues(alpha: 0.82)
                    : dark
                        ? Colors.black
                        : Colors.white,
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
          (e) {
            final id = e['songId'] ?? e['id'];
            final source = e['source'] ?? 'netease';
            return id?.toString() == widget.song.id &&
                source.toString() == widget.song.source;
          },
        );
      });
      final player = context.read<PlayerController>();
      if (player.current?.id == widget.song.id &&
          player.current?.source == widget.song.source) {
        player.setLiked(_fav);
      }
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
        final player = context.read<PlayerController>();
        if (player.current?.id == widget.song.id &&
            player.current?.source == widget.song.source) {
          player.setLiked(_fav);
        }
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
                    ? scheme.primary
                    : widget.immersive
                        ? Colors.white.withValues(alpha: 0.92)
                        : scheme.onSurface,
              ),
      ),
    );
  }
}

/// 进度条 + 时间（高频刷新，独立订阅 position/duration）
class _ProgressRow extends StatelessWidget {
  const _ProgressRow();

  @override
  Widget build(BuildContext context) {
    final duration =
        context.select<PlayerController, Duration?>((p) => p.duration);
    final player = context.read<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final timeStyle = TextStyle(
      fontSize: 11,
      color: scheme.onSurfaceVariant,
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
                  data: Theme.of(context),
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
    this.compact = false,
    this.onBackgroundTap,
  });

  final String lrc;
  final bool immersive;
  final bool compact;
  final VoidCallback? onBackgroundTap;

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
      final empty = Center(
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
      if (widget.onBackgroundTap == null) return empty;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onBackgroundTap,
        child: empty,
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
        final lineHeight = widget.immersive
            ? widget.compact
                ? 50.0
                : 44.0
            : 58.0;
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
                                    ? widget.compact
                                        ? 18
                                        : 19
                                    : widget.compact
                                        ? 14
                                        : 16
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
            if (widget.onBackgroundTap != null) {
              list = GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onBackgroundTap,
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
      final lineHeight = widget.immersive
          ? widget.compact
              ? 50.0
              : 44.0
          : 58.0;
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
