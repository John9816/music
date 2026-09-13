import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/config/audio_quality_policy.dart';
import '../../core/models/song.dart';
import '../../core/player/lrc_parser.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/sleep_timer.dart';
import '../../core/services/cast_service.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../profile/login_view.dart';
import '../profile/profile_view.dart';
import '../search/artist_names_link.dart';
import '../../widgets/song_action_menu.dart';
import '../../core/theme/app_animations.dart';
import 'queue_view.dart';

enum _PlayerPane { lyrics, queue }

/// Full-screen player route with the same bottom-sheet-like motion used by
/// the mobile player. Popping this route automatically runs the reverse
/// transition, so the player returns along the path it entered.
Route<void> buildPlayerRoute({required bool reducedMotion}) {
  return PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: AppAnimations.adaptive(
      AppAnimations.slow,
      reducedMotion: reducedMotion,
    ),
    reverseTransitionDuration: AppAnimations.adaptive(
      AppAnimations.slow,
      reducedMotion: reducedMotion,
    ),
    pageBuilder: (context, animation, secondaryAnimation) => const PlayerView(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppAnimations.pageTransition,
        reverseCurve: AppAnimations.pageTransition,
      );
      final slide = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curved);
      final opacity = Tween<double>(begin: 0.92, end: 1).animate(curved);

      if (reducedMotion) return child;
      return FadeTransition(
        opacity: opacity,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

/// 全屏播放页：左侧封面与播放控制，右侧歌词/队列原位切换。
class PlayerView extends StatefulWidget {
  const PlayerView({super.key});

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView>
    with SingleTickerProviderStateMixin {
  _PlayerPane _pane = _PlayerPane.lyrics;
  late final AnimationController _dismissOffset;
  bool _draggingToDismiss = false;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _dismissOffset = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _dismissOffset.dispose();
    super.dispose();
  }

  void _startDismissDrag(DragStartDetails details) {
    if (_dismissing || !Navigator.of(context).canPop()) return;
    _dismissOffset.stop();
    _draggingToDismiss = true;
  }

  void _updateDismissDrag(DragUpdateDetails details) {
    if (!_draggingToDismiss) return;
    final height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return;
    _dismissOffset.value =
        (_dismissOffset.value + (details.primaryDelta ?? 0) / height)
            .clamp(0.0, 1.0)
            .toDouble();
  }

  void _endDismissDrag(DragEndDetails details) {
    if (!_draggingToDismiss) return;
    _draggingToDismiss = false;
    final distance = _dismissOffset.value * MediaQuery.sizeOf(context).height;
    final shouldDismiss = _dismissOffset.value >= 0.18 ||
        (distance >= 24 && (details.primaryVelocity ?? 0) >= 850);
    if (shouldDismiss) {
      _dismissing = true;
      Navigator.of(context).maybePop().then((popped) {
        if (!mounted || popped) return;
        _dismissing = false;
        _returnFromDismissDrag();
      });
    } else {
      _returnFromDismissDrag();
    }
  }

  void _returnFromDismissDrag() {
    _draggingToDismiss = false;
    _dismissOffset.animateTo(
      0,
      duration: PlatformMotion.duration(context, Motion.normal),
      curve: Motion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final current =
        context.select<PlayerController, Song?>((player) => player.current);
    if (current == null) {
      return const Scaffold(body: Center(child: Text('暂无播放')));
    }
    return LayoutBuilder(
      builder: (context, constraints) => _buildPlayerSurface(
        context,
        current,
        wide: constraints.maxWidth >= GBreakpoints.sidebar &&
            constraints.maxHeight >= 600,
      ),
    );
  }

  Widget _buildPlayerSurface(
    BuildContext context,
    Song current, {
    required bool wide,
  }) {
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
            top: Theme.of(context).platform != TargetPlatform.macOS,
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
                                  duration: PlatformMotion.duration(
                                    context,
                                    Motion.normal,
                                  ),
                                  child: _pane == _PlayerPane.lyrics
                                      ? const _SelectedLyricView(
                                          key: ValueKey('lyrics'),
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
                : _MobilePlayer(
                    song: current,
                    onDismissDragStart: _startDismissDrag,
                    onDismissDragUpdate: _updateDismissDrag,
                    onDismissDragEnd: _endDismissDrag,
                    onDismissDragCancel: _returnFromDismissDrag,
                  ),
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
      child: AnimatedBuilder(
        animation: _dismissOffset,
        child: content,
        builder: (context, child) => Transform.translate(
          key: const ValueKey('player-dismiss-surface'),
          offset: Offset(
            0,
            _dismissOffset.value * MediaQuery.sizeOf(context).height,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(
                (_dismissOffset.value * 160).clamp(0.0, 24.0).toDouble(),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SelectedLyricView extends StatelessWidget {
  const _SelectedLyricView({super.key});

  @override
  Widget build(BuildContext context) {
    final lyric =
        context.select<PlayerController, String>((player) => player.lyric);
    return _LyricView(lrc: lyric);
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
    return RepaintBoundary(
      child: Stack(
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
                child: AsyncCover(
                  url: coverUrl,
                  size: double.infinity,
                  radius: 0,
                  memCacheWidth: 256,
                  memCacheHeight: 256,
                ),
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
      ),
    );
  }
}

/// 顶部栏仅保留关闭按钮，让内容和原生红绿灯共享顶边。
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Theme.of(context).platform == TargetPlatform.macOS ? 44 : 58,
      child: Row(
        children: [
          const Spacer(),
          GIconButton(
            icon: Icons.close_rounded,
            tooltip: '关闭播放器',
            size: 20,
            padding: 12,
            tint: Colors.white,
            backgroundColor: glassFill(context, alpha: 0.10),
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// 手机端播放器：竖屏上下排布，横屏并排展示封面/歌词与播放控制。
class _MobilePlayer extends StatefulWidget {
  const _MobilePlayer({
    required this.song,
    required this.onDismissDragStart,
    required this.onDismissDragUpdate,
    required this.onDismissDragEnd,
    required this.onDismissDragCancel,
  });

  final Song song;
  final GestureDragStartCallback onDismissDragStart;
  final GestureDragUpdateCallback onDismissDragUpdate;
  final GestureDragEndCallback onDismissDragEnd;
  final GestureDragCancelCallback onDismissDragCancel;

  @override
  State<_MobilePlayer> createState() => _MobilePlayerState();
}

class _MobilePlayerState extends State<_MobilePlayer> {
  late final PageController _pageController;
  late final CastService _castService;
  final _pagesKey = GlobalKey();
  final _controlsKey = GlobalKey();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _castService = CastService();
  }

  @override
  void didUpdateWidget(covariant _MobilePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.song.source != widget.song.source) {
      _page = 0;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _castService.dispose();
    super.dispose();
  }

  void _showPage(int page) {
    if (_page == page) return;
    final duration = PlatformMotion.duration(context, Motion.slow);
    if (duration == Duration.zero) {
      _pageController.jumpToPage(page);
      return;
    }
    _pageController.animateToPage(
      page,
      duration: duration,
      curve: Motion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.select<PlayerController, (String, String?)>(
      (player) => (player.lyric, player.error),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        final landscape = constraints.maxWidth >= 600 &&
            constraints.maxWidth > constraints.maxHeight;
        final pages = PageView(
          key: _pagesKey,
          controller: _pageController,
          physics: const BouncingScrollPhysics(),
          onPageChanged: (page) => setState(() => _page = page),
          children: [
            _MobileCoverStage(
              key: ValueKey(
                'mobile-cover-${widget.song.source}:${widget.song.id}',
              ),
              song: widget.song,
              compact: compact,
              onOpenLyrics: () => _showPage(1),
            ),
            _LyricView(
              key: ValueKey(
                'mobile-lyrics-${widget.song.source}:${widget.song.id}',
              ),
              lrc: state.$1,
              immersive: true,
              compact: compact,
              onBackgroundTap: () => _showPage(0),
            ),
          ],
        );
        final controls = SingleChildScrollView(
          key: _controlsKey,
          primary: false,
          child: _MobileControls(
            song: widget.song,
            error: state.$2,
            showingLyrics: _page == 1,
            compact: compact,
            onOpenDevicePicker: _openDevicePicker,
          ),
        );
        return Column(
          children: [
            // A dedicated top region keeps dismissal out of the lyrics and
            // playback timeline gesture arenas.
            GestureDetector(
              key: const ValueKey('mobile-player-dismiss-region'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: widget.onDismissDragStart,
              onVerticalDragUpdate: widget.onDismissDragUpdate,
              onVerticalDragEnd: widget.onDismissDragEnd,
              onVerticalDragCancel: widget.onDismissDragCancel,
              child: _MobilePlayerTopBar(
                song: widget.song,
                showingLyrics: _page == 1,
                compact: compact,
              ),
            ),
            Expanded(
              child: landscape
                  ? Row(
                      children: [
                        Expanded(flex: 4, child: pages),
                        Expanded(flex: 6, child: controls),
                      ],
                    )
                  : LayoutBuilder(
                      builder: (context, bodyConstraints) => Column(
                        children: [
                          Expanded(child: pages),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: math.max(
                                bodyConstraints.maxHeight - 120,
                                bodyConstraints.maxHeight / 2,
                              ),
                            ),
                            child: controls,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openDevicePicker() async {
    await _castService.showDevicePicker();
    if (!mounted || _castService.message.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_castService.message)));
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
    final textScaler = MediaQuery.textScalerOf(context);
    final lineHeight = DefaultTextStyle.of(context).style.height ?? 1.25;
    final titleHeight = ((textScaler.scale(compact ? 15 : 17) +
                    textScaler.scale(compact ? 11 : 13)) *
                lineHeight +
            3)
        .ceilToDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: math.max(compact ? 54 : 64, titleHeight),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            _ImmersiveIconButton(
              icon: Icons.keyboard_arrow_down_rounded,
              tooltip: '收起播放器',
              size: compact ? 29 : 32,
              buttonSize: compact ? 44 : 46,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: PlatformMotion.duration(context, Motion.normal),
                child: showingLyrics
                    ? Column(
                        key: const ValueKey('lyric-title'),
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            song.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 15 : 17,
                              fontWeight: TypeScale.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Semantics(
                            container: true,
                            button: true,
                            excludeSemantics: true,
                            label: '查看${song.artistNames}的歌手信息',
                            onTap: () => openArtistInfo(
                              context,
                              artists: song.artists,
                              source: song.source,
                            ),
                            child: ArtistNamesLink(
                              artists: song.artists,
                              source: song.source,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.62),
                                fontSize: compact ? 11 : 13,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        '正在播放',
                        key: const ValueKey('cover-title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.80),
                          fontSize: compact ? 13 : 15,
                          fontWeight: TypeScale.semibold,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 46),
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
        final maxDiscWidth = math.max(0.0, constraints.maxWidth - 38);
        final lyricHeight = (compact ? 54.0 : 78.0) *
            MediaQuery.textScalerOf(context).scale(14) /
            14;
        final topInset = compact ? 0.0 : 10.0;
        final discSize = math
            .min(
              maxDiscWidth,
              (constraints.maxHeight - lyricHeight - topInset - 12)
                  .clamp(140.0, 350.0),
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
              child: SingleChildScrollView(
                primary: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                      const SizedBox(height: 8),
                      SizedBox(
                        height: lyricHeight,
                        child: _VinylRollingLyrics(
                          key: const ValueKey('vinyl-rolling-lyrics'),
                          compact: compact,
                        ),
                      ),
                    ],
                  ),
                ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final stageSize = constraints.biggest.shortestSide;
        final vinylSize = stageSize * 0.88;
        return Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: const Alignment(0, 0.86),
              child: SizedBox.square(
                dimension: vinylSize,
                child: _SpinningVinyl(song: song),
              ),
            ),
            const Positioned.fill(child: _AnimatedTonearm()),
          ],
        );
      },
    );
  }
}

class _AnimatedTonearm extends StatefulWidget {
  const _AnimatedTonearm();

  @override
  State<_AnimatedTonearm> createState() => _AnimatedTonearmState();
}

class _AnimatedTonearmState extends State<_AnimatedTonearm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool? _lastPlaying;
  bool? _lastReduceMotion;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
      value: context.read<PlayerController>().playing ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_lastPlaying != playing || _lastReduceMotion != reduceMotion) {
      _lastPlaying = playing;
      _lastReduceMotion = reduceMotion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = playing ? 1.0 : 0.0;
        if (reduceMotion) {
          _controller.value = target;
        } else if (_controller.value != target) {
          _controller.animateTo(
            target,
            duration: const Duration(milliseconds: 680),
            curve: Curves.easeInOutCubic,
          );
        }
      });
    }
    return RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('vinyl-tonearm'),
        painter: _TonearmPainter(progress: _controller),
      ),
    );
  }
}

class _VinylRollingLyrics extends StatelessWidget {
  const _VinylRollingLyrics({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lrc = context.select<PlayerController, String>((p) => p.lyric);
    final player = context.read<PlayerController>();
    final lines = parseLrc(lrc);
    if (lines.isEmpty) {
      final loading = context.select<PlayerController, bool>((p) => p.loading);
      return Center(
        child: Text(
          loading && lrc.isEmpty ? '歌词加载中' : '暂无歌词',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.48),
            fontSize: compact ? 12 : 14,
          ),
        ),
      );
    }
    int currentLine(Duration position) {
      var low = 0;
      var high = lines.length - 1;
      var current = 0;
      while (low <= high) {
        final middle = low + ((high - low) >> 1);
        if (lines[middle].time <= position) {
          current = middle;
          low = middle + 1;
        } else {
          high = middle - 1;
        }
      }
      return current;
    }

    return StreamBuilder<int>(
      stream: player.positionStream.map(currentLine).distinct(),
      initialData: currentLine(player.position),
      builder: (context, snapshot) {
        final current = snapshot.data ?? 0;
        final previous = current > 0 ? lines[current - 1].text : '';
        final active = lines[current].text;
        final next = current + 1 < lines.length ? lines[current + 1].text : '';
        return ClipRect(
          child: AnimatedSwitcher(
            duration: PlatformMotion.duration(context, Motion.normal),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.28),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey(current),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!compact)
                  _VinylLyricLine(
                      text: previous, active: false, compact: false),
                _VinylLyricLine(text: active, active: true, compact: compact),
                _VinylLyricLine(text: next, active: false, compact: compact),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VinylLyricLine extends StatelessWidget {
  const _VinylLyricLine({
    required this.text,
    required this.active,
    required this.compact,
  });

  final String text;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height:
          (compact ? 26 : 25) * MediaQuery.textScalerOf(context).scale(14) / 14,
      child: Center(
        child: Text(
          text.isEmpty ? ' ' : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: active ? 0.94 : 0.36),
            fontSize: active ? (compact ? 14 : 16) : (compact ? 11 : 12),
            fontWeight: active ? TypeScale.semibold : TypeScale.medium,
          ),
        ),
      ),
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
  bool? _lastAnimating;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
  }

  void _syncRotation(bool animate) {
    if (animate && !_rotation.isAnimating) {
      _rotation.repeat();
    } else if (!animate && _rotation.isAnimating) {
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
    final animate = playing &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_lastAnimating != animate) {
      _lastAnimating = animate;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncRotation(animate);
      });
    }
    return RotationTransition(
      key: const ValueKey('vinyl-disc'),
      turns: _rotation,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final vinylSize = constraints.biggest.shortestSide;
            final labelSize = vinylSize * 0.56;
            return Stack(
              alignment: Alignment.center,
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: _VinylPainter()),
                ),
                SizedBox.square(
                  dimension: labelSize,
                  child: ClipOval(
                    key: const ValueKey('vinyl-cover'),
                    clipBehavior: Clip.antiAlias,
                    child: AsyncCover(
                      url: widget.song.album.picUrl,
                      size: labelSize,
                      radius: 0,
                    ),
                  ),
                ),
                SizedBox.square(
                  dimension: vinylSize * 0.034,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.76),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.18),
                        width: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
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
  const _TonearmPainter({required this.progress}) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeInOutCubic.transform(progress.value);
    final scale = math.min(size.width, size.height);
    final pivot = Offset(size.width * 0.83, size.height * 0.16);
    final restingTip = Offset(size.width * 0.89, size.height * 0.33);
    final playingTip = Offset(size.width * 0.70, size.height * 0.38);
    final tip = Offset.lerp(restingTip, playingTip, t)!;
    final elbow = Offset.lerp(
      Offset(size.width * 0.84, size.height * 0.24),
      Offset(size.width * 0.76, size.height * 0.27),
      t,
    )!;
    final path = Path()
      ..moveTo(pivot.dx, pivot.dy + scale * 0.025)
      ..cubicTo(
        pivot.dx + scale * 0.015,
        pivot.dy + scale * 0.06,
        elbow.dx + scale * 0.025,
        elbow.dy - scale * 0.025,
        elbow.dx,
        elbow.dy,
      )
      ..lineTo(tip.dx, tip.dy);
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * 0.021
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.30);
    final arm = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * 0.0115
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD8D5CE);
    canvas.drawPath(path, shadow);
    canvas.drawPath(path, arm);
    canvas.drawCircle(
      pivot,
      scale * 0.058,
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      pivot,
      scale * 0.042,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFF3F1EC), Color(0xFFAAA69E)],
        ).createShader(
          Rect.fromCircle(center: pivot, radius: scale * 0.042),
        ),
    );
    canvas.drawCircle(
      pivot,
      scale * 0.014,
      Paint()..color = const Color(0xFF55524D),
    );
    final direction = tip - elbow;
    final angle = math.atan2(direction.dy, direction.dx);
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: scale * 0.070,
          height: scale * 0.038,
        ),
        Radius.circular(scale * 0.008),
      ),
      Paint()..color = const Color(0xFFBBB7AF),
    );
    canvas.drawLine(
      Offset(scale * 0.032, 0),
      Offset(scale * 0.047, scale * 0.015),
      Paint()
        ..strokeWidth = scale * 0.0045
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFE7E4DD),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TonearmPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _MobileControls extends StatelessWidget {
  const _MobileControls({
    required this.song,
    required this.error,
    required this.showingLyrics,
    required this.compact,
    required this.onOpenDevicePicker,
  });

  final Song song;
  final String? error;
  final bool showingLyrics;
  final bool compact;
  final VoidCallback onOpenDevicePicker;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final state = context
        .select<PlayerController, (bool, bool, String, String?, int, bool)>(
      (player) => (
        player.playing,
        player.loading,
        player.loopMode.name,
        player.effectiveQuality,
        player.queueIndex,
        player.shuffle,
      ),
    );
    final requestedQuality = context.select<SettingsController, String>(
      (settings) => settings.qualityForSource(song.source),
    );
    final quality = state.$4 ?? requestedQuality;
    final shuffle = state.$6;
    final textScaler = MediaQuery.textScalerOf(context);
    final lineHeight = DefaultTextStyle.of(context).style.height ?? 1.25;
    final summaryHeight = ((textScaler.scale(compact ? 16 : 19) +
                    textScaler.scale(compact ? 11 : 13)) *
                lineHeight +
            (compact ? 1 : 4))
        .ceilToDouble();
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, compact ? 4 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(compact ? 48 : 58, summaryHeight),
            ),
            child: error != null
                ? _PlaybackErrorBanner(
                    message: error!,
                    actionLabel: _playbackActionLabel(player),
                    onAction: () => _handlePlaybackError(context, player),
                  )
                : showingLyrics
                    ? _LyricUtilityRow(song: song, compact: compact)
                    : _MobileSongSummary(song: song, compact: compact),
          ),
          _MobileProgressRow(
            qualityLabel: _mobileQualityLabel(quality),
            compact: compact,
            onQualityTap: () => _showPlaybackQualitySheet(context),
          ),
          SizedBox(height: compact ? 7 : 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ImmersiveIconButton(
                icon: Icons.skip_previous_rounded,
                tooltip: '上一首',
                size: compact ? 32 : 38,
                buttonSize: compact ? 44 : 54,
                onTap: player.previous,
              ),
              SizedBox(width: compact ? 18 : 26),
              _PlayPauseButton(
                playing: state.$1,
                loading: state.$2,
                onTap: player.togglePlay,
                large: true,
                immersive: true,
                compact: compact,
              ),
              SizedBox(width: compact ? 18 : 26),
              _ImmersiveIconButton(
                icon: Icons.skip_next_rounded,
                tooltip: '下一首',
                size: compact ? 32 : 38,
                buttonSize: compact ? 44 : 54,
                onTap: player.next,
              ),
            ],
          ),
          SizedBox(height: compact ? 2 : 7),
          LayoutBuilder(
            builder: (context, constraints) {
              final tools = <Widget>[
                _ImmersiveIconButton(
                  icon: Icons.shuffle_rounded,
                  tooltip: shuffle ? '随机播放（已开启）' : '随机播放',
                  selected: shuffle,
                  size: compact ? 21 : 23,
                  buttonSize: 44,
                  onTap: player.toggleShuffle,
                ),
                _ImmersiveIconButton(
                  icon: state.$3 == 'one'
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  tooltip: switch (state.$3) {
                    'one' => '单曲循环',
                    'all' => '列表循环',
                    _ => '不循环',
                  },
                  selected: state.$3 != 'off',
                  size: compact ? 21 : 23,
                  buttonSize: 44,
                  onTap: player.cycleLoopMode,
                ),
                _ImmersiveIconButton(
                  icon: Icons.airplay_rounded,
                  tooltip: 'AirPlay 或蓝牙',
                  size: compact ? 20 : 22,
                  buttonSize: 44,
                  onTap: onOpenDevicePicker,
                ),
                _ImmersiveIconButton(
                  icon: Icons.bedtime_outlined,
                  tooltip: '睡眠定时',
                  size: compact ? 20 : 22,
                  buttonSize: 44,
                  onTap: () => _showSleepTimer(context),
                ),
                _ImmersiveIconButton(
                  icon: Icons.info_outline_rounded,
                  tooltip: '歌曲百科',
                  size: compact ? 20 : 22,
                  buttonSize: 44,
                  onTap: () => _showSongInfoSheet(context, song, quality),
                ),
                _ImmersiveIconButton(
                  icon: Icons.queue_music_rounded,
                  tooltip: '播放队列',
                  size: compact ? 21 : 23,
                  buttonSize: 44,
                  onTap: () => showQueueSheet(context),
                ),
                _ImmersiveIconButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: '更多',
                  size: compact ? 22 : 24,
                  buttonSize: 44,
                  onTap: () => showSongActions(
                    context,
                    song: song,
                    queueIndex: state.$5,
                  ),
                ),
              ];
              if (constraints.maxWidth >= tools.length * 44) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: tools,
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [tools[0], tools[1], tools[5], tools[6]],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [tools[2], tools[3], tools[4]],
                  ),
                ],
              );
            },
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
              Semantics(
                container: true,
                button: true,
                excludeSemantics: true,
                label: '查看${song.artistNames}的歌手信息',
                onTap: () => openArtistInfo(
                  context,
                  artists: song.artists,
                  source: song.source,
                ),
                child: ArtistNamesLink(
                  artists: song.artists,
                  source: song.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: compact ? 11 : 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: compact ? 44 : 46,
          height: compact ? 44 : 46,
          child: _FavoriteBtn(song: song, immersive: true),
        ),
      ],
    );
  }
}

