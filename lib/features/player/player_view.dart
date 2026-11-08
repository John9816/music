import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
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
import '../../core/player/playback_time.dart';
import '../../core/services/sleep_timer.dart';
import '../../core/services/cast_service.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/settings/lyric_appearance.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../../widgets/playback_mode_button.dart';
import '../profile/login_view.dart';
import '../profile/profile_view.dart';
import '../search/artist_names_link.dart';
import '../../widgets/song_action_menu.dart';
import '../../core/theme/app_animations.dart';
import 'queue_view.dart';
import 'karaoke_lyric_text.dart';
import 'reference_player_effects.dart';
import 'spectrum_player_view.dart';
import 'sleep_timer_dialog.dart';

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
      if (reducedMotion) return child;
      final curved = animation.drive(
        CurveTween(curve: AppAnimations.pageTransition),
      );
      final slide = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curved);
      final opacity = Tween<double>(begin: 0.92, end: 1).animate(curved);

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
          if (wide) _AmbientBackground(coverUrl: current.album.picUrl),
          SafeArea(
            top: wide && Theme.of(context).platform != TargetPlatform.macOS,
            bottom: wide,
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
  });

  final String? coverUrl;

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
              scale: 1.08,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 70,
                  sigmaY: 70,
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
            color: dark
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
                  scheme.primary.withValues(alpha: dark ? 0.20 : 0.10),
                  Colors.transparent,
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
    return GToolbar(
      actions: [
        GToolbarButton(
          icon: Icons.close_rounded,
          tooltip: '关闭播放器',
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// A tonal mobile player with a quiet transport and an expanded reading pane.
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
  final VoidCallback onDismissDragCancel;

  @override
  State<_MobilePlayer> createState() => _MobilePlayerState();
}

class _MobilePlayerState extends State<_MobilePlayer> {
  final _pageController = PageController();
  final _castService = CastService();
  final _pagesKey = GlobalKey();
  final _controlsKey = GlobalKey();
  int _page = 0;
  bool _addingPlaylist = false;

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
    } else {
      _pageController.animateToPage(page,
          duration: duration, curve: Motion.standard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final original = Theme.of(context);
    final theme = original.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: original.colorScheme.copyWith(
        brightness: Brightness.dark,
        surface: const Color(0xff16191e),
        onSurface: const Color(0xfff3f5fa),
        onSurfaceVariant: const Color(0xffc1ccd8),
        primary: const Color(0xffc5dcee),
      ),
    );
    final state = context.select<PlayerController, (String, String?)>(
      (player) => (player.lyric, player.error),
    );
    return Theme(
        data: theme,
        child: Builder(builder: (context) {
          final lyrics = _page == 1;
          return PopScope<void>(
            canPop: !lyrics,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && lyrics) _showPage(0);
            },
            child: Stack(fit: StackFit.expand, children: [
              ReferenceArtworkBackground(coverUrl: widget.song.album.picUrl),
              SafeArea(child: LayoutBuilder(builder: (context, constraints) {
                final compact =
                    constraints.maxHeight < 680 || constraints.maxWidth < 360;
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
                            'mobile-cover-${widget.song.source}:${widget.song.id}'),
                        song: widget.song),
                    _LyricView(
                        key: ValueKey(
                            'mobile-lyrics-${widget.song.source}:${widget.song.id}'),
                        lrc: state.$1,
                        immersive: true,
                        compact: compact),
                  ],
                );
                final controls = SingleChildScrollView(
                  key: _controlsKey,
                  primary: false,
                  child: _MobileControls(
                      song: widget.song,
                      error: state.$2,
                      compact: compact,
                      onMore: _showMore,
                      onLyrics: () => _showPage(1),
                      onSettings: _showSettings,
                      onAddPlaylist: _addPlaylist),
                );
                return Column(children: [
                  GestureDetector(
                    key: const ValueKey('mobile-player-dismiss-region'),
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart:
                        lyrics ? null : widget.onDismissDragStart,
                    onVerticalDragUpdate:
                        lyrics ? null : widget.onDismissDragUpdate,
                    onVerticalDragEnd: lyrics ? null : widget.onDismissDragEnd,
                    onVerticalDragCancel:
                        lyrics ? null : widget.onDismissDragCancel,
                    child: _MobilePlayerTopBar(
                        song: widget.song,
                        showingLyrics: lyrics,
                        onShowCover: () => _showPage(0)),
                  ),
                  Expanded(
                      child: landscape && !lyrics
                          ? Row(children: [
                              Expanded(child: pages),
                              Expanded(child: controls)
                            ])
                          : LayoutBuilder(
                              builder: (context, body) => Column(children: [
                                    Expanded(child: pages),
                                    if (!lyrics)
                                      ConstrainedBox(
                                          constraints: BoxConstraints(
                                              maxHeight: math.max(
                                                  180, body.maxHeight - 80)),
                                          child: controls),
                                  ]))),
                ]);
              })),
            ]),
          );
        }));
  }

  Future<void> _addPlaylist() async {
    if (_addingPlaylist) return;
    _addingPlaylist = true;
    try {
      await showAddSongToPlaylist(context, song: widget.song);
    } finally {
      _addingPlaylist = false;
    }
  }

  Future<void> _showSettings() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('睡眠定时'),
                  onTap: () => Navigator.pop(sheet, 'sleep')),
              ListTile(
                  leading: const Icon(Icons.graphic_eq_rounded),
                  title: const Text('频谱视图'),
                  onTap: () => Navigator.pop(sheet, 'spectrum')),
              const SizedBox(height: 16),
            ]),
          )),
    );
    if (!mounted) return;
    switch (action) {
      case 'sleep':
        showReferenceSleepTimer(context);
      case 'spectrum':
        Navigator.of(context).push(
            buildAppRoute<void>(context, (_) => const SpectrumPlayerView()));
    }
  }

  Future<void> _showMore() async {
    final player = context.read<PlayerController>();
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final item in [
                ('song', Icons.more_horiz_rounded, '歌曲操作'),
                ('device', Icons.airplay_rounded, 'AirPlay 或蓝牙'),
                ('info', Icons.info_outline_rounded, '歌曲百科'),
              ])
                ListTile(
                  leading: Icon(item.$2),
                  title: Text(item.$3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  onTap: () => Navigator.of(context).pop(item.$1),
                ),
            ]),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'song':
        showSongActions(context,
            song: widget.song,
            queueIndex: player.queueIndex,
            downloadOnly: true);
      case 'device':
        await _castService.showDevicePicker();
        if (mounted && _castService.message.isNotEmpty) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(_castService.message)));
        }
      case 'info':
        final quality = player.effectiveQuality ??
            context
                .read<SettingsController>()
                .qualityForSource(widget.song.source);
        _showSongInfoSheet(context, widget.song, quality);
    }
  }
}

