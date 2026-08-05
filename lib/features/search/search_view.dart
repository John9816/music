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
enum _SearchType { song, artist, playlist }

/// 搜索页：单曲 / 歌手 / 歌单 分类搜索 + 多源切换 + 历史/热词。
class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final MusicApi _api = MusicApi();
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Song> _results = [];
  List<SearchArtist> _artists = [];
  List<Playlist> _playlists = [];
  bool _searching = false;
  String _keyword = '';
  _SearchType _type = _SearchType.song;

  static const _historyKey = 'search_history';
  static const _maxHistory = 10;
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
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _submit(String kw) {
    _controller.text = kw;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: kw.length),
    );
    _debounce?.cancel();
    _search(kw);
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

  void _switchType(_SearchType type) {
    if (type == _type) return;
    setState(() => _type = type);
    if (_keyword.isNotEmpty) _search(_keyword);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _keyword = '';
        _results = [];
        _artists = [];
        _playlists = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(value.trim()),
    );
  }

  Future<void> _search(String keyword) async {
    setState(() {
      _keyword = keyword;
      _searching = true;
    });
    try {
      final source = context.read<SettingsController>().source;
      switch (_type) {
        case _SearchType.song:
          final list = await _api.searchSongs(keyword, source: source);
          if (!mounted || _keyword != keyword) return;
          setState(() => _results = list);
        case _SearchType.artist:
          final list = await _api.searchArtists(keyword, source: source);
          if (!mounted || _keyword != keyword) return;
          setState(() => _artists = list);
        case _SearchType.playlist:
          final list = await _api.searchPlaylists(keyword, source: source);
          if (!mounted || _keyword != keyword) return;
          setState(() => _playlists = list);
      }
      // 搜索成功后保存到历史
      _saveHistory(keyword);
    } catch (_) {
      // 搜索失败保持之前的结果
    } finally {
      if (mounted && _keyword == keyword) {
        setState(() => _searching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          const GPageHeader(
            title: '搜索',
            subtitle: '搜索歌曲、歌手和歌单',
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
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '输入歌曲、歌手或歌单名称',
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
                    suffixIcon: _keyword.isEmpty
                        ? null
                        : GIconButton(
                            icon: Icons.cancel_rounded,
                            tooltip: '清除搜索',
                            size: 18,
                            padding: 8,
                            onTap: _clearSearch,
                          ),
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
          _buildTypeTabs(),
          _buildSourceRow(),
          const Divider(height: 1),
          Expanded(
            child: _keyword.isEmpty
                ? _buildHome()
                : _searching &&
                        _results.isEmpty &&
                        _artists.isEmpty &&
                        _playlists.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _buildResults(),
          ),
        ],
      ),
    );
  }

  void _clearSearch() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _keyword = '';
      _results = [];
      _artists = [];
      _playlists = [];
      _searching = false;
    });
  }

  /// 类型切换：单曲 / 歌手 / 歌单
  Widget _buildTypeTabs() {
    const labels = ['单曲', '歌手', '歌单'];
    const types = [_SearchType.song, _SearchType.artist, _SearchType.playlist];
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

  /// 多源切换：红源 / 绿源 / 橙源（跟随全局设置并持久化）
  Widget _buildSourceRow() {
    final settings = context.watch<SettingsController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: Row(
        children: [
          Icon(
            Icons.swap_horiz_rounded,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          for (final entry in AppConfig.musicSources.entries)
            GChoiceChip(
              label: entry.value,
              mini: true,
              selected: settings.source == entry.key,
              onTap: () {
                settings.setSource(entry.key);
                if (_keyword.isNotEmpty) _search(_keyword);
              },
            ),
        ],
      ),
    );
  }

  /// 按类型渲染结果
  Widget _buildResults() {
    switch (_type) {
      case _SearchType.song:
        return _results.isEmpty
            ? const GEmptyState(icon: Icons.search_off, text: '没有找到相关歌曲')
            : ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, i) => SongRow(
                  song: _results[i],
                  onTap: () => context
                      .read<PlayerController>()
                      .playQueue(_results, index: i),
                ),
              );
      case _SearchType.artist:
        return _artists.isEmpty
            ? const GEmptyState(
                icon: Icons.person_search_outlined, text: '没有找到相关歌手')
            : ListView.builder(
                itemCount: _artists.length,
                itemBuilder: (context, i) => _ArtistRow(
                  artist: _artists[i],
                  onTap: () => _openArtist(_artists[i]),
                ),
              );
      case _SearchType.playlist:
        return _playlists.isEmpty
            ? const GEmptyState(icon: Icons.queue_music, text: '没有找到相关歌单')
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 168,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio:
                      MediaQuery.sizeOf(context).width < 600 ? 0.65 : 0.78,
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
                            source: context.read<SettingsController>().source,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
    }
  }

  /// 搜索首页：搜索历史 + 热门搜索
  Widget _buildHome() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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
                    style: TextStyle(fontSize: 12, color: scheme.primary),
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
          const SizedBox(height: 28),
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
          borderRadius: BorderRadius.circular(20),
          color: hot
              ? scheme.primary.withValues(alpha: 0.10)
              : glassFill(context, alpha: 0.05),
          border: Border.all(
            color: hot
                ? scheme.primary.withValues(alpha: 0.25)
                : glassHairline(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: hot ? FontWeight.w600 : FontWeight.w400,
            color: hot ? scheme.primary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
