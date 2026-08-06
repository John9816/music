import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/music_api.dart';
import '../../core/config/app_config.dart';
import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/song_row.dart';
import '../playlists/playlist_detail_view.dart';
import 'artist_names_link.dart';

/// 搜索类型
enum _SearchType { song, artist, album, playlist }

/// 搜索页：单曲 / 歌手 / 专辑 / 歌单分类搜索 + 多源切换 + 分页。
class SearchView extends StatefulWidget {
  const SearchView({super.key, this.api, this.initialQuery});

  final MusicApi? api;
  final String? initialQuery;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  late final MusicApi _api;
  late final SettingsController _settings;
  late String _lastSource;
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Song> _results = [];
  List<SearchArtist> _artists = [];
  List<SearchAlbum> _albums = [];
  List<Playlist> _playlists = [];
  bool _searching = false;
  bool _hasNextPage = false;
  int _page = 1;
  int _requestVersion = 0;
  String? _pageError;
  String _keyword = '';
  _SearchType _type = _SearchType.song;

  static const _historyKey = 'search_history';
  static const _maxHistory = 10;
  static const _pageSize = 30;
  List<String> _history = [];

  static const _hotKeywords = [
    '周杰伦',
    '邓紫棋',
    '陈奕迅',
    '林俊杰',
    '五月天',
    '纯音乐',
    '抖音',
    '经典老歌',
    '说唱',
    '轻音乐',
  ];

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? MusicApi();
    _settings = context.read<SettingsController>();
    _lastSource = _settings.source;
    _settings.addListener(_onSourceChanged);
    final initialQuery = widget.initialQuery?.trim() ?? '';
    if (initialQuery.isNotEmpty) {
      _controller.text = initialQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search(initialQuery, clearResults: true);
      });
    }
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey);
    if (list != null && mounted) {
      setState(() => _history = list);
    }
  }

  Future<void> _saveHistory(String kw) async {
    final prefs = await SharedPreferences.getInstance();
    // 去重、置顶、截断
    _history =
        [kw, ..._history.where((e) => e != kw)].take(_maxHistory).toList();
    await prefs.setStringList(_historyKey, _history);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    if (mounted) setState(() => _history = []);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSourceChanged);
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSourceChanged() {
    final source = _settings.source;
    if (source == _lastSource) return;
    _lastSource = source;
    if (mounted && _keyword.isNotEmpty) {
      _search(_keyword, clearResults: true);
    }
  }

  void _submit(String kw) {
    _controller.text = kw;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: kw.length),
    );
    _debounce?.cancel();
    _search(kw, clearResults: true);
  }

  void _openArtist(SearchArtist artist) {
    openArtistInfo(
      context,
      artists: [
        Artist(id: 0, name: artist.name, picUrl: artist.coverUrl),
      ],
      artistId: artist.id,
      source: artist.source ?? context.read<SettingsController>().source,
      initialTrackCount: artist.trackCount,
    );
  }

  void _openAlbum(SearchAlbum album) {
    final source = album.source ?? context.read<SettingsController>().source;
    final numericId = int.tryParse(album.id) ?? album.id.hashCode;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailView(
          playlist: Playlist(
            id: numericId,
            name: album.name,
            source: source,
            coverUrl: album.coverUrl,
            creatorName: album.artist,
            trackCount: album.trackCount,
          ),
          loader: () => _api.getAlbumDetail(album.id, source: source),
        ),
      ),
    );
  }

  void _switchType(_SearchType type) {
    if (type == _type) return;
    setState(() => _type = type);
    if (_keyword.isNotEmpty) _search(_keyword, clearResults: true);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _requestVersion++;
    final keyword = value.trim();
    if (keyword.isEmpty) {
      setState(() {
        _keyword = '';
        _results = [];
        _artists = [];
        _albums = [];
        _playlists = [];
        _searching = false;
        _page = 1;
        _hasNextPage = false;
        _pageError = null;
      });
      return;
    }
    setState(() {
      _keyword = keyword;
      _searching = true;
      _results = [];
      _artists = [];
      _albums = [];
      _playlists = [];
      _page = 1;
      _hasNextPage = false;
      _pageError = null;
    });
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(keyword, clearResults: true),
    );
  }

  Future<void> _search(
    String keyword, {
    int page = 1,
    bool clearResults = false,
  }) async {
    final requestVersion = ++_requestVersion;
    final type = _type;
    final source = context.read<SettingsController>().source;
    setState(() {
      _keyword = keyword;
      _searching = true;
      _pageError = null;
      if (clearResults) {
        _results = [];
        _artists = [];
        _albums = [];
        _playlists = [];
        _page = 1;
        _hasNextPage = false;
      }
    });
    try {
      // Desktop search mirrors the reference layout: one query exposes every
      // supported result kind, while the compact layout keeps type tabs.
      if (MediaQuery.sizeOf(context).width >= 720) {
        final values = await Future.wait<dynamic>([
          _searchPlaylistsAll(
            keyword,
            offset: (page - 1) * _pageSize,
            limit: _pageSize,
          ),
          _searchSongsAll(
            keyword,
            offset: (page - 1) * _pageSize,
            limit: _pageSize,
          ),
          _searchArtistsAll(
            keyword,
            offset: (page - 1) * _pageSize,
            limit: _pageSize,
          ),
          _searchAlbumsAll(
            keyword,
            offset: (page - 1) * _pageSize,
            limit: _pageSize,
          ),
        ]);
        if (!_isCurrentRequest(requestVersion, keyword, type, source)) {
          return;
        }
        final playlists = values[0] as List<Playlist>;
        final songs = values[1] as List<Song>;
        final artists = values[2] as List<SearchArtist>;
        final albums = values[3] as List<SearchAlbum>;
        setState(() {
          _playlists = playlists;
          _results = songs;
          _artists = artists;
          _albums = albums;
          _page = page;
          _hasNextPage = playlists.length >= _pageSize ||
              songs.length >= _pageSize ||
              artists.length >= _pageSize ||
              albums.length >= _pageSize;
        });
        unawaited(_saveHistory(keyword));
        return;
      }
      switch (type) {
        case _SearchType.song:
          final list = await _searchSongsAll(
            keyword,
            offset: (page - 1) * _pageSize,
            limit: _pageSize,
          );
          if (!_isCurrentRequest(requestVersion, keyword, type, source)) {
            return;
          }
          if (page > 1 && list.isEmpty) {
            setState(() => _hasNextPage = false);
            return;
          }
          setState(() {
            _results = list;
            _page = page;
            _hasNextPage = list.length >= _pageSize;
          });
        case _SearchType.artist:
          final list = await _searchArtistsAll(
            keyword,
            offset: (page - 1) * _pageSize,
            limit: _pageSize,
          );
          if (!_isCurrentRequest(requestVersion, keyword, type, source)) {
            return;
          }
          if (page > 1 && list.isEmpty) {
            setState(() => _hasNextPage = false);
            return;
          }
          setState(() {
            _artists = list;
            _page = page;
            _hasNextPage = list.length >= _pageSize;
          });
        case _SearchType.album:
          final list = await _searchAlbumsAll(
            keyword,
            offset: (page - 1) * _pageSize,
            limit: _pageSize,
          );
          if (!_isCurrentRequest(requestVersion, keyword, type, source)) {
            return;
          }
          if (page > 1 && list.isEmpty) {
            setState(() => _hasNextPage = false);
            return;
          }
          setState(() {
            _albums = list;
            _page = page;
            _hasNextPage = list.length >= _pageSize;
          });
        case _SearchType.playlist:
          final list = await _searchPlaylistsAll(
            keyword,
            offset: (page - 1) * _pageSize,
            limit: _pageSize,
          );
          if (!_isCurrentRequest(requestVersion, keyword, type, source)) {
            return;
          }
          if (page > 1 && list.isEmpty) {
            setState(() => _hasNextPage = false);
            return;
          }
          setState(() {
            _playlists = list;
            _page = page;
            _hasNextPage = list.length >= _pageSize;
          });
      }
      unawaited(_saveHistory(keyword));
    } catch (error) {
      if (_isCurrentRequest(requestVersion, keyword, type, source)) {
        setState(() => _pageError = error.toString());
      }
    } finally {
      if (_isCurrentRequest(requestVersion, keyword, type, source)) {
        setState(() => _searching = false);
      }
    }
  }

  /// Switches the provider used by every search result type.
  Widget _buildSourceRow() {
    final settings = context.watch<SettingsController>();
    final desktop = MediaQuery.sizeOf(context).width >= 720;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final entries = AppConfig.musicSources.entries.toList();
    const colors = [Color(0xFFFF375F), Color(0xFF2FD365), Color(0xFFFF9F0A)];
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, desktop ? 14 : 8),
      child: Container(
        height: desktop ? 48 : 44,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: dark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: glassHairline(context)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < entries.length; i++)
              Expanded(
                child: GPressScale(
                  key: ValueKey('search_source_${entries[i].key}'),
                  onTap: () => settings.setSource(entries[i].key),
                  child: AnimatedContainer(
                    height: double.infinity,
                    duration: Motion.fast,
                    decoration: BoxDecoration(
                      color: settings.source == entries[i].key
                          ? scheme.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: settings.source == entries[i].key
                          ? Border.all(color: glassHairline(context))
                          : null,
                      boxShadow: settings.source == entries[i].key && !dark
                          ? ShadowToken.card(context, radius: 8, opacity: 0.10)
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors[i],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entries[i].value,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: TypeScale.semibold,
                            color: settings.source == entries[i].key
                                ? scheme.onSurface
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
    );
  }

  Future<List<Song>> _searchSongsAll(
    String keyword, {
    required int offset,
    required int limit,
  }) async {
    return _api.searchSongs(
      keyword,
      source: context.read<SettingsController>().source,
      offset: offset,
      limit: limit,
    );
  }

  Future<List<Playlist>> _searchPlaylistsAll(
    String keyword, {
    required int offset,
    required int limit,
  }) async {
    return _api.searchPlaylists(
      keyword,
      source: context.read<SettingsController>().source,
      offset: offset,
      limit: limit,
    );
  }

  Future<List<SearchArtist>> _searchArtistsAll(
    String keyword, {
    required int offset,
    required int limit,
  }) async {
    return _api.searchArtists(
      keyword,
      source: context.read<SettingsController>().source,
      offset: offset,
      limit: limit,
    );
  }

  Future<List<SearchAlbum>> _searchAlbumsAll(
    String keyword, {
    required int offset,
    required int limit,
  }) async {
    return _api.searchAlbums(
      keyword,
      source: context.read<SettingsController>().source,
      offset: offset,
      limit: limit,
    );
  }

  bool _isCurrentRequest(
    int requestVersion,
    String keyword,
    _SearchType type,
    String source,
  ) {
    if (!mounted || requestVersion != _requestVersion) return false;
    return _keyword == keyword &&
        _type == type &&
        context.read<SettingsController>().source == source;
  }

  bool get _currentResultsEmpty {
    if (MediaQuery.sizeOf(context).width >= 720) {
      return _results.isEmpty &&
          _artists.isEmpty &&
          _albums.isEmpty &&
          _playlists.isEmpty;
    }
    return switch (_type) {
      _SearchType.song => _results.isEmpty,
      _SearchType.artist => _artists.isEmpty,
      _SearchType.album => _albums.isEmpty,
      _SearchType.playlist => _playlists.isEmpty,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final desktop = MediaQuery.sizeOf(context).width >= 720;
    final light = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      backgroundColor: light ? scheme.surface : scheme.surfaceContainerLowest,
      body: Column(
        children: [
          _contentFrame(
            GPageHeader(
              title: _keyword.isEmpty ? '搜索' : '搜索结果',
              subtitle: '歌曲、歌手、专辑与歌单',
              padding: EdgeInsets.fromLTRB(
                24,
                desktop ? 22 : 18,
                24,
                desktop ? 12 : 10,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: GSurface(
              radius: RadiusToken.md,
              alpha: 0.08,
              child: SizedBox(
                height: 46,
                child: TextField(
                  controller: _controller,
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                  cursorColor: scheme.primary,
                  decoration: InputDecoration(
                    hintText: '输入歌曲、歌手、专辑或歌单名称',
                    hintStyle: TextStyle(
                      fontSize: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    border: InputBorder.none,
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    prefixIconConstraints:
                        const BoxConstraints.tightFor(width: 46, height: 46),
                    suffixIcon: _keyword.isEmpty
                        ? null
                        : SizedBox(
                            width: 46,
                            height: 46,
                            child: GIconButton(
                              icon: Icons.cancel_rounded,
                              tooltip: '清除搜索',
                              size: 18,
                              padding: 8,
                              backgroundColor: Colors.transparent,
                              onTap: _clearSearch,
                            ),
                          ),
                    suffixIconConstraints:
                        const BoxConstraints.tightFor(width: 46, height: 46),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) {
                    final trimmed = value.trim();
                    if (trimmed.isNotEmpty) _submit(trimmed);
                  },
                  onChanged: _onChanged,
                ),
              ),
            ),
          ),
          if (!desktop) _buildTypeTabs(),
          _contentFrame(_buildSourceRow()),
          Expanded(
            child: _contentFrame(
              _keyword.isEmpty
                  ? _buildHome()
                  : _searching && _currentResultsEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _pageError != null && _currentResultsEmpty
                          ? GEmptyState(
                              icon: Icons.error_outline_rounded,
                              text: '搜索失败，请重试',
                              onRetry: () => _search(
                                _keyword,
                                page: _page,
                                clearResults: _page == 1,
                              ),
                            )
                          : _buildResults(),
              maxWidth: _keyword.isEmpty ? 1080 : 1320,
              fillHeight: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentFrame(
    Widget child, {
    double maxWidth = 1320,
    bool fillHeight = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, maxWidth).toDouble();
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: fillHeight ? constraints.maxHeight : null,
            child: child,
          ),
        );
      },
    );
  }

  void _clearSearch() {
    _debounce?.cancel();
    _requestVersion++;
    _controller.clear();
    setState(() {
      _keyword = '';
      _results = [];
      _artists = [];
      _albums = [];
      _playlists = [];
      _searching = false;
      _page = 1;
      _hasNextPage = false;
      _pageError = null;
    });
  }

  /// 类型切换：单曲 / 歌手 / 专辑 / 歌单
  Widget _buildTypeTabs() {
    const labels = ['单曲', '歌手', '专辑', '歌单'];
    const types = [
      _SearchType.song,
      _SearchType.artist,
      _SearchType.album,
      _SearchType.playlist,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GSegmented(
          items: labels,
          selected: types.indexOf(_type),
          onSelected: (i) => _switchType(types[i]),
        ),
      ),
    );
  }

  /// 按类型渲染结果
  Widget _buildResults() {
    if (MediaQuery.sizeOf(context).width >= 720) {
      return _buildDesktopResults();
    }
    switch (_type) {
      case _SearchType.song:
        return _results.isEmpty
            ? const GEmptyState(icon: Icons.search_off, text: '没有找到相关歌曲')
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) => SongRow(
                        song: _results[i],
                        onTap: () => context
                            .read<PlayerController>()
                            .playQueue(_results, index: i),
                      ),
                    ),
                  ),
                  _buildPagination(),
                ],
              );
      case _SearchType.artist:
        return _artists.isEmpty
            ? const GEmptyState(
                icon: Icons.person_search_outlined, text: '没有找到相关歌手')
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _artists.length,
                      itemBuilder: (context, i) => _ArtistRow(
                        artist: _artists[i],
                        onTap: () => _openArtist(_artists[i]),
                      ),
                    ),
                  ),
                  _buildPagination(),
                ],
              );
      case _SearchType.album:
        return _albums.isEmpty
            ? const GEmptyState(
                icon: Icons.album_outlined,
                text: '没有找到相关专辑',
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _albums.length,
                      itemBuilder: (context, i) => _AlbumRow(
                        album: _albums[i],
                        onTap: () => _openAlbum(_albums[i]),
                      ),
                    ),
                  ),
                  _buildPagination(),
                ],
              );
      case _SearchType.playlist:
        return _playlists.isEmpty
            ? const GEmptyState(icon: Icons.queue_music, text: '没有找到相关歌单')
            : Column(
                children: [
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 168,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: MediaQuery.sizeOf(context).width < 600
                            ? 0.65
                            : 0.78,
                      ),
                      itemCount: _playlists.length,
                      itemBuilder: (context, i) {
                        final p = _playlists[i];
                        return PlaylistCard(
                          playlist: p,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlaylistDetailView(
                                playlist: p,
                                loader: () => _api.getPlaylistDetail(
                                  p.id,
                                  source: p.source ??
                                      context.read<SettingsController>().source,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  _buildPagination(),
                ],
              );
    }
  }

  Widget _buildDesktopResults() {
    final sections = <Widget>[];
    if (_playlists.isNotEmpty) {
      sections.add(_SearchSection(
        title: '歌单',
        child: SizedBox(
          height: 218,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _playlists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final playlist = _playlists[index];
              return SizedBox(
                width: 148,
                child: PlaylistCard(
                  playlist: playlist,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailView(
                        playlist: playlist,
                        loader: () => _api.getPlaylistDetail(
                          playlist.id,
                          source: playlist.source ??
                              context.read<SettingsController>().source,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ));
    }
    if (_artists.isNotEmpty) {
      sections.add(_SearchSection(
        title: '歌手',
        child: SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _artists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 18),
            itemBuilder: (_, index) {
              final artist = _artists[index];
              return _DesktopArtistCard(
                artist: artist,
                onTap: () => _openArtist(artist),
              );
            },
          ),
        ),
      ));
    }
    if (_albums.isNotEmpty) {
      sections.add(_SearchSection(
        title: '专辑',
        child: SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _albums.length,
            separatorBuilder: (_, __) => const SizedBox(width: 18),
            itemBuilder: (_, index) {
              final album = _albums[index];
              return _DesktopAlbumCard(
                album: album,
                onTap: () => _openAlbum(album),
              );
            },
          ),
        ),
      ));
    }
    if (_results.isNotEmpty) {
      sections.add(_SearchSection(
        title: '歌曲',
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _results.length,
          itemBuilder: (context, index) => SongRow(
            song: _results[index],
            onTap: () => context
                .read<PlayerController>()
                .playQueue(_results, index: index),
          ),
        ),
      ));
    }
    if (sections.isEmpty) {
      return const GEmptyState(icon: Icons.search_off, text: '没有找到相关内容');
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ...sections,
        _buildPagination(),
      ],
    );
  }

  Widget _buildPagination() {
    final scheme = Theme.of(context).colorScheme;
    final canGoBack = !_searching && _page > 1;
    return SafeArea(
      top: false,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: glassHairline(context))),
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GIconButton(
              icon: Icons.chevron_left_rounded,
              tooltip: '上一页',
              size: 20,
              padding: 7,
              disabled: !canGoBack,
              onTap:
                  canGoBack ? () => _search(_keyword, page: _page - 1) : null,
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 84,
              child: _searching
                  ? Center(
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      ),
                    )
                  : Text(
                      '第 $_page 页',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: TypeScale.semibold,
                        color: _pageError == null
                            ? scheme.onSurface
                            : scheme.error,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            GIconButton(
              icon: Icons.chevron_right_rounded,
              tooltip: _pageError == null ? '下一页' : '重试当前页',
              size: 20,
              padding: 7,
              disabled: _searching || (!_hasNextPage && _pageError == null),
              onTap: _searching
                  ? null
                  : _pageError != null
                      ? () => _search(_keyword, page: _page)
                      : _hasNextPage
                          ? () => _search(_keyword, page: _page + 1)
                          : null,
            ),
          ],
        ),
      ),
    );
  }

  /// 搜索首页：搜索历史 + 热门搜索
  Widget _buildHome() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        if (_history.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.history_rounded,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '搜索历史',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                GPressScale(
                  onTap: _clearHistory,
                  child: Text(
                    '清空',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _history
                .map((kw) => _Chip(label: kw, onTap: () => _submit(kw)))
                .toList(),
          ),
          const SizedBox(height: 24),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(Icons.trending_up_rounded,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '热门搜索',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _hotKeywords
              .map(
                  (kw) => _Chip(label: kw, onTap: () => _submit(kw), hot: true))
              .toList(),
        ),
      ],
    );
  }
}