class _MobilePlayerTopBar extends StatelessWidget {
  const _MobilePlayerTopBar(
      {required this.song,
      required this.showingLyrics,
      required this.onShowCover});
  final Song song;
  final bool showingLyrics;
  final VoidCallback onShowCover;
  @override
  Widget build(BuildContext context) => GToolbar(
        leading: GToolbarButton(
            icon: showingLyrics
                ? Icons.close_rounded
                : Icons.arrow_downward_rounded,
            tooltip: showingLyrics ? '返回封面' : '收起播放器',
            onTap: showingLyrics
                ? onShowCover
                : () => Navigator.of(context).maybePop()),
        title: SizedBox(
            key: ValueKey(showingLyrics ? 'lyric-spacer' : 'cover-title')),
        actions: [
          if (showingLyrics)
            Semantics(
                key: const ValueKey('lyric-title'),
                label: '${song.name}，${song.artistNames}',
                child: Tooltip(
                    message: '通过封面返回',
                    child: GPressScale(
                        key: const ValueKey('lyric-cover-return'),
                        scale: 0.92,
                        borderRadius: BorderRadius.circular(8),
                        onTap: onShowCover,
                        child: AsyncCover(
                            url: song.album.picUrl,
                            size: GToolbarButton.extent,
                            radius: 8))))
          else
            _FavoriteBtn(song: song),
        ],
      );
}

class _MobileCoverStage extends StatelessWidget {
  const _MobileCoverStage({super.key, required this.song});
  final Song song;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = math.max(
          0.0,
          math.min(math.min(constraints.maxWidth - 48, 420.0),
              constraints.maxHeight - 16));
      return Center(
        child: RepaintBoundary(
          child: AsyncCover(
              key: const ValueKey('mobile-player-artwork'),
              url: song.album.picUrl,
              size: size,
              radius: 28),
        ),
      );
    });
  }
}

