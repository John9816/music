import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/user_playlist_library.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/glass.dart';
import '../../widgets/user_avatar.dart';
import '../discover/discover_view.dart';
import '../library/library_view.dart';
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
  static const _favoritesIndex = 4;
  static const _historyIndex = 5;
  static const _profileIndex = 6;
  static const _pageCount = 7;

  int _index = 0;
  String? _pendingSearchQuery;
  int _sourceVersion = 0;
  MiniPlayerPanel? _miniPlayerPanel;
  final Set<int> _visitedPages = {0};
  final List<GlobalKey<_TabNavigatorState>> _tabKeys = List.generate(
    _pageCount,
    (_) => GlobalKey<_TabNavigatorState>(),
  );
  late String _lastSource;
  late final SettingsController _settings;
  late final PlayerController _player;
  late final AuthController _auth;

  static const _tabToPageIndex = [0, 3, 1, 6];

  static const _tabs = [
    (
      label: '首页',
      icon: CupertinoIcons.house,
      selectedIcon: CupertinoIcons.house_fill
    ),
    (
      label: '发现',
      icon: CupertinoIcons.compass,
      selectedIcon: CupertinoIcons.compass_fill,
    ),
    (
      label: '搜索',
      icon: CupertinoIcons.search,
      selectedIcon: CupertinoIcons.search
    ),
    (
      label: '我的',
      icon: CupertinoIcons.person,
      selectedIcon: CupertinoIcons.person_fill,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _settings = context.read<SettingsController>();
    _player = context.read<PlayerController>();
    _auth = context.read<AuthController>();
    _lastSource = _settings.source;
    _player.onSongPlayed = _recordPlayedSong;
    _player.onSongChanged = _syncFavoriteState;
    _player.onMembershipRequired = _openMembershipCenter;
    _settings.addListener(_onSettingsChanged);
  }

  void _recordPlayedSong(Song song) {
    final token = _auth.token;
    if (!_auth.isLoggedIn || token == null) return;
    UserApi().addHistory(song, token).catchError((_) {});
  }

  Future<void> _syncFavoriteState(Song song) async {
    final token = _auth.token;
    if (!_auth.isLoggedIn || token == null) {
      _player.setLiked(false);
      return;
    }
    try {
      final items = await UserApi().getFavorites(token);
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

  void _openMembershipCenter() {
    if (!mounted) return;
    switchTo(_profileIndex);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('播放需要有效会员，请在个人中心输入兑换码'),
        ),
      );
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    if (_player.onSongPlayed == _recordPlayedSong) {
      _player.onSongPlayed = null;
    }
    if (_player.onSongChanged == _syncFavoriteState) {
      _player.onSongChanged = null;
    }
    if (_player.onMembershipRequired == _openMembershipCenter) {
      _player.onMembershipRequired = null;
    }
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    final source = _settings.source;
    if (source != _lastSource) {
      _lastSource = source;
      setState(() => _sourceVersion++);
    }
  }

  void switchTo(int index) {
    if (index < 0 || index >= _pageCount) return;
    if (_index == index && _visitedPages.contains(index)) {
      _tabKeys[index].currentState?.popToRoot();
      return;
    }
    setState(() {
      _index = index;
      _visitedPages.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    final macOS = Theme.of(context).platform == TargetPlatform.macOS;
    final wide = windowWidth >= 640;
    final sidebarWidth = windowWidth >= 900 ? 280.0 : 232.0;
    final dockedPlayerPanel = windowWidth >= 1120 &&
        context.select<PlayerController, bool>((p) => p.current != null);
    final playerPanelWidth = (windowWidth * 0.30).clamp(360.0, 420.0);
    final pages = List<Widget>.generate(
      _pageCount,
      (pageIndex) => _visitedPages.contains(pageIndex)
          ? _buildPage(pageIndex, wide: wide)
          : const SizedBox.shrink(),
    );

    return Scaffold(
      body: Stack(
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
                          topInset: macOS ? 68 : 18,
                          selected: _index,
                          onSelect: _selectPage,
                          onSearch: (query) {
                            setState(() => _pendingSearchQuery = query);
                            _selectPage(1);
                          },
                          searchQuery: _pendingSearchQuery,
                        ),
                      Expanded(
                        child: GWindowControlsSafeRegion(
                          child: SafeArea(
                            top: !macOS,
                            bottom: false,
                            child: Padding(
                              padding: EdgeInsets.zero,
                              child: IndexedStack(
                                index: _index,
                                children: [
                                  for (var i = 0; i < pages.length; i++)
                                    _TabNavigator(
                                      key: _tabKeys[i],
                                      child: pages[i],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                MiniPlayer(
                  sidebarWidth: wide ? sidebarWidth : null,
                  panel: dockedPlayerPanel ? _miniPlayerPanel : null,
                  onPanelChanged: dockedPlayerPanel
                      ? (panel) => setState(() => _miniPlayerPanel = panel)
                      : null,
                ),
              ],
            ),
          ),
          if (dockedPlayerPanel)
            AnimatedPositioned(
              duration: Motion.normal,
              curve: Curves.easeOutCubic,
              top: 0,
              bottom: 80,
              right: _miniPlayerPanel == null ? -playerPanelWidth - 24 : 0,
              width: playerPanelWidth,
              child: IgnorePointer(
                ignoring: _miniPlayerPanel == null,
                child: DesktopPlayerPanel(
                  panel: _miniPlayerPanel ?? MiniPlayerPanel.lyrics,
                  onClose: () => setState(() => _miniPlayerPanel = null),
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
      bottomNavigationBar: wide
          ? null
          : _BottomNav(
              selected: _index,
              onSelect: _selectPage,
            ),
    );
  }

  Widget _buildPage(int pageIndex, {required bool wide}) {
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
        );
      case 2:
        return LibraryView(
          key: ValueKey('library_$_sourceVersion'),
          onOpenFavorites: () => _selectPage(_favoritesIndex),
          onOpenHistory: () => _selectPage(_historyIndex),
        );
      case 3:
        return PlaylistsView(
          key: ValueKey('discover_$_sourceVersion'),
          title: '发现',
          subtitle: '去听一些还没遇见过的声音',
        );
      case _favoritesIndex:
        return UserLibraryView(
          key: const ValueKey('favorites'),
          title: '喜欢的音乐',
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
          key: const ValueKey('history'),
          title: '播放历史',
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
        return ProfileView(
          key: const ValueKey('profile'),
          embedded: true,
          onOpenFavorites: wide ? () => _selectPage(_favoritesIndex) : null,
          onOpenHistory: wide ? () => _selectPage(_historyIndex) : null,
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
  const _TabNavigator({super.key, required this.child});

  final Widget child;

  @override
  State<_TabNavigator> createState() => _TabNavigatorState();
}

class _TabNavigatorState extends State<_TabNavigator> {
  late final ValueNotifier<Widget> _rootPage = ValueNotifier(widget.child);

  void popToRoot() {
    final navigator = _navigatorKey.currentState;
    navigator?.popUntil((route) => route.isFirst);
  }

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void didUpdateWidget(covariant _TabNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rootPage.value = widget.child;
  }

  @override
  void dispose() {
    _rootPage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _navigatorKey,
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => ValueListenableBuilder<Widget>(
          valueListenable: _rootPage,
          builder: (_, page, __) => page,
        ),
      ),
    );
  }
}

/// 侧边栏：Logo + 搜索 + 功能导航 + 我的歌单 + 用户信息
class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.width,
    required this.topInset,
    required this.selected,
    required this.onSelect,
    required this.onSearch,
    this.searchQuery,
  });

  final double width;
  final double topInset;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<String> onSearch;
  final String? searchQuery;

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

  void _openPlaylist(Map<String, dynamic> item) {
    final token = context.read<AuthController>().token;
    final id = userPlaylistId(item);
    if (token == null || id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserLibraryView(
          title: userPlaylistName(item),
          loader: () async {
            final songs = await UserApi().getUserPlaylistSongs(id, token);
            return songs.map(itemToSong).toList();
          },
        ),
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
        color: dark ? null : scheme.surfaceContainer.withValues(alpha: 0.96),
        gradient: dark
            ? const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF242725), Color(0xFF252926)],
              )
            : null,
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
                  color:
                      dark ? const Color(0xFF383B39) : scheme.surfaceContainer,
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
            selected: widget.selected == 3,
            onTap: () => widget.onSelect(3),
          ),
          _SidebarItem(
            icon: CupertinoIcons.music_albums,
            selectedIcon: CupertinoIcons.music_albums_fill,
            label: '资料库',
            selected: widget.selected == 2,
            onTap: () => widget.onSelect(2),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 5),
            child: Text(
              '资料库',
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
                  '我的歌单',
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
        if (owned.isNotEmpty) ...[
          _playlistSectionTitle('我的歌单', scheme),
          ...owned.map(_playlistItem),
        ],
        if (favorites.isNotEmpty) ...[
          _playlistSectionTitle('收藏歌单', scheme),
          ...favorites.map(_playlistItem),
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

  Widget _playlistItem(Map<String, dynamic> item) {
    return _SidebarItem(
      icon: CupertinoIcons.music_note_list,
      selectedIcon: CupertinoIcons.music_note_list,
      label: userPlaylistName(item),
      selected: false,
      onTap: () => _openPlaylist(item),
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
            ? (Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF24482F)
                : AppBrand.red.withValues(alpha: 0.14))
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
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor =
        selected ? AppBrand.red : scheme.onSurface.withValues(alpha: 0.63);
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
              ? (Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF24482F)
                  : AppBrand.red.withValues(alpha: 0.14))
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

/// 窄屏底部导航：资料库已融合到“我的”。
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xF2101012) : const Color(0xF2FFFFFF),
        border: Border(top: BorderSide(color: glassHairline(context))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < _HomeShellState._tabs.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: _HomeShellState._tabToPageIndex[i] == selected,
                    label: _HomeShellState._tabs[i].label,
                    child: GPressScale(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onSelect(_HomeShellState._tabToPageIndex[i]);
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _HomeShellState._tabToPageIndex[i] == selected
                                ? _HomeShellState._tabs[i].selectedIcon
                                : _HomeShellState._tabs[i].icon,
                            size: 23,
                            color:
                                _HomeShellState._tabToPageIndex[i] == selected
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _HomeShellState._tabs[i].label,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.1,
                              fontWeight:
                                  _HomeShellState._tabToPageIndex[i] == selected
                                      ? TypeScale.semibold
                                      : TypeScale.medium,
                              color:
                                  _HomeShellState._tabToPageIndex[i] == selected
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
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