class _SearchSection extends StatelessWidget {
  const _SearchSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        child,
        const SizedBox(height: 16),
      ],
    );
  }
}

class _DesktopArtistCard extends StatelessWidget {
  const _DesktopArtistCard({required this.artist, required this.onTap});

  final SearchArtist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GPressScale(
      onTap: onTap,
      child: SizedBox(
        width: 210,
        child: Row(
          children: [
            ClipOval(
                child: AsyncCover(url: artist.coverUrl, size: 58, radius: 29)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${artist.trackCount ?? 0} 首歌曲',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopAlbumCard extends StatelessWidget {
  const _DesktopAlbumCard({required this.album, required this.onTap});

  final SearchAlbum album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GPressScale(
      onTap: onTap,
      child: SizedBox(
        width: 240,
        child: Row(
          children: [
            AsyncCover(url: album.coverUrl, size: 58, radius: 9),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(album.artist ?? '查看专辑',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌手结果行：圆形头像 + 名字 + 歌曲数
class _ArtistRow extends StatelessWidget {
  const _ArtistRow({required this.artist, required this.onTap});

  final SearchArtist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GListTile(
      onTap: onTap,
      leading: ClipOval(
        child: AsyncCover(url: artist.coverUrl, size: 46, radius: 23),
      ),
      title: Text(artist.name),
      subtitle: Text(
        artist.trackCount != null ? '${artist.trackCount} 首歌曲' : '查看歌手',
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
    );
  }
}

/// 专辑结果行：方形封面 + 专辑名 + 歌手/歌曲数
class _AlbumRow extends StatelessWidget {
  const _AlbumRow({required this.album, required this.onTap});

  final SearchAlbum album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (album.artist != null) album.artist!,
      if (album.trackCount != null) '${album.trackCount} 首歌曲',
    ];
    return GListTile(
      onTap: onTap,
      leading: AsyncCover(url: album.coverUrl, size: 46, radius: 8),
      title: Text(album.name),
      subtitle: Text(details.isEmpty ? '查看专辑' : details.join(' · ')),
      trailing: const Icon(Icons.chevron_right, size: 18),
    );
  }
}

/// 关键词胶囊按钮（搜索历史 / 热门搜索）
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.onTap,
    this.hot = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).brightness == Brightness.dark
              ? scheme.surfaceContainer
              : scheme.surfaceContainerLow,
          border: Border.all(
            color: glassHairline(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: hot ? FontWeight.w600 : FontWeight.w500,
            color: hot ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