class _MobileControls extends StatelessWidget {
  const _MobileControls(
      {required this.song,
      required this.error,
      required this.compact,
      required this.onMore,
      required this.onLyrics,
      required this.onSettings,
      required this.onAddPlaylist});
  final Song song;
  final String? error;
  final bool compact;
  final VoidCallback onMore, onLyrics, onSettings, onAddPlaylist;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final state = context.select<PlayerController, (bool, bool, String?)>(
        (p) => (p.playing, p.loading, p.effectiveQuality));
    final requested = context.select<SettingsController, String>(
        (s) => s.qualityForSource(song.source));
    return Center(
        child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Padding(
        padding: EdgeInsets.fromLTRB(28, compact ? 8 : 24, 28, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (error != null)
            _PlaybackErrorBanner(
                message: error!,
                actionLabel: _playbackActionLabel(player),
                onAction: () => _handlePlaybackError(context, player)),
          _MobileSongSummary(song: song, compact: compact, onMore: onMore),
          SizedBox(height: compact ? 2 : 18),
          _MobileProgressRow(
              key: ValueKey((song.source, song.id)),
              qualityLabel: _mobileQualityLabel(state.$3 ?? requested),
              compact: compact,
              onQualityTap: () => _showPlaybackQualitySheet(context)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _ImmersiveIconButton(
                icon: CupertinoIcons.backward_end_fill,
                tooltip: '上一首',
                size: 25,
                buttonSize: 56,
                onTap: player.previous),
            _PlayPauseButton(
                playing: state.$1,
                loading: state.$2,
                onTap: player.togglePlay,
                large: true,
                compact: compact),
            _ImmersiveIconButton(
                icon: CupertinoIcons.forward_end_fill,
                tooltip: '下一首',
                size: 25,
                buttonSize: 56,
                onTap: player.next),
          ]),
          SizedBox(height: compact ? 0 : 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            const PlaybackModeButton(),
            _ImmersiveIconButton(
                icon: Icons.chat_bubble_outline_rounded,
                tooltip: '查看歌词',
                onTap: onLyrics),
            _ImmersiveIconButton(
                icon: Icons.add_rounded,
                tooltip: '添加到歌单',
                onTap: onAddPlaylist),
            _ImmersiveIconButton(
                icon: Icons.view_headline_rounded,
                tooltip: '播放队列',
                onTap: () => showQueueSheet(context)),
            _ImmersiveIconButton(
                icon: Icons.tune_rounded, tooltip: '播放设置', onTap: onSettings),
          ]),
        ]),
      ),
    ));
  }
}

class _MobileSongSummary extends StatelessWidget {
  const _MobileSongSummary(
      {required this.song, required this.compact, required this.onMore});
  final Song song;
  final bool compact;
  final VoidCallback onMore;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Expanded(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(song.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: compact ? 20 : 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.4,
                    height: 1.2)),
            const SizedBox(height: 5),
            Semantics(
                button: true,
                excludeSemantics: true,
                label: '查看${song.artistNames}的歌手信息',
                onTap: () => openArtistInfo(context,
                    artists: song.artists, source: song.source),
                child: ArtistNamesLink(
                    artists: song.artists,
                    source: song.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 15))),
          ])),
      const SizedBox(width: 10),
      DecoratedBox(
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: .16))),
          child: _ImmersiveIconButton(
              icon: Icons.more_vert_rounded, tooltip: '更多', onTap: onMore)),
    ]);
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

class _MobileProgressRow extends StatefulWidget {
  const _MobileProgressRow({
    super.key,
    required this.qualityLabel,
    required this.compact,
    required this.onQualityTap,
  });

  final String qualityLabel;
  final bool compact;
  final VoidCallback onQualityTap;

  @override
  State<_MobileProgressRow> createState() => _MobileProgressRowState();
}

class _MobileProgressRowState extends State<_MobileProgressRow> {
  Duration? _previewPosition;

