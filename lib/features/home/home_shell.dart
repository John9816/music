import '../car/car_home_view.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/services/desktop_integration_service.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/user_playlist_library.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/utils/toast_helper.dart';
import '../../widgets/glass.dart';
import '../../widgets/floating_dock_surface.dart';
import '../../widgets/user_avatar.dart';
import '../discover/discover_view.dart';
import '../playlists/playlists_view.dart';
import '../playlists/playlist_import_view.dart';
import '../player/mini_player.dart';
import '../player/desktop_player_panel.dart';
import '../profile/login_view.dart';
import '../profile/profile_view.dart';
import '../profile/user_library_view.dart';
import '../search/search_view.dart';

/// 主框架：左侧导航（搜索 + 功能 + 我的歌单 + 用户信息）+ 内容区 + 底部全局播放栏。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _discoverIndex = 2;
  static const _favoritesIndex = 3;
  static const _historyIndex = 4;
  static const _profileIndex = 5;
  static const _pageCount = 6;

  int _index = 0;
  String? _pendingSearchQuery;
  int _sourceVersion = 0;
  MiniPlayerPanel? _miniPlayerPanel;
  String? _activePlaylistId;
  final Set<int> _visitedPages = {0};
  final List<Widget?> _pageCache = List<Widget?>.filled(_pageCount, null);
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'library-search');
  final List<GlobalKey<_TabNavigatorState>> _tabKeys = List.generate(
    _pageCount,
    (_) => GlobalKey<_TabNavigatorState>(),
  );
  final List<ValueNotifier<bool>> _tabCanPop = List.generate(
    _pageCount,
    (_) => ValueNotifier(false),
  );
  late String _lastSource;
  late final SettingsController _settings;
  late final PlayerController _player;
  late final AuthController _auth;
  late int _lastAuthGeneration;
  int _authVersion = 0;
  bool _favoriteBusy = false;

  static const _tabToPageIndex = [0, 1, _discoverIndex, _profileIndex];

  static const _tabs = [
    (
      label: '首页',
      icon: CupertinoIcons.house,
      selectedIcon: CupertinoIcons.house_fill
    ),
    (
      label: '搜索',
      icon: CupertinoIcons.search,
      selectedIcon: CupertinoIcons.search
    ),
    (
      label: '发现',
      icon: CupertinoIcons.square_stack,
      selectedIcon: CupertinoIcons.square_stack_fill
    ),
    (
      label: '我的',
      icon: CupertinoIcons.person,
      selectedIcon: CupertinoIcons.person_fill
    ),
  ];

  @override
  void initState() {
    super.initState();
    _settings = context.read<SettingsController>();
    _player = context.read<PlayerController>();
    _auth = context.read<AuthController>();
    _lastAuthGeneration = _auth.sessionGeneration;
    _lastSource = _settings.source;
    _player.onSongPlayed ??= _recordPlayedSong;
    _player.onSongChanged ??= _syncFavoriteState;
    _player.onMembershipRequired = _openMembershipCenter;
    context.read<DesktopIntegrationService>().onFavorite = _toggleFavorite;
    unawaited(_restoreLastPlayback());
    _settings.addListener(_onSettingsChanged);
    _auth.addListener(_onAuthChanged);
  }

  Future<void> _restoreLastPlayback() {
    final token = _auth.token;
    return _player.restoreLastPlayback(
      preferredLoader: token == null
          ? null
          : () async {
              final latest = await UserApi().getLatestHistory(token);
              return latest == null ? null : Song.fromUserLibraryItem(latest);
            },
    );
  }

  void _recordPlayedSong(Song song) {
    final token = _auth.token;
    if (!_auth.isLoggedIn || token == null) return;
    UserApi().addHistory(song, token).catchError((_) {});
  }

  Future<void> _syncFavoriteState(Song song) async {
    final token = _auth.token;
    final generation = _auth.sessionGeneration;
    if (!_auth.isLoggedIn || token == null) {
      _player.setLiked(false);
      return;
    }
    try {
      final items = await UserApi().getFavorites(token);
      if (!mounted || generation != _auth.sessionGeneration) return;
      final current = _player.current;
      if (current?.id != song.id || current?.source != song.source) return;
      _player.setLiked(
        items.any((item) {
          final id = item['songId'] ?? item['id'];
          final source = item['source'] ?? 'netease';
          return id?.toString() == song.id && source.toString() == song.source;
        }),
      );
    } catch (_) {
      // 收藏状态查询失败不影响播放。
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    final song = _player.current;
    final token = _auth.token;
    if (song == null) return;
    if (!_auth.isLoggedIn || token == null) {
      if (!mounted) return;
      showAppToast(context, '请先登录后再收藏');
      return;
    }
    _favoriteBusy = true;
    final generation = _auth.sessionGeneration;
    final wasLiked = _player.liked;
    try {
      if (wasLiked) {
        await UserApi().removeFavorite(song.id, song.source, token);
      } else {
        await UserApi().addFavorite(song, token);
      }
      if (!mounted ||
          generation != _auth.sessionGeneration ||
          _player.current?.id != song.id ||
          _player.current?.source != song.source) {
        return;
      }
      _player.setLiked(!wasLiked);
    } catch (_) {
      if (mounted && generation == _auth.sessionGeneration) {
        showAppToast(context, '收藏操作失败，请重试');
      }
    } finally {
      _favoriteBusy = false;
    }
  }

  void _openMembershipCenter() {
    if (!mounted) return;
    switchTo(_profileIndex);
    showAppToast(
      context,
      '播放需要有效会员，可在个人中心查看会员状态',
      action: SnackBarAction(
        label: '查看会员',
        onPressed: () => switchTo(_profileIndex),
      ),
    );
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _auth.removeListener(_onAuthChanged);
    _searchFocusNode.dispose();
    if (_player.onSongPlayed == _recordPlayedSong) {
      _player.onSongPlayed = null;
    }
    if (_player.onSongChanged == _syncFavoriteState) {
      _player.onSongChanged = null;
    }
    if (_player.onMembershipRequired == _openMembershipCenter) {
      _player.onMembershipRequired = null;
    }
    for (final notifier in _tabCanPop) {
      notifier.dispose();
    }
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted || _lastAuthGeneration == _auth.sessionGeneration) return;
    _lastAuthGeneration = _auth.sessionGeneration;
    setState(() {
      _authVersion++;
      _activePlaylistId = null;
      if (!_auth.isLoggedIn &&
          (_index == _favoritesIndex || _index == _historyIndex)) {
        _index = _profileIndex;
        _visitedPages.add(_profileIndex);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final index in [_favoritesIndex, _historyIndex, _profileIndex]) {
        _tabKeys[index].currentState?.popToRoot();
      }
    });
  }

  bool get _editingText {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    return focusedContext?.widget is EditableText ||
        focusedContext?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _focusSearch() {
    switchTo(1);
    _tabKeys[1].currentState?.popToRoot();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _index == 1) _searchFocusNode.requestFocus();
    });
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    final source = _settings.source;
    if (source != _lastSource) {
      _lastSource = source;
      setState(() {
        _sourceVersion++;
        _pageCache[0] = null;
        _pageCache[_discoverIndex] = null;
      });
    }
  }

  void switchTo(int index) {
    if (index < 0 || index >= _pageCount) return;
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _index == index) {
        _tabKeys[index].currentState?.focus();
      }
    });
    if (_index == index && _visitedPages.contains(index)) {
      _tabKeys[index].currentState?.popToRoot();
      return;
    }
    setState(() {
      _index = index;
      _visitedPages.add(index);
      // 切换到其他页面时清空活跃歌单ID
      if (index != _profileIndex) {
        _activePlaylistId = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.android &&
        context.select<SettingsController, bool>(
            (settings) => settings.carModeEnabled)) {
      return CarHomeView(onFavorite: _toggleFavorite);
    }
    final windowWidth = MediaQuery.sizeOf(context).width;
    final bottomSystemInset = MediaQuery.paddingOf(context).bottom;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final scheme = Theme.of(context).colorScheme;
    final macOS = Theme.of(context).platform == TargetPlatform.macOS;
    final wide = windowWidth >= GBreakpoints.sidebar;
    final sidebarWidth = (windowWidth * 0.205).clamp(224.0, 264.0);
    final hasCurrentSong =
        context.select<PlayerController, bool>((p) => p.current != null);
    final playerPanelWidth = (windowWidth * 0.30).clamp(360.0, 420.0);
    final dockedPlayerPanel = windowWidth >= GBreakpoints.desktopPlayer &&
        hasCurrentSong &&
        windowWidth - sidebarWidth - playerPanelWidth >= 560;
    final panelVisible = dockedPlayerPanel && _miniPlayerPanel != null;
    final pages = List<Widget>.generate(
      _pageCount,
      (pageIndex) => _visitedPages.contains(pageIndex)
          ? pageIndex == _favoritesIndex || pageIndex == _historyIndex
              ? _buildPage(pageIndex)
              : _pageCache[pageIndex] ??= _buildPage(pageIndex)
          : const SizedBox.shrink(),
    );

    final canPopTab = _tabCanPop[_index];
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyF):
            const _FocusSearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
            const _FocusSearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.space): const _PlayPauseIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft):
            const _SeekBackwardIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight):
            const _SeekForwardIntent(),
        LogicalKeySet(LogicalKeyboardKey.shift, LogicalKeyboardKey.arrowLeft):
            const _SeekBackwardLongIntent(),
        LogicalKeySet(LogicalKeyboardKey.shift, LogicalKeyboardKey.arrowRight):
            const _SeekForwardLongIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowUp): const _VolumeUpIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown): const _VolumeDownIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.arrowRight,
        ): const _NextTrackIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.arrowRight,
        ): const _NextTrackIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.arrowLeft,
        ): const _PreviousTrackIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.arrowLeft,
        ): const _PreviousTrackIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) {
              _focusSearch();
              return null;
            },
          ),
          _PlayPauseIntent: _PlaybackAction<_PlayPauseIntent>(
            enabled: () => !_editingText,
            onInvoke: (_) {
              _player.togglePlay();
              return null;
            },
          ),
          _SeekBackwardIntent: _PlaybackAction<_SeekBackwardIntent>(
            enabled: () => !_editingText,
            onInvoke: (_) {
              final position = _player.position;
              _player.seek(Duration(
                seconds: (position.inSeconds - 5).clamp(0, position.inSeconds),
              ));
              return null;
            },
          ),
          _SeekForwardIntent: _PlaybackAction<_SeekForwardIntent>(
            enabled: () => !_editingText,
            onInvoke: (_) {
              final current = _player.current;
              if (current == null) return null;
              final position = _player.position;
              final duration = Duration(milliseconds: current.durationMs);
              _player.seek(Duration(
                seconds: (position.inSeconds + 5).clamp(0, duration.inSeconds),
              ));
              return null;
            },
          ),
          _SeekBackwardLongIntent: _PlaybackAction<_SeekBackwardLongIntent>(
            enabled: () => !_editingText,
            onInvoke: (_) {
              final position = _player.position;
              _player.seek(Duration(
                seconds: (position.inSeconds - 30).clamp(0, position.inSeconds),
              ));
              return null;
            },
          ),
          _SeekForwardLongIntent: _PlaybackAction<_SeekForwardLongIntent>(
            enabled: () => !_editingText,
            onInvoke: (_) {
              final current = _player.current;
              if (current == null) return null;
              final position = _player.position;
              final duration = Duration(milliseconds: current.durationMs);
              _player.seek(Duration(
                seconds: (position.inSeconds + 30).clamp(0, duration.inSeconds),
              ));
              return null;
            },
          ),
          _VolumeUpIntent: _PlaybackAction<_VolumeUpIntent>(
            enabled: () => !_editingText,
            onInvoke: (_) {
              final volume = _player.volume;
              _player.setVolume((volume + 0.05).clamp(0.0, 1.0));
              return null;
            },
          ),
          _VolumeDownIntent: _PlaybackAction<_VolumeDownIntent>(
            enabled: () => !_editingText,
            onInvoke: (_) {
              final volume = _player.volume;
              _player.setVolume((volume - 0.05).clamp(0.0, 1.0));
              return null;
            },
          ),
          _NextTrackIntent: _PlaybackAction<_NextTrackIntent>(
            enabled: () => !_editingText,
            onInvoke: (_) {
              _player.next();
              return null;
            },
          ),
          _PreviousTrackIntent: _PlaybackAction<_PreviousTrackIntent>(
            enabled: () => !_editingText,
            onInvoke: (_) {
              _player.previous();
              return null;
            },
          ),
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: canPopTab,
          builder: (context, tabCanPop, child) {
            return PopScope<void>(
              canPop: _index == 0,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                if (!tabCanPop && _index != 0) {
                  switchTo(0);
                }
              },
              child: child!,
            );
          },
          child: Scaffold(
            key: const ValueKey('home-shell-scaffold'),
            backgroundColor: scheme.surfaceContainerLowest,
            body: ColoredBox(
              color: scheme.surfaceContainerLowest,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              if (wide)
                                _Sidebar(
                                  width: sidebarWidth,
                                  topInset: macOS ? 48 : 18,
                                  selected: _index,
                                  onSelect: _selectPage,
                                  onOpenPlaylist: _openUserPlaylist,
                                  onSearch: (query) {
                                    setState(() {
                                      _pendingSearchQuery = query;
                                      _pageCache[1] = null;
                                    });
                                    _selectPage(1);
                                  },
                                  searchQuery: _pendingSearchQuery,
                                  activePlaylistId: _activePlaylistId,
                                ),
                              Expanded(
                                child: AnimatedPadding(
                                  duration: PlatformMotion.duration(
                                      context, Motion.normal),
                                  curve: Motion.standard,
                                  padding: EdgeInsets.only(
                                    right: panelVisible ? playerPanelWidth : 0,
                                  ),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: GBreakpoints.contentMax,
                                      ),
                                      child: GWindowControlsSafeRegion(
                                        safe: wide,
                                        child: ValueListenableBuilder<bool>(
                                          valueListenable: canPopTab,
                                          builder:
                                              (context, nestedCanPop, child) {
                                            final dockInset = wide ||
                                                    keyboardOpen
                                                ? 0.0
                                                : nestedCanPop
                                                    ? hasCurrentSong
                                                        ? MiniPlayer
                                                                .mobileHeight(
                                                                    context) +
                                                            20 +
                                                            bottomSystemInset
                                                        : bottomSystemInset
                                                    : 80.0 + bottomSystemInset;
                                            return FloatingDockInsets(
                                              bottom:
                                                  nestedCanPop ? 0 : dockInset,
                                              child: AnimatedPadding(
                                                duration:
                                                    PlatformMotion.duration(
                                                        context, Motion.normal),
                                                curve: Motion.standard,
                                                padding: EdgeInsets.only(
                                                  bottom: nestedCanPop
                                                      ? dockInset
                                                      : 0,
                                                ),
                                                child: MediaQuery.removePadding(
                                                  context: context,
                                                  removeBottom: !wide,
                                                  child: child!,
                                                ),
                                              ),
                                            );
                                          },
                                          child: _AnimatedTabStack(
                                            index: _index,
                                            children: [
                                              for (var i = 0;
                                                  i < pages.length;
                                                  i++)
                                                _TabNavigator(
                                                  key: _tabKeys[i],
                                                  active: _index == i,
                                                  canPopListenable:
                                                      _tabCanPop[i],
                                                  child: pages[i],
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (wide)
                          MiniPlayer(
                            sidebarWidth: sidebarWidth,
                            panel: dockedPlayerPanel ? _miniPlayerPanel : null,
                            onPanelChanged: dockedPlayerPanel
                                ? (panel) =>
                                    setState(() => _miniPlayerPanel = panel)
                                : null,
                          ),
                      ],
                    ),
                  ),
                  if (!wide)
                    ValueListenableBuilder<bool>(
                      valueListenable: canPopTab,
                      builder: (context, tabCanPop, child) {
                        if (keyboardOpen || (tabCanPop && !hasCurrentSong)) {
                          return const SizedBox.shrink();
                        }
                        final horizontalInset = windowWidth < 360 ? 8.0 : 16.0;
                        return Positioned(
                          left: horizontalInset,
                          right: horizontalInset,
                          bottom: bottomSystemInset + 10,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: tabCanPop
                                  ? const MiniPlayer()
                                  : _BottomNav(
                                      selected: _index,
                                      onSelect: _selectPage,
                                      hasCurrentSong: hasCurrentSong,
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  if (dockedPlayerPanel)
                    AnimatedPositioned(
                      duration: PlatformMotion.duration(context, Motion.normal),
                      curve: Motion.standard,
                      top: 0,
                      bottom: MiniPlayer.desktopHeight(context),
                      right:
                          _miniPlayerPanel == null ? -playerPanelWidth - 24 : 0,
                      width: playerPanelWidth,
                      child: IgnorePointer(
                        ignoring: !panelVisible,
                        child: ExcludeFocus(
                          excluding: !panelVisible,
                          child: ExcludeSemantics(
                            excluding: !panelVisible,
                            child: DesktopPlayerPanel(
                              panel: _miniPlayerPanel ?? MiniPlayerPanel.lyrics,
                              onClose: () =>
                                  setState(() => _miniPlayerPanel = null),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (macOS && wide)
                    Positioned(
                      left: 0,
                      width: sidebarWidth,
                      top: 0,
                      child: const _WindowDragBar(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(int pageIndex) {
    switch (pageIndex) {
      case 0:
        return DiscoverView(
          key: ValueKey('home_$_sourceVersion'),
          title: '首页',
        );
      case 1:
        return SearchView(
          key: ValueKey('search_$_pendingSearchQuery'),
          initialQuery: _pendingSearchQuery,
          focusNode: _searchFocusNode,
        );
      case _discoverIndex:
        return PlaylistsView(
          key: ValueKey('discover_$_sourceVersion'),
          title: '发现',
          subtitle: '去听一些还没遇见过的声音',
        );
      case _favoritesIndex:
        return UserLibraryView(
          key: ValueKey('favorites_$_authVersion'),
          title: '喜欢的音乐',
          kind: UserLibraryKind.favorites,
          embedded: true,
          active: _index == _favoritesIndex,
          loader: () => _loadUserSongs(favorites: true),
          onRemove: (song) async {
            final token = _auth.token;
            if (token == null) return;
            await UserApi().removeFavorite(song.id, song.source, token);
          },
        );
      case _historyIndex:
        return UserLibraryView(
          key: ValueKey('history_$_authVersion'),
          title: '播放历史',
          kind: UserLibraryKind.history,
          embedded: true,
          active: _index == _historyIndex,
          loader: () => _loadUserSongs(favorites: false),
          onRemove: (song) async {
            final token = _auth.token;
            final recordId = song.libraryId;
            if (token == null || recordId == null) return;
            await UserApi().deleteHistory(recordId, token);
          },
          onClear: (songs) async {
            final token = _auth.token;
            if (token == null) return;
            for (final song in songs) {
              final recordId = song.libraryId;
              if (recordId != null) {
                await UserApi().deleteHistory(recordId, token);
              }
            }
          },
        );
      case _profileIndex:
        return const ProfileView(
          key: ValueKey('profile'),
          embedded: true,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _selectPage(int index) {
    if (index == _favoritesIndex || index == _historyIndex) {
      final token = context.read<AuthController>().token;
      if (token == null) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginView()),
        );
        return;
      }
    }
    switchTo(index);
  }

  void _openUserPlaylist(Map<String, dynamic> item) {
    final token = _auth.token;
    final id = userPlaylistId(item);
    if (token == null || id == null) return;

    final source = item['source']?.toString().trim();
    final sourceId = item['sourceId']?.toString().trim();
    final canSync = source != null &&
        source.isNotEmpty &&
        source != 'local' &&
        sourceId != null &&
        sourceId.isNotEmpty;
    final page = UserLibraryView(
      title: userPlaylistName(item),
      kind: UserLibraryKind.playlist,
      loader: () async {
        final songs = await UserApi().getUserPlaylistSongs(id, token);
        return songs.map(itemToSong).toList();
      },
      onSync: canSync
          ? () async {
              await UserApi().syncPlaylist(id, token);
            }
          : null,
    );

    switchTo(_profileIndex);
    setState(() => _activePlaylistId = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tabKeys[_profileIndex].currentState?.push(page);
    });
  }

  Future<List<Song>> _loadUserSongs({required bool favorites}) async {
    final token = context.read<AuthController>().token;
    if (token == null) throw StateError('登录状态已失效，请重新登录');
    final items = favorites
        ? await UserApi().getFavorites(token)
        : await UserApi().getHistory(token);
    return items.map(itemToSong).toList();
  }
}

/// 每个栏目保留独立的内容导航栈；二级页不会遮住侧栏和全局播放栏。
class _TabNavigator extends StatefulWidget {
  const _TabNavigator({
    super.key,
    required this.active,
    required this.child,
    required this.canPopListenable,
  });

  final bool active;
  final Widget child;
  final ValueNotifier<bool> canPopListenable;

  @override
  State<_TabNavigator> createState() => _TabNavigatorState();
}

/// Switches tabs while keeping every navigator mounted.
///
/// Keeping the stacks alive is important for mobile: switching tabs must not
/// reset scroll position or a nested detail page. IgnorePointer and
/// ExcludeSemantics ensure only the visible tab participates in interaction.
class _AnimatedTabStack extends StatefulWidget {
  const _AnimatedTabStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_AnimatedTabStack> createState() => _AnimatedTabStackState();
}

class _AnimatedTabStackState extends State<_AnimatedTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// 正在淡出的旧 Tab。过渡期间它必须保持可见，否则会看到闪白。
  int? _outgoing;
  double _direction = 1;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.normal,
      value: 1,
    )..addStatusListener(_onAnimationStatus);
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _outgoing != null) {
      setState(() => _outgoing = null);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _outgoing = null;
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(_AnimatedTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _outgoing = null;
      _controller.value = 1;
      return;
    }
    _direction = widget.index > oldWidget.index ? 1 : -1;
    _outgoing = oldWidget.index;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              // 子树在这里提升，不随动画帧重建；每个 Tab 的 Navigator 状态得以保留。
              child: RepaintBoundary(child: widget.children[i]),
              builder: (context, child) {
                final active = i == widget.index;
                final leaving = i == _outgoing;
                final progress = Motion.standard.transform(_controller.value);
                final opacity = active
                    ? progress
                    : leaving
                        ? 1 - progress
                        : 0.0;
                return Offstage(
                  offstage: !active && !leaving,
                  child: ExcludeSemantics(
                    excluding: !active,
                    child: IgnorePointer(
                      ignoring: !active,
                      child: ExcludeFocus(
                        excluding: !active,
                        child: TickerMode(
                          enabled: active,
                          child: Opacity(
                            opacity: opacity.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(
                                _direction *
                                    22 *
                                    (active ? 1 - progress : -progress),
                                0,
                              ),
                              child: child,
                            ),
                          ),
                        ),
                      ),
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

class _TabNavigatorState extends State<_TabNavigator> {
  late final ValueNotifier<Widget> _rootPage = ValueNotifier(widget.child);

  ValueNotifier<bool> get canPopListenable => widget.canPopListenable;

  void popToRoot() {
    final navigator = _navigatorKey.currentState;
    navigator?.popUntil((route) => route.isFirst);
  }

  void focus() {
    _navigatorKey.currentState?.focusNode.requestFocus();
  }

  void push(Widget page) {
    _navigatorKey.currentState?.push<void>(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void didUpdateWidget(covariant _TabNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.child, widget.child)) {
      _rootPage.value = widget.child;
    }
  }

  @override
  void dispose() {
    _rootPage.dispose();
    super.dispose();
  }

  void _syncCanPop() {
    final value = _navigatorKey.currentState?.canPop() ?? false;
    if (value != canPopListenable.value) canPopListenable.value = value;
  }

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler<void>(
      enabled: widget.active,
      onPopWithResult: (_) {
        _navigatorKey.currentState?.maybePop();
      },
      child: Navigator(
        key: _navigatorKey,
        observers: [_TabNavigatorObserver(_syncCanPop)],
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => ValueListenableBuilder<Widget>(
            valueListenable: _rootPage,
            builder: (_, page, __) => SafeArea(
              bottom: false,
              child: page,
            ),
          ),
        ),
      ),
    );
  }
}

class _TabNavigatorObserver extends NavigatorObserver {
  _TabNavigatorObserver(this.onChanged);

  final VoidCallback onChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged();
  }
}

/// 侧边栏：Logo + 搜索 + 功能导航 + 我的歌单 + 用户信息
class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.width,
    required this.topInset,
    required this.selected,
    required this.onSelect,
    required this.onOpenPlaylist,
    required this.onSearch,
    this.searchQuery,
    this.activePlaylistId,
  });

  final double width;
  final double topInset;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<Map<String, dynamic>> onOpenPlaylist;
  final ValueChanged<String> onSearch;
  final String? searchQuery;
  final String? activePlaylistId;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _userPlaylists = [];
  bool _loadingPlaylists = false;
  String? _loadedToken;
  bool _reloadScheduled = false;
  int _playlistLoadSequence = 0;

  @override
  void initState() {
    super.initState();
    UserPlaylistLibrary.instance.addListener(_onPlaylistLibraryChanged);
  }

  void _onPlaylistLibraryChanged() {
    if (mounted) _loadUserPlaylists();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = context.read<AuthController>().token;
    if (token != _loadedToken && !_reloadScheduled) {
      _loadedToken = token;
      _reloadScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reloadScheduled = false;
        if (mounted) _loadUserPlaylists();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery &&
        widget.searchQuery != null &&
        widget.searchQuery!.isNotEmpty) {
      _searchController.value = TextEditingValue(
        text: widget.searchQuery!,
        selection: TextSelection.collapsed(offset: widget.searchQuery!.length),
      );
    }
  }

  @override
  void dispose() {
    UserPlaylistLibrary.instance.removeListener(_onPlaylistLibraryChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserPlaylists() async {
    final sequence = ++_playlistLoadSequence;
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) {
      setState(() {
        _userPlaylists = [];
        _loadingPlaylists = false;
      });
      return;
    }
    setState(() => _loadingPlaylists = true);
    try {
      final items = await UserApi().getUserPlaylists(token);
      if (mounted && sequence == _playlistLoadSequence) {
        setState(() => _userPlaylists = items);
      }
    } catch (_) {
      if (mounted && sequence == _playlistLoadSequence) {
        setState(() => _userPlaylists = []);
      }
    } finally {
      if (mounted && sequence == _playlistLoadSequence) {
        setState(() => _loadingPlaylists = false);
      }
    }
  }

  Future<void> _openImport() async {
    final auth = context.read<AuthController>();
    if (!auth.isLoggedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginView()),
      );
      return;
    }
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const PlaylistImportView(),
      ),
    );
    if (imported == true && mounted) UserPlaylistLibrary.instance.markChanged();
  }

  void _onCreatePlaylist() {
    final auth = context.read<AuthController>();
    if (!auth.isLoggedIn || auth.token == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginView()),
      );
      return;
    }
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入歌单名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(dialogContext).pop();
              try {
                await UserApi().createPlaylist(name, null, auth.token!);
              } catch (_) {}
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthController>();
    final name = auth.username ?? '用户';
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: dark
            ? scheme.surfaceContainer.withValues(alpha: 0.92)
            : scheme.surfaceContainer.withValues(alpha: 0.96),
        border: Border(right: BorderSide(color: glassHairline(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: widget.topInset),
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: GestureDetector(
              key: const ValueKey('sidebar_search_control'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _searchFocusNode.requestFocus();
                widget.onSelect(1);
              },
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: widget.selected == 1
                        ? scheme.primary
                        : glassHairline(context),
                  ),
                ),
                child: TextField(
                  key: const ValueKey('sidebar_search_field'),
                  focusNode: _searchFocusNode,
                  controller: _searchController,
                  onTap: () => widget.onSelect(1),
                  onSubmitted: (value) {
                    final query = value.trim();
                    if (query.isNotEmpty) widget.onSearch(query);
                  },
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: '搜索音乐',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurface.withValues(alpha: 0.52),
                    ),
                    prefixIcon: Icon(
                      CupertinoIcons.search,
                      size: 18,
                      color: widget.selected == 1
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.58),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints.tightFor(width: 38, height: 40),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.only(right: 10),
                  ),
                ),
              ),
            ),
          ),
          // 功能导航
          _SidebarItem(
            icon: CupertinoIcons.house,
            selectedIcon: CupertinoIcons.house_fill,
            label: '首页',
            selected: widget.selected == 0,
            onTap: () => widget.onSelect(0),
          ),
          _SidebarItem(
            icon: CupertinoIcons.compass,
            selectedIcon: CupertinoIcons.compass_fill,
            label: '发现',
            selected: widget.selected == _HomeShellState._discoverIndex,
            onTap: () => widget.onSelect(_HomeShellState._discoverIndex),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 5),
            child: Text(
              '你的音乐',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: TypeScale.semibold,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          _SidebarItem(
            icon: CupertinoIcons.heart,
            selectedIcon: CupertinoIcons.heart_fill,
            fixedIconColor: AppBrand.favoriteRed,
            label: '喜欢的音乐',
            selected: widget.selected == _HomeShellState._favoritesIndex,
            onTap: () => widget.onSelect(_HomeShellState._favoritesIndex),
          ),
          _SidebarItem(
            icon: CupertinoIcons.clock,
            selectedIcon: CupertinoIcons.clock_fill,
            label: '播放历史',
            selected: widget.selected == _HomeShellState._historyIndex,
            onTap: () => widget.onSelect(_HomeShellState._historyIndex),
          ),
          const SizedBox(height: 14),
          // 我的歌单分组
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 2),
            child: Row(
              children: [
                Text(
                  '歌单',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: TypeScale.semibold,
                    letterSpacing: 0,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                PopupMenuButton<int>(
                  tooltip: '歌单操作',
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      CupertinoIcons.add,
                      size: 19,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  onSelected: (value) {
                    if (value == 0) {
                      _onCreatePlaylist();
                    } else {
                      _openImport();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 0, child: Text('新建歌单')),
                    PopupMenuItem(value: 1, child: Text('导入歌单')),
                  ],
                ),
              ],
            ),
          ),
          // 歌单列表（可滚动区域）
          Expanded(
            child: _buildPlaylistList(context),
          ),
          // 底部用户信息
          _UserFooter(
            loggedIn: auth.isLoggedIn,
            name: name,
            avatarUrl: auth.avatarUrl,
            selected: widget.selected == _HomeShellState._profileIndex,
            onTap: () => widget.onSelect(_HomeShellState._profileIndex),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthController>();
    if (!auth.isLoggedIn) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Text(
          '登录后查看我的歌单',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      );
    }
    if (_loadingPlaylists) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_userPlaylists.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Text(
          '还没有歌单，点 + 新建',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      );
    }
    final owned =
        _userPlaylists.where(UserApi.isOwnedPlaylist).toList(growable: false);
    final favorites = _userPlaylists
        .where(UserApi.isFavoritePlaylist)
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 2),
      children: [
        if (owned.isNotEmpty)
          ...owned.map((item) =>
              _playlistItem(item, activePlaylistId: widget.activePlaylistId)),
        if (favorites.isNotEmpty) ...[
          _playlistSectionTitle('收藏歌单', scheme),
          ...favorites.map((item) =>
              _playlistItem(item, activePlaylistId: widget.activePlaylistId)),
        ],
      ],
    );
  }

  Widget _playlistSectionTitle(String title, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 7, 12, 5),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: TypeScale.semibold,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _playlistItem(Map<String, dynamic> item,
      {required String? activePlaylistId}) {
    final itemId = userPlaylistId(item);
    return _SidebarItem(
      icon: CupertinoIcons.music_note_list,
      selectedIcon: CupertinoIcons.music_note_list,
      label: userPlaylistName(item),
      selected: itemId != null && itemId == activePlaylistId,
      onTap: () => widget.onOpenPlaylist(item),
    );
  }
}

