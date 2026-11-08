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
import '../../core/utils/image_cache_manager.dart';
import '../playlists/playlist_detail_view.dart';
import 'artist_names_link.dart';

/// 搜索类型
enum _SearchType { all, song, artist, album, playlist }

/// 搜索页：综合 / 单曲 / 歌手 / 专辑 / 歌单搜索 + 多源切换 + 分页。
class SearchView extends StatefulWidget {
  const SearchView({super.key, this.api, this.initialQuery, this.focusNode});

  final MusicApi? api;
  final String? initialQuery;

  /// Borrowed from the shell when provided; ownership stays with the caller.
  final FocusNode? focusNode;

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
  int? _retryPage;
  int _requestVersion = 0;
  String? _pageError;
  String _keyword = '';
  _SearchType _type = _SearchType.song;
  bool _initialScopeChosen = false;

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
    _lastSource = _settings.searchSource;
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
    final source = _settings.searchSource;
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
    // 只在显式提交时保存历史
    if (kw.trim().isNotEmpty) {
      unawaited(_saveHistory(kw.trim()));
    }
  }

  void _openArtist(SearchArtist artist) {
    openArtistInfo(
      context,
      artists: [
        Artist(id: 0, name: artist.name, picUrl: artist.coverUrl),
      ],
      artistId: artist.id,
      source: artist.source ?? _settings.searchSource,
      initialTrackCount: artist.trackCount,
    );
  }

  void _openAlbum(SearchAlbum album) {
    final source = album.source ?? _settings.searchSource;
    final numericId = int.tryParse(album.id) ?? album.id.hashCode;
    Navigator.of(context).push(
      buildAppRoute(
        context,
        (_) => PlaylistDetailView(
          kind: PlaylistDetailKind.album,
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

  void _openPlaylist(Playlist playlist) {
    final source = playlist.source ?? _settings.searchSource;
    final resolved = playlist.source != null
        ? playlist
        : Playlist(
            id: playlist.id,
            name: playlist.name,
            source: source,
            coverUrl: playlist.coverUrl,
            description: playlist.description,
            creatorName: playlist.creatorName,
            trackCount: playlist.trackCount,
            playCount: playlist.playCount,
          );
    Navigator.of(context).push(
      buildAppRoute(
        context,
        (_) => PlaylistDetailView(
          playlist: resolved,
          loader: () => _api.getPlaylistDetail(playlist.id, source: source),
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
        _retryPage = null;
      });
      return;
    }
    // 保留旧结果，只设置搜索状态
    setState(() {
      _keyword = keyword;
      _searching = true;
      _page = 1;
      _pageError = null;
      _retryPage = null;
    });
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () {
        if (mounted && keyword.isNotEmpty) {
          _search(keyword, clearResults: true);
          // 移除这里的自动保存历史
        }
      },
    );
  }

  Future<void> _search(
    String keyword, {
    int page = 1,
    bool clearResults = false,
  }) async {
    final requestVersion = ++_requestVersion;
    final type = _type;
    final source = _settings.searchSource;
    setState(() {
      _keyword = keyword;
      _searching = true;
      _pageError = null;
      _retryPage = null;
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
      // The scope belongs to the query. Resizing while loading, retrying or
      // paging must not change which result kinds the user requested.
      if (type == _SearchType.all) {
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

        if (page > _page &&
            playlists.isEmpty &&
            songs.isEmpty &&
            artists.isEmpty &&
            albums.isEmpty) {
          setState(() => _hasNextPage = false);
          return;
        }

        // 预加载封面
        final coverUrls = <String?>[
          ...songs.map((s) => s.album.picUrl),
          ...albums.map((a) => a.coverUrl),
          ...playlists.map((p) => p.coverUrl),
        ];
        ImageCacheManager.preloadCovers(coverUrls, limit: 15);

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
        case _SearchType.all:
          // Combined results were handled above.
          return;
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
      // 移除这里的自动保存历史，只在_submit里保存
    } catch (error) {
      if (_isCurrentRequest(requestVersion, keyword, type, source)) {
        setState(() {
          _pageError = error.toString();
          _retryPage = page;
        });
      }
    } finally {
      if (_isCurrentRequest(requestVersion, keyword, type, source)) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _retrySearch() => _search(
        _keyword,
        page: _retryPage ?? _page,
        clearResults: _currentResultsEmpty,
      );

  /// Switches the provider used by every search result type.
  Widget _buildSourceRow({required bool wide}) {
    final settings = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final entries = AppConfig.musicSources.entries.toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 20, 12, wide ? 24 : 20, 8),
      child: Container(
        height: (MediaQuery.textScalerOf(context).scale(13) * 1.5 + 12)
            .clamp(wide ? 48.0 : 44.0, double.infinity),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: dark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (var i = 0; i < entries.length; i++)
              Expanded(
                child: GPressScale(
                  key: ValueKey('search_source_${entries[i].key}'),
                  onTap: () => settings.setSearchSource(entries[i].key),
                  child: AnimatedContainer(
                    height: double.infinity,
                    duration: Motion.fast,
                    decoration: BoxDecoration(
                      color: settings.searchSource == entries[i].key
                          ? scheme.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: settings.searchSource == entries[i].key
                                ? scheme.primary
                                : scheme.onSurfaceVariant
                                    .withValues(alpha: 0.45),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entries[i].value,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: TypeScale.medium,
                            color: settings.searchSource == entries[i].key
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
      source: _settings.searchSource,
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
      source: _settings.searchSource,
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
      source: _settings.searchSource,
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
      source: _settings.searchSource,
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
        _settings.searchSource == source;
  }

  bool get _currentResultsEmpty {
    return switch (_type) {
      _SearchType.all => _results.isEmpty &&
          _artists.isEmpty &&
          _albums.isEmpty &&
          _playlists.isEmpty,
      _SearchType.song => _results.isEmpty,
      _SearchType.artist => _artists.isEmpty,
      _SearchType.album => _albums.isEmpty,
      _SearchType.playlist => _playlists.isEmpty,
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= GBreakpoints.contentSplit;
        // Choose a useful initial scope once. Every later scope change is an
        // explicit user action, never a side effect of a window resize.
        if (!_initialScopeChosen) {
          _type = wide ? _SearchType.all : _SearchType.song;
          _initialScopeChosen = true;
        }
        return _buildContent(
          context,
          wide: wide,
          scrollHeader: constraints.maxHeight <
              480 * MediaQuery.textScalerOf(context).scale(1),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required bool wide,
    required bool scrollHeader,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final header = <Widget>[
      _contentFrame(
        GPageHeader(
          title: _keyword.isEmpty ? '搜索' : '搜索结果',
          subtitle: wide ? '歌曲、歌手、专辑与歌单' : null,
          padding: EdgeInsets.fromLTRB(
            (MediaQuery.sizeOf(context).width >= 600 ? 24 : 20) +
                macOSWindowControlsInset(context),
            wide ? 22 : 18,
            24,
            wide ? 12 : 10,
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(wide ? 24 : 20, 0, wide ? 24 : 20, 4),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            height: MediaQuery.textScalerOf(context).scale(17) * 1.5 + 22,
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              style: TextStyle(
                fontSize: 15,
                color: scheme.onSurface,
              ),
              cursorColor: scheme.primary,
              decoration: InputDecoration(
                hintText: '搜索音乐',
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: scheme.onSurfaceVariant,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
      _contentFrame(_buildSourceRow(wide: wide)),
      _contentFrame(_buildTypeTabs()),
    ];
    final results = _contentFrame(
      _keyword.isEmpty
          ? _buildHome(shrinkWrap: scrollHeader)
          : _searching && _currentResultsEmpty
              ? Semantics(
                  label: '正在搜索',
                  liveRegion: true,
                  child: scrollHeader
                      ? const GSkeletonList(itemCount: 8)
                      : const SingleChildScrollView(
                          child: GSkeletonList(itemCount: 8),
                        ),
                )
              : _pageError != null && _currentResultsEmpty
                  ? GEmptyState(
                      icon: Icons.error_outline_rounded,
                      text: '搜索失败，请重试',
                      onRetry: _retrySearch,
                    )
                  : _buildResults(shrinkWrap: scrollHeader),
      maxWidth: _keyword.isEmpty ? 1080 : 1320,
      fillHeight: !scrollHeader,
    );
    return Scaffold(
      // Short panes need the entire header to scroll away so that scopes,
      // sources and results remain reachable without shrinking touch targets.
      body: scrollHeader
          ? SingleChildScrollView(
              child: Column(children: [...header, results]),
            )
          : Column(children: [...header, Expanded(child: results)]),
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
      _retryPage = null;
    });
  }

  /// The same explicit scopes remain available on both sides of a breakpoint.
  Widget _buildTypeTabs() {
    const labels = ['综合', '单曲', '歌手', '专辑', '歌单'];
    const types = [
      _SearchType.all,
      _SearchType.song,
      _SearchType.artist,
      _SearchType.album,
      _SearchType.playlist,
    ];
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                selected: _type == types[i],
                child: GPressScale(
                  onTap: () => _switchType(types[i]),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: _type == types[i]
                          ? scheme.onSurface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(RadiusToken.pill),
                    ),
                    child: Text(labels[i],
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: TypeScale.medium,
                          color: _type == types[i]
                              ? scheme.surface
                              : scheme.onSurface,
                        )),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 按类型渲染结果
  Widget _buildResults({bool shrinkWrap = false}) {
    switch (_type) {
      case _SearchType.all:
        return _buildCombinedResults(shrinkWrap: shrinkWrap);
      case _SearchType.song:
        return _results.isEmpty
            ? const GEmptyState(icon: Icons.search_off, text: '没有找到相关歌曲')
            : _withPagination(
                shrinkWrap: shrinkWrap,
                child: ListView.builder(
                  shrinkWrap: shrinkWrap,
                  primary: shrinkWrap ? false : null,
                  physics:
                      shrinkWrap ? const NeverScrollableScrollPhysics() : null,
                  itemCount: _results.length,
                  itemBuilder: (context, i) => RepaintBoundary(
                    child: SongRow(
                      song: _results[i],
                      onTap: () => context
                          .read<PlayerController>()
                          .playQueue(_results, index: i),
                    ),
                  ),
                ),
              );
      case _SearchType.artist:
        return _artists.isEmpty
            ? const GEmptyState(
                icon: Icons.person_search_outlined, text: '没有找到相关歌手')
            : _withPagination(
                shrinkWrap: shrinkWrap,
                child: ListView.builder(
                  shrinkWrap: shrinkWrap,
                  primary: shrinkWrap ? false : null,
                  physics:
                      shrinkWrap ? const NeverScrollableScrollPhysics() : null,
                  itemCount: _artists.length,
                  itemBuilder: (context, i) => RepaintBoundary(
                    child: _ArtistRow(
                      artist: _artists[i],
                      onTap: () => _openArtist(_artists[i]),
                    ),
                  ),
                ),
              );
      case _SearchType.album:
        return _albums.isEmpty
            ? const GEmptyState(
                icon: Icons.album_outlined,
                text: '没有找到相关专辑',
              )
            : _withPagination(
                shrinkWrap: shrinkWrap,
                child: ListView.builder(
                  shrinkWrap: shrinkWrap,
                  primary: shrinkWrap ? false : null,
                  physics:
                      shrinkWrap ? const NeverScrollableScrollPhysics() : null,
                  itemCount: _albums.length,
                  itemBuilder: (context, i) => RepaintBoundary(
                    child: _AlbumRow(
                      album: _albums[i],
                      onTap: () => _openAlbum(_albums[i]),
                    ),
                  ),
                ),
              );
      case _SearchType.playlist:
        return _playlists.isEmpty
            ? const GEmptyState(icon: Icons.queue_music, text: '没有找到相关歌单')
            : _withPagination(
                shrinkWrap: shrinkWrap,
                child: _buildPlaylistGrid(shrinkWrap: shrinkWrap),
              );
    }
  }

  Widget _withPagination({required Widget child, required bool shrinkWrap}) {
    return Column(
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        shrinkWrap ? child : Expanded(child: child),
        _buildPagination(),
      ],
    );
  }

  double _playlistCardHeight(double coverSize) {
    final scaler = MediaQuery.textScalerOf(context);
    // Reserve two title lines and one creator line using the card's type scale.
    return coverSize + 18 + scaler.scale(13) * 2.5 + scaler.scale(11.5) * 1.5;
  }

  Widget _buildPlaylistGrid({bool shrinkWrap = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final width = (constraints.maxWidth - 28).clamp(0.0, double.infinity);
        final columns = ((width + spacing) / (168 + spacing)).ceil();
        final count = columns < 1 ? 1 : columns;
        final coverSize = (width - spacing * (count - 1)) / count;
        return GridView.builder(
          shrinkWrap: shrinkWrap,
          primary: shrinkWrap ? false : null,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: _playlistCardHeight(coverSize),
          ),
          itemCount: _playlists.length,
          itemBuilder: (context, index) {
            final playlist = _playlists[index];
            return PlaylistCard(
              playlist: playlist,
              onTap: () => _openPlaylist(playlist),
            );
          },
        );
      },
    );
  }

  Widget _buildCombinedResults({bool shrinkWrap = false}) {
    final compact =
        MediaQuery.sizeOf(context).width < GBreakpoints.contentSplit;
    final sections = <Widget>[];
    if (_playlists.isNotEmpty) {
      sections.add(_SearchSection(
        title: '歌单',
        child: SizedBox(
          height: _playlistCardHeight(148).clamp(218.0, double.infinity),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _playlists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final playlist = _playlists[index];
              return SizedBox(
                width: 148,
                child: PlaylistCard(
                  playlist: playlist,
                  onTap: () => _openPlaylist(playlist),
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
        child: compact
            ? Column(children: [
                for (final artist in _artists)
                  _ArtistRow(artist: artist, onTap: () => _openArtist(artist)),
              ])
            : SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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
        child: compact
            ? Column(children: [
                for (final album in _albums)
                  _AlbumRow(album: album, onTap: () => _openAlbum(album)),
              ])
            : SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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
          padding: EdgeInsets.zero,
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
      shrinkWrap: shrinkWrap,
      primary: shrinkWrap ? false : null,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ...sections,
        _buildPagination(),
      ],
    );
  }

  Widget _buildPagination() {
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pageError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '第 $_retryPage 页加载失败，仍显示第 $_page 页，请重试',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          _buildPaginationControls(
            compact: constraints.maxWidth < GBreakpoints.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls({required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    final canGoBack = !_searching && _page > 1;
    if (compact) {
      final canGoNext = !_searching && (_pageError != null || _hasNextPage);
      return SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  GIconButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: '上一页',
                    size: 24,
                    padding: 12,
                    backgroundColor: Colors.transparent,
                    disabled: !canGoBack,
                    onTap: canGoBack
                        ? () => _search(_keyword, page: _page - 1)
                        : null,
                  ),
                  Expanded(
                    child: _searching
                        ? Center(
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.primary,
                                semanticsLabel: '正在加载搜索结果',
                              ),
                            ),
                          )
                        : Text(
                            '第 $_page 页',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: _pageError == null
                                  ? scheme.onSurfaceVariant
                                  : scheme.error,
                            ),
                          ),
                  ),
                  GIconButton(
                    icon: _pageError == null
                        ? Icons.chevron_right_rounded
                        : Icons.refresh_rounded,
                    tooltip: _pageError == null ? '下一页' : '重试第 $_retryPage 页',
                    size: 24,
                    padding: 12,
                    backgroundColor: Colors.transparent,
                    disabled: !canGoNext,
                    onTap: !canGoNext
                        ? null
                        : _pageError != null
                            ? _retrySearch
                            : () => _search(_keyword, page: _page + 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
                          semanticsLabel: '正在加载搜索结果',
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
              tooltip: _pageError == null ? '下一页' : '重试第 $_retryPage 页',
              size: 20,
              padding: 7,
              disabled: _searching || (!_hasNextPage && _pageError == null),
              onTap: _searching
                  ? null
                  : _pageError != null
                      ? _retrySearch
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
  Widget _buildHome({bool shrinkWrap = false}) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      shrinkWrap: shrinkWrap,
      primary: shrinkWrap ? false : null,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Text('热门搜索',
              style: TextStyle(
                  fontSize: TypeScale.section, fontWeight: TypeScale.semibold)),
        ),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720 ? 4 : 2;
          final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          final height =
              68 + (MediaQuery.textScalerOf(context).scale(16) - 16) * 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < _hotKeywords.length; i++)
                SizedBox(
                  width: width,
                  height: height,
                  child: _HotSearchCard(
                    label: _hotKeywords[i],
                    index: i,
                    onTap: () => _submit(_hotKeywords[i]),
                  ),
                ),
            ],
          );
        }),
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
              fontWeight: TypeScale.semibold,
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
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      onTap: onTap,
      leading: ClipOval(
        child: AsyncCover(url: artist.coverUrl, size: 48, radius: 24),
      ),
      title: Text(artist.name,
          style: const TextStyle(fontSize: 16, fontWeight: TypeScale.regular)),
      subtitle: Text(
        artist.trackCount != null ? '${artist.trackCount} 首歌曲' : '查看歌手',
        style: const TextStyle(fontSize: 14),
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
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      onTap: onTap,
      leading: AsyncCover(url: album.coverUrl, size: 48, radius: 8),
      title: Text(album.name,
          style: const TextStyle(fontSize: 16, fontWeight: TypeScale.regular)),
      subtitle: Text(details.isEmpty ? '查看专辑' : details.join(' · '),
          style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, size: 18),
    );
  }
}

/// 关键词胶囊按钮（搜索历史 / 热门搜索）
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RadiusToken.pill),
          color: Theme.of(context).brightness == Brightness.dark
              ? scheme.surfaceContainer
              : scheme.surfaceContainerLow,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _HotSearchCard extends StatelessWidget {
  const _HotSearchCard(
      {required this.label, required this.index, required this.onTap});

  final String label;
  final int index;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: GPressScale(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: scheme.surfaceContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: TypeScale.medium,
                          color: scheme.onSurface)),
                ),
                const SizedBox(width: 6),
                Icon(Icons.north_west_rounded,
                    size: 15,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.65)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
