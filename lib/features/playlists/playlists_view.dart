import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/music_api.dart';
import '../../core/models/playlist.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/glass.dart';
import '../../widgets/playlist_card.dart';
import 'playlist_detail_view.dart';

/// 歌单页：排行榜横滑 + 歌单分类筛选 + 分页
class PlaylistsView extends StatefulWidget {
  const PlaylistsView({
    super.key,
    this.title = '发现',
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  State<PlaylistsView> createState() => _PlaylistsViewState();
}

class _PlaylistsViewState extends State<PlaylistsView> {
  static const _limit = 20;

  final MusicApi _api = MusicApi();

  late Future<List<Playlist>> _chartsFuture;
  final List<PlaylistCategoryGroup> _groups = kPlaylistCategories;
  int _groupIndex = -1;
  String? _cat;

  List<Playlist> _playlists = [];
  int _offset = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _requestSeq = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _chartsFuture = _api.getTopLists(source: _source());
    _loadPlaylists();
  }

  String _source() => context.read<SettingsController>().source;

  /// 只有红源（netease）支持歌单分类筛选，其他源不传 category。
  bool _supportsCategories() => _source() == 'netease';

  Future<void> _loadPlaylists({bool append = false}) async {
    if (append && (_loading || _loadingMore || !_hasMore)) return;
    // 请求序号：快速切换分类时，旧请求的结果会被丢弃，防止数据错乱。
    final seq = ++_requestSeq;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final list = await _api.getTopPlaylists(
        source: _source(),
        category: _supportsCategories() ? _cat : null,
        offset: append ? _offset : 0,
        limit: _limit,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        if (append) {
          final existingIds = _playlists.map((e) => e.id).toSet();
          _playlists = [
            ..._playlists,
            ...list.where((e) => !existingIds.contains(e.id)),
          ];
        } else {
          _playlists = list;
        }
        _offset = append ? _offset + list.length : list.length;
        _hasMore = list.length >= _limit;
        _error = null;
      });
    } catch (e) {
      if (mounted && seq == _requestSeq) {
        setState(() {
          _error = e is Exception ? e.toString() : "加载失败，请稍后重试";
          if (!append) _playlists = [];
        });
      }
    } finally {
      if (mounted && seq == _requestSeq) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _selectGroup(PlaylistCategoryGroup? group) {
    setState(() {
      _groupIndex = group == null ? -1 : _groups.indexOf(group);
      _cat = null;
    });
    _reload();
  }

  void _selectCat(PlaylistCategory cat) {
    setState(() => _cat = cat.name == '全部' ? null : cat.name);
    _reload();
  }

  void _reload() {
    _offset = 0;
    _hasMore = true;
    _loadPlaylists();
  }

  void _openDetail(Playlist p, {bool isChart = false}) {
    final source = _source();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailView(
          playlist: p,
          loader: isChart
              ? () => _api.getTopListDetail(p.id, source: source)
              : () => _api.getPlaylistDetail(p.id, source: source),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compactLayout = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // 滚动接近底部时自动加载下一页（_loadPlaylists 内部有防抖）
          if (notification.metrics.extentAfter < 400) {
            _loadPlaylists(append: true);
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: GPageHeader(
                title: widget.title,
                subtitle: widget.subtitle ??
                    (_supportsCategories() ? '排行榜与精选分类歌单' : '排行榜与热门歌单'),
              ),
            ),
            const SliverToBoxAdapter(child: SectionHeader('排行榜')),
            SliverToBoxAdapter(
              child: FutureBuilder<List<Playlist>>(
                future: _chartsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 150,
                      child: GLoading(padding: 40),
                    );
                  }
                  if (snapshot.hasError) {
                    return SizedBox(
                      height: 150,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "榜单加载失败",
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GButton(
                              label: "重试",
                              filled: false,
                              onTap: () => setState(() {
                                _chartsFuture = _api.getTopLists(
                                  source: _source(),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final charts = snapshot.data ?? const <Playlist>[];
                  return SizedBox(
                    height: 172,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: charts.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (context, i) => SizedBox(
                        width: 116,
                        child: PlaylistCard(
                          playlist: charts[i],
                          onTap: () => _openDetail(charts[i], isChart: true),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: SectionHeader(
                _supportsCategories() ? '分类歌单' : '热门歌单',
                subtitle: _supportsCategories() ? _cat ?? '全部' : null,
              ),
            ),
            if (_supportsCategories()) SliverToBoxAdapter(child: _buildChips()),
            if (_error != null && !_loading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 14),
                      GButton(
                        label: "重试",
                        filled: false,
                        onTap: _reload,
                      ),
                    ],
                  ),
                ),
              )
            else if (_playlists.isEmpty && _loading)
              const SliverToBoxAdapter(child: GLoading())
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 168,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: compactLayout ? 0.65 : 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => PlaylistCard(
                      playlist: _playlists[i],
                      onTap: () => _openDetail(_playlists[i]),
                    ),
                    childCount: _playlists.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _buildFooter()),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          ],
        ),
      ),
    );
  }

  /// 列表底部状态：加载中转圈 / 有更多时留白（自动加载）/ 到底提示
  Widget _buildFooter() {
    final scheme = Theme.of(context).colorScheme;
    final Widget child;
    if (_loadingMore) {
      child = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('加载中…', style: TextStyle(fontSize: 12)),
        ],
      );
    } else if (!_hasMore) {
      child = Text(
        _playlists.isEmpty ? '暂无歌单' : '已经到底啦',
        style: TextStyle(fontSize: 12, color: scheme.outline),
      );
    } else {
      // 有更多数据：留白即可，滚动到底自动触发加载
      child = const SizedBox(height: 16);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(child: child),
    );
  }

  Widget _buildChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              GChoiceChip(
                label: '全部',
                selected: _groupIndex == -1,
                onTap: () => _selectGroup(null),
              ),
              for (var i = 0; i < _groups.length; i++)
                GChoiceChip(
                  label: _groups[i].name,
                  selected: _groupIndex == i,
                  onTap: () => _selectGroup(_groups[i]),
                ),
            ],
          ),
        ),
        if (_groupIndex >= 0)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              children: [
                GChoiceChip(
                  label: '全部',
                  mini: true,
                  selected: _cat == null,
                  onTap: () => _selectCat(PlaylistCategory.all),
                ),
                for (final cat in _groups[_groupIndex].categories)
                  GChoiceChip(
                    label: cat.name,
                    mini: true,
                    selected: _cat == cat.name,
                    onTap: () => _selectCat(cat),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }
}