  @override
  Widget build(BuildContext context) {
    final duration =
        context.select<PlayerController, Duration?>((p) => p.duration);
    final player = context.read<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final timeStyle = TextStyle(
      color: scheme.onSurfaceVariant,
      fontSize: 12,
      fontWeight: TypeScale.semibold,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final position = _previewPosition ?? snapshot.data ?? player.position;
        final total = duration ?? Duration.zero;
        final time = PlaybackTime(position: position, duration: duration);
        return Column(
          children: [
            GProgressBar(
              position: snapshot.data ?? player.position,
              duration: total,
              bufferedPosition: player.bufferedPosition,
              onSeek: player.seek,
              onPreviewChanged: (value) =>
                  setState(() => _previewPosition = value),
              height: 2.5,
              wave: true,
              playing: playing,
              activeColor: scheme.onSurface,
            ),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(time.elapsed, style: timeStyle)),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Tooltip(
                    message: '切换音质',
                    child: Semantics(
                      button: true,
                      label: '切换音质，当前${widget.qualityLabel}',
                      onTap: widget.onQualityTap,
                      excludeSemantics: true,
                      child: GPressScale(
                        onTap: widget.onQualityTap,
                        child: SizedBox(
                          height: 48,
                          child: Center(
                            child: Text(
                              widget.qualityLabel,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: timeStyle.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(time.remaining, style: timeStyle)),
                  ),
                ),
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
    context: Navigator.of(context, rootNavigator: true).context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.44),
    sheetAnimationStyle: AnimationStyle(
      duration: PlatformMotion.duration(context, Motion.slow),
      reverseDuration: PlatformMotion.duration(context, Motion.normal),
    ),
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
  bool isCurrentSong() =>
      player.current?.id == song.id && player.current?.source == song.source;
  await settings.setQualityForSource(source, selected);
  if (!context.mounted || !isCurrentSong()) return;

  await player.retry();
  if (!context.mounted || !isCurrentSong()) return;
  if (player.error == null) {
    await player.seek(position);
    if (!context.mounted || !isCurrentSong()) return;
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
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Color(0xF21A1918),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SingleChildScrollView(
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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 62),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
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
                              mainAxisSize: MainAxisSize.min,
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final double buttonSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        onTap: onTap,
        excludeSemantics: true,
        child: GPressScale(
          onTap: onTap,
          scale: 0.92,
          borderRadius: BorderRadius.circular(RadiusToken.pill),
          feedbackColor:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
          child: SizedBox(
            width: math.max(
                PlatformMotion.isAndroid(context) ? 48 : 44, buttonSize),
            height: math.max(
                PlatformMotion.isAndroid(context) ? 48 : 44, buttonSize),
            child: Icon(
              icon,
              size: size,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final state = context.select<PlayerController, (bool, bool, String?)>(
      (player) => (
        player.playing,
        player.loading,
        player.error,
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
                      GIconButton(
                        icon: Icons.more_horiz_rounded,
                        tooltip: '更多',
                        size: 24,
                        backgroundColor: Colors.transparent,
                        onTap: () => showSongActions(
                          context,
                          song: song,
                          queueIndex: player.queueIndex,
                          downloadOnly: true,
                        ),
                      ),
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
                  _ProgressRow(key: ValueKey((song.source, song.id))),
                  const SizedBox(height: 13),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const PlaybackModeButton(size: 26),
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
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 20),
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
            ),
            child: Icon(icon, size: 21, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

void _showSleepTimer(BuildContext context) {
  final timer = context.read<SleepTimer>();
  final player = context.read<PlayerController>();
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    sheetAnimationStyle: AnimationStyle(
      duration: PlatformMotion.duration(context, Motion.slow),
      reverseDuration: PlatformMotion.duration(context, Motion.normal),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        child: SingleChildScrollView(
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
                        constraints: const BoxConstraints(minHeight: 68),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: current
                              ? scheme.onSurface.withValues(alpha: 0.07)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Row(
                          children: [
                            AsyncCover(
                              url: song.album.picUrl,
                              size: 44,
                              radius: 8,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    song.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
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
                                      fontSize: 13,
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
                            SongActionButton(
                              song: song,
                              queueIndex: index,
                              onPlay: () => player.playAt(index),
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
  if (player.requiresMembership) return '查看会员状态';
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
    this.compact = false,
  });

  final bool playing;
  final bool loading;
  final VoidCallback onTap;
  final bool large;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = compact
        ? 56.0
        : large
            ? 76.0
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
          scale: 0.94,
          borderRadius: BorderRadius.circular(RadiusToken.pill),
          feedbackColor: scheme.surface.withValues(alpha: 0.08),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.onSurface,
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
                      padding: const EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: scheme.surface,
                      ),
                    )
                  : Icon(
                      playing
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      key: ValueKey(playing ? 'pause' : 'play'),
                      size: size * 0.46,
                      color: scheme.surface,
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
  const _FavoriteBtn({required this.song});

  final Song song;

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
          scale: 0.92,
          borderRadius: BorderRadius.circular(RadiusToken.pill),
          feedbackColor: scheme.onSurface.withValues(alpha: 0.08),
          child: Container(
            width: GToolbarButton.extent,
            height: GToolbarButton.extent,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.onSurface.withValues(alpha: 0.04),
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
                    activeColor: AppBrand.favoriteRed,
                    color: scheme.onSurface,
                  ),
          ),
        ),
      ),
    );
  }
}

/// 进度条 + 时间（高频刷新，独立订阅 position/duration）
class _ProgressRow extends StatefulWidget {
  const _ProgressRow({super.key});

  @override
  State<_ProgressRow> createState() => _ProgressRowState();

  static String _fmt(Duration d) {
    return formatPlaybackDuration(d);
  }
}

class _ProgressRowState extends State<_ProgressRow> {
  Duration? _previewPosition;

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
        final position = _previewPosition ?? snapshot.data ?? player.position;
        final time = PlaybackTime(position: position, duration: duration);
        return Row(
          children: [
            Text(time.elapsed, style: timeStyle),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Theme(
                  data: Theme.of(context),
                  child: GProgressBar(
                    position: snapshot.data ?? player.position,
                    duration: duration ?? Duration.zero,
                    bufferedPosition: player.bufferedPosition,
                    onSeek: player.seek,
                    onPreviewChanged: (value) =>
                        setState(() => _previewPosition = value),
                    height: 4,
                  ),
                ),
              ),
            ),
            Text(time.remaining, style: timeStyle),
          ],
        );
      },
    );
  }
}

/// 歌词视图：当前句清晰聚焦，周围歌词随距离淡出并虚化。
class _LyricView extends StatefulWidget {
  const _LyricView({
    super.key,
    required this.lrc,
    this.immersive = false,
    this.compact = false,
  });

  final String lrc;
  final bool immersive;
  final bool compact;

  @override
  State<_LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends State<_LyricView> {
  final ScrollController _controller = ScrollController();
  List<LrcLine> _lines = const [];
  int _lastCurrentLine = -1;
  bool _userScrolling = false;
  Timer? _scrollResumeTimer;
  Object? _layoutSignature;
  final List<double> _lineHeights = [];
  final List<double> _lineOffsets = [];
  double _topPadding = 0;
  double _viewportHeight = 0;

  Future<void> _seekToLine(int index) async {
    _scrollResumeTimer?.cancel();
    await context.read<PlayerController>().seek(_lines[index].time);
    if (mounted) _resumeFollowing();
  }

  void _measureLines(
      BuildContext context, BoxConstraints constraints, TextStyle activeStyle) {
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final signature =
        (constraints.maxWidth, textScaler, direction, locale, activeStyle);
    if (_layoutSignature != signature) {
      _layoutSignature = signature;
      _lastCurrentLine = -1;
      _lineHeights.clear();
      _lineOffsets.clear();
      final painter = TextPainter(
          textDirection: direction, textScaler: textScaler, locale: locale);
      final width =
          math.max(1.0, constraints.maxWidth - (widget.immersive ? 68 : 60));
      var offset = 0.0;
      for (final line in _lines) {
        painter.text = TextSpan(
            text: line.text.isEmpty ? '· · ·' : line.text, style: activeStyle);
        painter.layout(maxWidth: width);
        // All focus states use the same typography, preserving both wrapping
        // and scroll geometry. Long lyrics and large text can wrap freely.
        final height = math.max(widget.immersive ? 140.0 : 58.0,
            painter.height.ceilToDouble() + (widget.immersive ? 28 : 24));
        _lineOffsets.add(offset);
        _lineHeights.add(height);
        offset += height;
      }
      painter.dispose();
    }
    if (_viewportHeight != constraints.maxHeight) {
      _viewportHeight = constraints.maxHeight;
      _lastCurrentLine = -1;
    }
    _topPadding = math.max(0.0, (_viewportHeight - _lineHeights.first) / 2);
  }

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
      _layoutSignature = null;
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading && widget.lrc.isEmpty) ...[
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
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
                style: widget.lrc.isNotEmpty
                    ? lyricTextStyle(
                        DefaultTextStyle.of(context)
                            .style
                            .copyWith(color: scheme.onSurface),
                        fontSize:
                            context.watch<SettingsController>().lyricFontSize,
                        fontStyle:
                            context.watch<SettingsController>().lyricFontStyle,
                      )
                    : TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: widget.immersive ? 16 : null,
                      ),
              ),
            ],
          ),
        ),
      );
      return empty;
    }
    final player = context.read<PlayerController>();
    final appearance =
        context.select<SettingsController, (int, LyricFontStyle)>(
            (s) => (s.lyricFontSize, s.lyricFontStyle));
    return StreamBuilder<int>(
      stream: player.positionStream.map(_currentLineFor).distinct(),
      initialData: _currentLineFor(player.position),
      builder: (context, snapshot) {
        final current = snapshot.data ?? _currentLineFor(player.position);
        final activeStyle = lyricTextStyle(
          DefaultTextStyle.of(context).style.copyWith(color: scheme.onSurface),
          fontSize: appearance.$1,
          fontStyle: appearance.$2,
          scale: (widget.immersive ? (widget.compact ? 24 : 28) : 26) / 28,
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            _measureLines(context, constraints, activeStyle);
            _scheduleScroll(current);
            Widget list = NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: ListView.builder(
                controller: _controller,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  widget.immersive ? 34 : 30,
                  _topPadding,
                  widget.immersive ? 34 : 30,
                  math.max(0.0, (_viewportHeight - _lineHeights.last) / 2),
                ),
                itemCount: _lines.length,
                itemExtentBuilder: (index, _) => _lineHeights[index],
                itemBuilder: (context, i) {
                  final isCurrent = i == current;
                  return Semantics(
                    button: true,
                    selected: isCurrent,
                    label: '跳转到 ${_formatLyricTime(_lines[i].time)}',
                    child: GPressScale(
                      onTap: () => _seekToLine(i),
                      scale: 1,
                      feedbackColor: widget.immersive
                          ? scheme.onSurface.withValues(alpha: 0.08)
                          : null,
                      child: SizedBox(
                        height: _lineHeights[i],
                        child: Align(
                          alignment: widget.immersive
                              ? Alignment.center
                              : Alignment.centerLeft,
                          child: _LyricFocusLine(
                            line: _lines[i],
                            style: activeStyle,
                            distance: (i - current).abs(),
                            browsing: _userScrolling,
                            centered: widget.immersive,
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
                    stops: [0, 0.10, 0.90, 1],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: list,
                ),
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
      if (!mounted || current != _lastCurrentLine) return;
      if (_userScrolling) return;
      if (!_controller.hasClients) {
        _lastCurrentLine = -1;
        _scheduleScroll(current);
        return;
      }
      if (current >= _lineHeights.length) return;
      final target = _topPadding +
          _lineOffsets[current] +
          _lineHeights[current] / 2 -
          _controller.position.viewportDimension / 2;
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

/// Animate focus without changing font metrics or rebuilding on every tick of
/// playback. Browsing and accessibility modes keep every visible line legible.
class _LyricFocusLine extends StatelessWidget {
  const _LyricFocusLine({
    required this.line,
    required this.style,
    required this.distance,
    required this.browsing,
    this.centered = false,
  });

  final LrcLine line;
  final TextStyle style;
  final int distance;
  final bool browsing;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final clear = browsing ||
        MediaQuery.highContrastOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final opacity = centered && !clear && distance > 1
        ? 0.0
        : distance == 0
            ? 1.0
            : clear
                ? 0.78
                : switch (distance) {
                    1 => 0.56,
                    2 => 0.38,
                    _ => 0.26,
                  };
    final blur = centered || clear
        ? 0.0
        : switch (distance) {
            0 => 0.0,
            1 => 0.45,
            2 => 1.1,
            3 => 1.9,
            _ => 2.6,
          };
    final duration = PlatformMotion.duration(context, Motion.normal);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: blur),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, sigma, child) => ImageFiltered(
        enabled: sigma > 0.01,
        imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
      child: AnimatedDefaultTextStyle(
        duration: duration,
        curve: Curves.easeOutCubic,
        style: style.copyWith(color: style.color!.withValues(alpha: opacity)),
        child: distance == 0 && line.words.isNotEmpty && !clear
            ? _CurrentKaraokeLine(line: line, style: style, centered: centered)
            : Text(line.text.isEmpty ? '· · ·' : line.text,
                textAlign: centered ? TextAlign.center : TextAlign.left),
      ),
    );
  }
}

class _CurrentKaraokeLine extends StatelessWidget {
  const _CurrentKaraokeLine(
      {required this.line, required this.style, this.centered = false});

  final bool centered;

  final LrcLine line;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final player = context.read<PlayerController>();
    return KaraokeLyricText(
      line: line,
      style: style,
      position: player.position,
      positionStream: player.positionStream,
      playing: playing,
      textAlign: centered ? TextAlign.center : TextAlign.left,
    );
  }
}
