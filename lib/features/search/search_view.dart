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

/// 搜索页：综合 / 单曲 / 歌手 / 专辑 / 歌单搜索 + 多源切换 + 连续加载。
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
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  List<Song> _results = [];
  List<SearchArtist> _artists = [];
  List<SearchAlbum> _albums = [];
  List<Playlist> _playlists = [];
  final List<_SearchBatch> _combinedBatches = [];
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
    _scrollController.addListener(_loadMoreNearBottom);
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
    _scrollController.dispose();
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
        _combinedBatches.clear();
        _searching = false;
        _page = 1;
        _hasNextPage = false;
        _pageError = null;
        _retryPage = null;
      });
      return;
    }
    setState(() {
      _keyword = keyword;
      _results = [];
      _artists = [];
      _albums = [];
      _playlists = [];
      _combinedBatches.clear();
      _hasNextPage = false;
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
    _debounce?.cancel();
    if (page > 1 && _searching) return;
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
        _combinedBatches.clear();
        _page = 1;
        _hasNextPage = false;
      }
    });
    if (clearResults) _resetScroll();
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
          if (page == 1) _combinedBatches.clear();
          _combinedBatches.add(_SearchBatch(
            playlists: playlists,
            songs: songs,
            artists: artists,
            albums: albums,
            songOffset: page == 1 ? 0 : _results.length,
          ));
          _playlists = page == 1 ? playlists : [..._playlists, ...playlists];
          _results = page == 1 ? songs : [..._results, ...songs];
          _artists = page == 1 ? artists : [..._artists, ...artists];
          _albums = page == 1 ? albums : [..._albums, ...albums];
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
            _results = page == 1 ? list : [..._results, ...list];
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
            _artists = page == 1 ? list : [..._artists, ...list];
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
            _albums = page == 1 ? list : [..._albums, ...list];
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
            _playlists = page == 1 ? list : [..._playlists, ...list];
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _scrollController.hasClients &&
              _scrollController.position.pixels > 0) {
            _loadMoreNearBottom();
          }
        });
      }
    }
  }

  Future<void> _retrySearch() => _search(
        _keyword,
        page: _retryPage ?? _page,
        clearResults: _currentResultsEmpty,
      );

  void _resetScroll() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _loadMoreNearBottom() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter <= 240) {
      _loadNextPage();
    }
  }

  void _loadNextPage() {
    if (_searching || !_hasNextPage || _pageError != null || _keyword.isEmpty) {
      return;
    }
    unawaited(_search(_keyword, page: _page + 1));
  }

  Widget _buildSourcePicker({required bool showLabel}) {
    final settings = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final label =
        AppConfig.musicSources[settings.searchSource] ?? settings.searchSource;
    return PopupMenuButton<String>(
      key: const ValueKey('search-source-picker'),
      tooltip: '搜索音源：$label',
      initialValue: settings.searchSource,
      onSelected: settings.setSearchSource,
      itemBuilder: (_) => [
        for (final entry in AppConfig.musicSources.entries)
          PopupMenuItem<String>(
            key: ValueKey('search_source_${entry.key}'),
            value: entry.key,
            height: 48,
            child: Row(children: [
              Icon(
                  settings.searchSource == entry.key
                      ? Icons.check_rounded
                      : Icons.music_note_rounded,
                  size: 20),
              const SizedBox(width: 12),
              Text(entry.value),
            ]),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (showLabel)
            Text(label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: TypeScale.medium))
          else
            Icon(Icons.library_music_outlined,
                size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Icon(Icons.expand_more_rounded,
              size: 18, color: scheme.onSurfaceVariant),
        ]),
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
        return _buildContent(context, wide: wide);
      },
    );
  }

  int get _resultCount => switch (_type) {
        _SearchType.all => _results.length +
            _artists.length +
            _albums.length +
            _playlists.length,
        _SearchType.song => _results.length,
        _SearchType.artist => _artists.length,
        _SearchType.album => _albums.length,
        _SearchType.playlist => _playlists.length,
      };

  Widget _buildToolbar({required bool wide}) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context);
    final inset = GToolbar.horizontalInset(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          inset + macOSWindowControlsInset(context), 8, inset, 4),
      child: Row(children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              style: TextStyle(fontSize: 15, color: scheme.onSurface),
              cursorColor: scheme.primary,
              decoration: InputDecoration(
                hintText: '搜索音乐',
                hintStyle:
                    TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(wide ? 0 : 14, 12, 0, 12),
                prefixIcon: wide
                    ? Icon(Icons.search_rounded,
                        size: 20, color: scheme.onSurfaceVariant)
                    : null,
                prefixIconConstraints:
                    const BoxConstraints.tightFor(width: 48, height: 48),
                suffixIcon: _keyword.isEmpty
                    ? null
                    : GToolbarButton(
                        icon: Icons.cancel_rounded,
                        tooltip: '清除搜索',
                        backgroundColor: Colors.transparent,
                        onTap: _clearSearch,
                      ),
                suffixIconConstraints:
                    const BoxConstraints.tightFor(width: 48, height: 48),
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
        const SizedBox(width: 8),
        _buildSourcePicker(showLabel: wide || textScale.scale(13) <= 18),
      ]),
    );
  }

  Widget _buildContent(BuildContext context, {required bool wide}) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: CustomScrollView(
            key: const ValueKey('search-results-scroll'),
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: Column(children: [
                  _buildToolbar(wide: wide),
                  Row(children: [
                    Expanded(child: _buildTypeTabs()),
                    if (wide && _resultCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: Text('$_resultCount 条结果',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      ),
                  ]),
                ]),
              ),
              if (_keyword.isEmpty)
                SliverToBoxAdapter(child: _buildHome(shrinkWrap: true))
              else if (_searching && _currentResultsEmpty)
                SliverToBoxAdapter(
                    child: Semantics(
                  label: '正在搜索',
                  liveRegion: true,
                  child: const GSkeletonList(itemCount: 8),
                ))
              else if (_pageError != null && _currentResultsEmpty)
                SliverFillRemaining(
                    hasScrollBody: false,
                    child: GEmptyState(
                      icon: Icons.error_outline_rounded,
                      text: '搜索失败，请重试',
                      onRetry: _retrySearch,
                    ))
              else
                ..._buildResultSlivers(compact: !wide),
            ],
          ),
        ),
      ),
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
      _combinedBatches.clear();
      _searching = false;
      _page = 1;
      _hasNextPage = false;
      _pageError = null;
      _retryPage = null;
    });
    _resetScroll();
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
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
                    constraints: const BoxConstraints(minHeight: 48),
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

  List<Widget> _buildResultSlivers({required bool compact}) {
    if (_currentResultsEmpty) {
      final (icon, text) = switch (_type) {
        _SearchType.all => (Icons.search_off, '没有找到相关内容'),
        _SearchType.song => (Icons.search_off, '没有找到相关歌曲'),
        _SearchType.artist => (Icons.person_search_outlined, '没有找到相关歌手'),
        _SearchType.album => (Icons.album_outlined, '没有找到相关专辑'),
        _SearchType.playlist => (Icons.queue_music, '没有找到相关歌单'),
      };
      return [
        SliverFillRemaining(
            hasScrollBody: false, child: GEmptyState(icon: icon, text: text))
      ];
    }
    return [
      if (_type == _SearchType.all)
        ..._buildCombinedSlivers(compact: compact)
      else if (_type == _SearchType.song)
        _songSliver()
      else if (_type == _SearchType.artist)
        _artistSliver()
      else if (_type == _SearchType.album)
        _albumSliver()
      else
        _buildPlaylistGrid(),
      SliverToBoxAdapter(child: _buildLoadMoreFooter()),
    ];
  }

  Widget _songSliver({List<Song>? songs, int offset = 0}) {
    final items = songs ?? _results;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => RepaintBoundary(
            child: SongRow(
          song: items[index],
          index: offset + index + 1,
          onTap: () => context
              .read<PlayerController>()
              .playQueue(_results, index: offset + index),
        )),
        childCount: items.length,
      ),
    );
  }

  Widget _artistSliver({List<SearchArtist>? artists}) {
    final items = artists ?? _artists;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => RepaintBoundary(
            child: _ArtistRow(
                artist: items[index], onTap: () => _openArtist(items[index]))),
        childCount: items.length,
      ),
    );
  }

  Widget _albumSliver({List<SearchAlbum>? albums}) {
    final items = albums ?? _albums;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => RepaintBoundary(
            child: _AlbumRow(
                album: items[index], onTap: () => _openAlbum(items[index]))),
        childCount: items.length,
      ),
    );
  }

  double _playlistCardHeight(double coverSize) {
    final scaler = MediaQuery.textScalerOf(context);
    // Reserve two title lines and one creator line using the card's type scale.
    return coverSize + 18 + scaler.scale(13) * 2.5 + scaler.scale(11.5) * 1.5;
  }

  Widget _buildPlaylistGrid() => SliverLayoutBuilder(
        builder: (context, constraints) {
          const spacing = 16.0;
          final width =
              (constraints.crossAxisExtent - 28).clamp(0.0, double.infinity);
          final columns = ((width + spacing) / (168 + spacing)).ceil();
          final count = columns < 1 ? 1 : columns;
          final coverSize = (width - spacing * (count - 1)) / count;
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                mainAxisExtent: _playlistCardHeight(coverSize),
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final playlist = _playlists[index];
                return PlaylistCard(
                    playlist: playlist, onTap: () => _openPlaylist(playlist));
              }, childCount: _playlists.length),
            ),
          );
        },
      );

  List<Widget> _buildCombinedSlivers({required bool compact}) {
    Widget heading(String title) => SliverToBoxAdapter(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 19, fontWeight: TypeScale.semibold)),
        ));
    return [
      for (final batch in _combinedBatches) ...[
        if (batch.playlists.isNotEmpty)
          SliverToBoxAdapter(
              child: _SearchSection(
            title: '歌单',
            child: SizedBox(
              height: _playlistCardHeight(148).clamp(218.0, double.infinity),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: batch.playlists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) => SizedBox(
                  width: 148,
                  child: PlaylistCard(
                      playlist: batch.playlists[index],
                      onTap: () => _openPlaylist(batch.playlists[index])),
                ),
              ),
            ),
          )),
        if (batch.artists.isNotEmpty) ...[
          heading('歌手'),
          if (compact)
            _artistSliver(artists: batch.artists)
          else
            SliverToBoxAdapter(
                child: SizedBox(
              height: 106,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: batch.artists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 18),
                itemBuilder: (_, index) => _DesktopArtistCard(
                    artist: batch.artists[index],
                    onTap: () => _openArtist(batch.artists[index])),
              ),
            )),
        ],
        if (batch.albums.isNotEmpty) ...[
          heading('专辑'),
          if (compact)
            _albumSliver(albums: batch.albums)
          else
            SliverToBoxAdapter(
                child: SizedBox(
              height: 106,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: batch.albums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 18),
                itemBuilder: (_, index) => _DesktopAlbumCard(
                    album: batch.albums[index],
                    onTap: () => _openAlbum(batch.albums[index])),
              ),
            )),
        ],
        if (batch.songs.isNotEmpty) ...[
          heading('歌曲'),
          _songSliver(songs: batch.songs, offset: batch.songOffset)
        ],
      ],
    ];
  }

  Widget _buildLoadMoreFooter() {
    final scheme = Theme.of(context).colorScheme;
    Widget child;
    if (_searching) {
      child = const Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              key: ValueKey('search-load-more-progress'),
              strokeWidth: 2,
              semanticsLabel: '正在加载更多搜索结果',
            )),
        SizedBox(width: 10),
        Text('正在加载更多…', style: TextStyle(fontSize: 13)),
      ]);
    } else if (_pageError != null) {
      child = TextButton.icon(
        key: const ValueKey('search-load-more-retry'),
        onPressed: _retrySearch,
        style: TextButton.styleFrom(
            minimumSize: const Size(48, 48), foregroundColor: scheme.error),
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('加载更多失败，点击重试'),
      );
    } else if (_hasNextPage) {
      // Keep an explicit action for keyboard and screen-reader users, and for
      // short result sections that do not fill the viewport yet.
      child = TextButton(
        onPressed: _loadNextPage,
        style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: scheme.onSurfaceVariant),
        child: const Text('继续下滑加载更多', style: TextStyle(fontSize: 13)),
      );
    } else {
      child = Text('已显示全部结果',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(child: child),
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

class _SearchBatch {
  const _SearchBatch(
      {required this.playlists,
      required this.songs,
      required this.artists,
      required this.albums,
      required this.songOffset});

  final List<Playlist> playlists;
  final List<Song> songs;
  final List<SearchArtist> artists;
  final List<SearchAlbum> albums;
  final int songOffset;
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