class _LyricUtilityRow extends StatelessWidget {
  const _LyricUtilityRow({required this.song, required this.compact});

  final Song song;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ImmersiveIconButton(
          icon: Icons.more_horiz_rounded,
          tooltip: '更多',
          size: compact ? 22 : 25,
          buttonSize: 44,
          onTap: () => showSongActions(context, song: song),
        ),
        Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: _FavoriteBtn(song: song, immersive: true),
            ),
            SizedBox(width: compact ? 16 : 24),
            _ImmersiveIconButton(
              icon: Icons.mic_none_rounded,
              tooltip: '逐字歌词',
              size: compact ? 24 : 27,
              buttonSize: 44,
              onTap: () {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('当前歌曲暂无逐字歌词')),
                  );
              },
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _showSongInfoSheet(
  BuildContext context,
  Song song,
  String quality,
) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _SongInfoSheet(song: song, quality: quality),
  );
}

class _SongInfoSheet extends StatelessWidget {
  const _SongInfoSheet({required this.song, required this.quality});

  final Song song;
  final String quality;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '歌曲百科',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: TypeScale.bold,
                      ),
                    ),
                  ),
                  GIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '关闭歌曲信息',
                    backgroundColor: Colors.transparent,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  AsyncCover(url: song.album.picUrl, size: 64, radius: 8),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: TypeScale.semibold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.artistNames,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SongArtistsSection(song: song),
              const SizedBox(height: 10),
              _SongInfoRow(label: '专辑', value: song.album.name),
              _SongInfoRow(label: '音乐源', value: _sourceLabel(song.source)),
              _SongInfoRow(
                label: '时长',
                value: _ProgressRow._fmt(
                  Duration(milliseconds: song.durationMs),
                ),
              ),
              _SongInfoRow(label: '当前音质', value: _mobileQualityLabel(quality)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongArtistsSection extends StatelessWidget {
  const _SongArtistsSection({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final artists = song.artists.where((artist) {
      final name = artist.name.trim();
      return name.isNotEmpty && name != '未知' && name != '未知歌手';
    }).toList();
    if (artists.isEmpty) {
      return const _SongInfoRow(label: '歌手信息', value: '未知');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '歌手信息',
          style: TextStyle(
            fontSize: 13,
            fontWeight: TypeScale.semibold,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < artists.length; index++) ...[
          _SongArtistRow(song: song, artist: artists[index]),
          if (index != artists.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _SongArtistRow extends StatelessWidget {
  const _SongArtistRow({required this.song, required this.artist});

  final Song song;
  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final artistId = artist.id == 0 ? null : '${artist.id}';
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          ClipOval(
            child: AsyncCover(url: artist.picUrl, size: 38, radius: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ArtistNamesLink(
              artists: [artist],
              source: song.source,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: TypeScale.semibold,
              ),
            ),
          ),
          GIconButton(
            icon: Icons.arrow_forward_ios_rounded,
            tooltip: '查看${artist.name}的歌手资料',
            size: 14,
            padding: 9,
            backgroundColor: Colors.transparent,
            onTap: () => openArtistInfo(
              context,
              artists: [artist],
              source: song.source,
              artistId: artistId,
            ),
          ),
        ],
      ),
    );
  }
}

class _SongInfoRow extends StatelessWidget {
  const _SongInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '未知' : value)),
        ],
      ),
    );
  }
}