/// 侧边栏底部用户信息区
class _UserFooter extends StatelessWidget {
  const _UserFooter({
    required this.loggedIn,
    required this.name,
    required this.avatarUrl,
    required this.selected,
    required this.onTap,
  });

  final bool loggedIn;
  final String name;
  final String? avatarUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.18
                    : 0.12,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: GPressScale(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              UserAvatar(
                radius: 14,
                name: name,
                showInitial: loggedIn,
                imageUrl: loggedIn ? avatarUrl : null,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: loggedIn
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  loggedIn ? name : '我的',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: TypeScale.semibold,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 侧边栏导航项（图标 + 文字，选中高亮）
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.fixedIconColor,
  });

  final IconData icon;
  final IconData selectedIcon;
  final Color? fixedIconColor;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = fixedIconColor ??
        (selected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.63));
    final textColor =
        selected ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.82);
    return GPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? scheme.primary.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.18
                      : 0.12,
                )
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              selected ? selectedIcon : icon,
              size: 18,
              color: iconColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: selected ? TypeScale.semibold : TypeScale.medium,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A floating icon pill with a separate, persistent now-playing disc.
class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.selected,
    required this.onSelect,
    required this.hasCurrentSong,
  });

  final int selected;
  final ValueChanged<int> onSelect;
  final bool hasCurrentSong;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 330;
        return Row(
          children: [
            Expanded(
              child: FloatingDockSurface(
                surfaceKey: const ValueKey('mobile-bottom-nav-surface'),
                child: SizedBox(
                  height: 60,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedAlign(
                          key: const ValueKey('mobile-nav-glass-selector'),
                          alignment: Alignment(
                            -1 +
                                2 *
                                    _HomeShellState._tabToPageIndex
                                        .indexOf(selected)
                                        .clamp(0,
                                            _HomeShellState._tabs.length - 1) /
                                    (_HomeShellState._tabs.length - 1),
                            0,
                          ),
                          duration: PlatformMotion.duration(
                              context, const Duration(milliseconds: 320)),
                          curve: Curves.easeOutCubic,
                          child: FractionallySizedBox(
                            widthFactor: 1 / _HomeShellState._tabs.length,
                            heightFactor: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white
                                        .withValues(alpha: dark ? .22 : .72),
                                    Colors.white
                                        .withValues(alpha: dark ? .07 : .18),
                                  ],
                                ),
                                border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: dark ? .24 : .65),
                                    width: .8),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: .06),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2))
                                ],
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0;
                                i < _HomeShellState._tabs.length;
                                i++)
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  selected:
                                      _HomeShellState._tabToPageIndex[i] ==
                                          selected,
                                  label: _HomeShellState._tabs[i].label,
                                  onTap: () => onSelect(
                                      _HomeShellState._tabToPageIndex[i]),
                                  child: ExcludeSemantics(
                                    child: Tooltip(
                                      message: _HomeShellState._tabs[i].label,
                                      child: GPressScale(
                                        onTap: () => onSelect(
                                            _HomeShellState._tabToPageIndex[i]),
                                        scale: .90,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        child: SizedBox(
                                          height: 48,
                                          child: Center(
                                            child: AnimatedScale(
                                              scale: _HomeShellState
                                                          ._tabToPageIndex[i] ==
                                                      selected
                                                  ? 1.08
                                                  : 1,
                                              duration:
                                                  PlatformMotion.tabDuration(
                                                      context),
                                              curve: Curves.easeOutCubic,
                                              child: Icon(
                                                _HomeShellState._tabToPageIndex[
                                                            i] ==
                                                        selected
                                                    ? _HomeShellState
                                                        ._tabs[i].selectedIcon
                                                    : _HomeShellState
                                                        ._tabs[i].icon,
                                                size: 22,
                                                color: dark
                                                    ? (_HomeShellState
                                                                    ._tabToPageIndex[
                                                                i] ==
                                                            selected
                                                        ? const Color(
                                                            0xFFEEF6FD)
                                                        : const Color(
                                                            0xFFB5C9D8))
                                                    : const Color(0xFF30495B),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (hasCurrentSong) ...[
              SizedBox(width: compact ? 8 : 10),
              SizedBox.square(
                dimension: compact ? 52 : 60,
                child: const MiniPlayer(collapsed: true),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// macOS 顶部红绿灯预留区：与整体背景同色，可拖动窗口
class _WindowDragBar extends StatelessWidget {
  const _WindowDragBar();

  static const double height = 36;
  static const MethodChannel _channel = MethodChannel('duckmusic/window');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        _channel.invokeMethod(
          'moveBy',
          {'dx': d.delta.dx, 'dy': d.delta.dy},
        );
      },
      child: const SizedBox(height: height, width: double.infinity),
    );
  }
}

/// Disabled playback bindings bubble to Flutter's text-editing shortcuts.
/// Returning null from an enabled action would still consume the key event.
class _PlaybackAction<T extends Intent> extends CallbackAction<T> {
  _PlaybackAction({required this.enabled, required super.onInvoke});

  final bool Function() enabled;

  @override
  bool isEnabled(T intent) => enabled();
}

// 播放控制 Intents
class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _PlayPauseIntent extends Intent {
  const _PlayPauseIntent();
}

class _SeekBackwardIntent extends Intent {
  const _SeekBackwardIntent();
}

class _SeekForwardIntent extends Intent {
  const _SeekForwardIntent();
}

class _SeekBackwardLongIntent extends Intent {
  const _SeekBackwardLongIntent();
}

class _SeekForwardLongIntent extends Intent {
  const _SeekForwardLongIntent();
}

class _VolumeUpIntent extends Intent {
  const _VolumeUpIntent();
}

class _VolumeDownIntent extends Intent {
  const _VolumeDownIntent();
}

class _NextTrackIntent extends Intent {
  const _NextTrackIntent();
}

class _PreviousTrackIntent extends Intent {
  const _PreviousTrackIntent();
}