String _sourceLabel(String source) => switch (source.toLowerCase()) {
      'netease' => '网易云音乐',
      'qq' => 'QQ 音乐',
      'kugou' => '酷狗音乐',
      'kuwo' => '酷我音乐',
      _ => source,
    };

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
                bufferedPosition: player.bufferedPosition,
                onSeek: player.seek,
                height: compact ? 2 : 2.5,
              ),
            ),
            Row(
              children: [
                Text(_ProgressRow._fmt(position), style: timeStyle),
                Expanded(
                  child: Tooltip(
                    message: '切换音质',
                    child: Semantics(
                      button: true,
                      label: '切换音质，当前$qualityLabel',
                      onTap: onQualityTap,
                      excludeSemantics: true,
                      child: GPressScale(
                        onTap: onQualityTap,
                        child: SizedBox(
                          height: 44,
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
  final song = player.current;
  if (song == null) return;
  final source = song.source;
  final currentQuality = settings.qualityForSource(source);
  final selected = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.44),
    builder: (sheetContext) => _PlaybackQualitySheet(
      source: source,
      selected: normalizeQualityForSource(
        source,
        player.effectiveQuality ?? currentQuality,
      ),
    ),
  );
  if (selected == null || selected == currentQuality || !context.mounted) {
    return;
  }

  final position = player.position;
  final wasPlaying = player.playing;
  await settings.setQualityForSource(source, selected);
  if (!context.mounted || player.current == null) return;

  await player.retry();
  if (player.error == null) {
    await player.seek(position);
    if (!wasPlaying) await player.pause();
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          '已切换为 ${qualityLabelForSource(source, selected)}',
        ),
        duration: const Duration(milliseconds: 1400),
      ),
    );
}

class _PlaybackQualitySheet extends StatelessWidget {
  const _PlaybackQualitySheet({required this.source, required this.selected});

  final String source;
  final String selected;

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${sourceDisplayName(source)} · 当前歌曲音质',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: TypeScale.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (final option in qualityOptionsForSource(source))
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
    this.selected,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final double buttonSize;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        onTap: onTap,
        excludeSemantics: true,
        child: GPressScale(
          onTap: onTap,
          child: SizedBox(
            width: math.max(44, buttonSize),
            height: math.max(44, buttonSize),
            child: Icon(
              icon,
              size: size,
              color: selected == true
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
    final player = context.read<PlayerController>();
    final state =
        context.select<PlayerController, (bool, bool, String?, bool, String)>(
      (player) => (
        player.playing,
        player.loading,
        player.error,
        player.shuffle,
        player.loopMode.name,
      ),
    );
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
                  if (state.$3 != null) ...[
                    const SizedBox(height: 14),
                    _PlaybackErrorBanner(
                      message: state.$3!,
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
                        icon: Icons.shuffle_rounded,
                        tooltip: state.$4 ? '随机播放（已开启）' : '随机播放',
                        size: 26,
                        padding: 10,
                        tint: state.$4 ? scheme.primary : null,
                        onTap: player.toggleShuffle,
                      ),
                      GIconButton(
                        icon: Icons.skip_previous_rounded,
                        tooltip: '上一首',
                        size: 34,
                        padding: 10,
                        onTap: player.previous,
                      ),
                      _PlayPauseButton(
                        playing: state.$1,
                        loading: state.$2,
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
                      GIconButton(
                        icon: state.$5 == 'one'
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        tooltip: switch (state.$5) {
                          'one' => '单曲循环',
                          'all' => '列表循环',
                          _ => '不循环',
                        },
                        size: 26,
                        padding: 10,
                        tint: state.$5 != 'off' ? scheme.primary : null,
                        onTap: player.cycleLoopMode,
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
                        tooltip: '歌词',
                        selected: pane == _PlayerPane.lyrics,
                        onTap: () => onPaneChanged(_PlayerPane.lyrics),
                      ),
                      _PaneButton(
                        icon: Icons.timer_outlined,
                        tooltip: '睡眠定时',
                        onTap: () => _showSleepTimer(context),
                      ),
                      _PaneButton(
                        icon: Icons.queue_music_rounded,
                        tooltip: '播放队列',
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
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        selected: selected,
        onTap: onTap,
        excludeSemantics: true,
        child: GPressScale(
          onTap: onTap,
          child: AnimatedContainer(
            duration: PlatformMotion.duration(context, Motion.fast),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? glassFill(context, alpha: 0.16)
                  : Colors.transparent,
              border: selected
                  ? Border.all(color: Colors.white.withValues(alpha: 0.14))
                  : null,
            ),
            child: Icon(icon, size: 21, color: scheme.onSurface),
          ),
        ),
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
                        duration: PlatformMotion.duration(context, Motion.fast),
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
    final immersive = Theme.of(context).scaffoldBackgroundColor == Colors.black;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: immersive
            ? scheme.error.withValues(alpha: 0.16)
            : scheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(RadiusToken.md),
        border: Border.all(
          color: immersive
              ? AppBrand.cueYellow.withValues(alpha: 0.60)
              : scheme.error.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: immersive ? Colors.white : scheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: immersive ? Colors.white : scheme.onSurface,
              ),
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
    final label = loading
        ? '正在加载'
        : playing
            ? '暂停'
            : '播放';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        enabled: !loading,
        onTap: loading ? null : onTap,
        excludeSemantics: true,
        child: GPressScale(
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
            child: AnimatedSwitcher(
              duration: PlatformMotion.duration(context, Motion.normal),
              reverseDuration: PlatformMotion.duration(context, Motion.fast),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.72, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: loading
                  ? Padding(
                      key: const ValueKey('playback-loading'),
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
                      key: ValueKey(playing ? 'pause' : 'play'),
                      size: size * (immersive ? 0.78 : 0.52),
                      color: immersive
                          ? Colors.white.withValues(alpha: 0.82)
                          : dark
                              ? Colors.black
                              : Colors.white,
                    ),
            ),
          ),
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
  bool _loaded = false;
  String? _token;
  int _requestVersion = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = context.watch<AuthController>().token;
    if (!_loaded || _token != token) {
      _loaded = true;
      _token = token;
      _refresh();
    }
  }

  @override
  void didUpdateWidget(covariant _FavoriteBtn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.song.source != widget.song.source) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final request = ++_requestVersion;
    final song = widget.song;
    final token = context.read<AuthController>().token;
    _fav = false;
    _busy = false;
    if (token == null) return;
    try {
      final items = await UserApi().getFavorites(token);
      if (!mounted || !_isCurrentRequest(request, song, token)) return;
      setState(() {
        _fav = items.any(
          (e) {
            final id = e['songId'] ?? e['id'];
            final source = e['source'] ?? 'netease';
            return id?.toString() == song.id &&
                source.toString() == song.source;
          },
        );
      });
      final player = context.read<PlayerController>();
      if (player.current?.id == song.id &&
          player.current?.source == song.source) {
        player.setLiked(_fav);
      }
    } catch (_) {}
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再收藏')),
      );
      return;
    }
    final request = ++_requestVersion;
    final song = widget.song;
    final wasFavorite = _fav;
    setState(() => _busy = true);
    try {
      if (wasFavorite) {
        await UserApi().removeFavorite(song.id, song.source, token);
      } else {
        await UserApi().addFavorite(song, token);
      }
      if (mounted && _isCurrentRequest(request, song, token)) {
        setState(() => _fav = !wasFavorite);
        final player = context.read<PlayerController>();
        if (player.current?.id == song.id &&
            player.current?.source == song.source) {
          player.setLiked(_fav);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_fav ? '已收藏' : '已取消收藏')),
        );
      }
    } catch (_) {
      if (mounted && _isCurrentRequest(request, song, token)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请稍后重试')),
        );
      }
    } finally {
      if (_isCurrentRequest(request, song, token)) {
        setState(() => _busy = false);
      }
    }
  }

  bool _isCurrentRequest(int request, Song song, String token) =>
      mounted &&
      request == _requestVersion &&
      widget.song.id == song.id &&
      widget.song.source == song.source &&
      context.read<AuthController>().token == token;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: _fav ? '取消收藏' : '收藏歌曲',
      child: Semantics(
        button: true,
        enabled: !_busy,
        toggled: _fav,
        label: _fav ? '取消收藏' : '收藏歌曲',
        onTap: _busy ? null : _toggle,
        excludeSemantics: true,
        child: GPressScale(
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
                : GPopIcon(
                    icon: _fav
                        ? Icons.favorite_rounded
                        : Icons.favorite_outline_rounded,
                    active: _fav,
                    size: 22,
                    activeColor: scheme.primary,
                    color: widget.immersive
                        ? Colors.white.withValues(alpha: 0.92)
                        : scheme.onSurface,
                  ),
          ),
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
                    bufferedPosition: player.bufferedPosition,
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
  bool _userScrolling = false;
  Timer? _scrollResumeTimer;

  void _resumeFollowing() {
    _scrollResumeTimer?.cancel();
    if (!mounted) return;
    setState(() => _userScrolling = false);
    final position = context.read<PlayerController>().position;
    _scheduleScroll(_currentLineFor(position), force: true);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    final startedDragging = notification is ScrollStartNotification &&
        notification.dragDetails != null;
    final userMoved = notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle;
    if (startedDragging || userMoved) {
      _scrollResumeTimer?.cancel();
      if (!_userScrolling) setState(() => _userScrolling = true);
    } else if (notification is ScrollEndNotification && _userScrolling) {
      _scrollResumeTimer?.cancel();
      _scrollResumeTimer = Timer(const Duration(seconds: 5), _resumeFollowing);
    }
    return false;
  }

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
      _userScrolling = false;
      _scrollResumeTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _scrollResumeTimer?.cancel();
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
    return StreamBuilder<int>(
      stream: player.positionStream.map(_currentLineFor).distinct(),
      initialData: _currentLineFor(player.position),
      builder: (context, snapshot) {
        final current = snapshot.data ?? _currentLineFor(player.position);
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
            Widget list = NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: ListView.builder(
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
                            duration:
                                PlatformMotion.duration(context, Motion.normal),
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
                              fontWeight: isCurrent
                                  ? TypeScale.bold
                                  : TypeScale.semibold,
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
              ),
            );
            if (widget.immersive) {
              list = RepaintBoundary(
                child: ShaderMask(
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
                ),
              );
            }
            if (widget.onBackgroundTap != null) {
              list = GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onBackgroundTap,
                child: list,
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                list,
                if (_userScrolling)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: GButton(
                      label: '回到当前',
                      filled: false,
                      small: true,
                      onTap: _resumeFollowing,
                    ),
                  ),
              ],
            );
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

  void _scheduleScroll(int current, {bool force = false}) {
    if (!force && current == _lastCurrentLine) return;
    if (_userScrolling) return; // Don't auto-scroll when user is scrolling
    final initialAlignment = _lastCurrentLine == -1;
    _lastCurrentLine = current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_userScrolling) return;
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
        final duration = PlatformMotion.duration(context, Motion.slow);
        if (initialAlignment || duration == Duration.zero) {
          _controller.jumpTo(clampedTarget);
        } else {
          _controller.animateTo(
            clampedTarget,
            duration: duration,
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
