import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/video_api.dart';
import '../../core/models/video.dart';
import '../../core/models/video_source.dart';
import '../../core/services/video_source_preferences.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import 'video_detail_view.dart';

class VideosView extends StatefulWidget {
  const VideosView({super.key, this.api, this.sourcePreferences});

  final VideoApi? api;
  final VideoSourcePreferences? sourcePreferences;

  @override
  State<VideosView> createState() => _VideosViewState();
}

class _VideosViewState extends State<VideosView> {
  late final VideoApi _api = widget.api ?? VideoApi();
  late final VideoSourcePreferences _sourcePreferences =
      widget.sourcePreferences ?? VideoSourcePreferences();
  final _searchController = TextEditingController();
  List<VideoSource> _sources = const [];
  VideoSource? _source;
  String? _sourceError;
  List<VideoCategory> _categories = const [];
  VideoFilter _filters = const VideoFilter();
  List<VideoItem> _items = const [];
  String? _category;
  String? _year;
  String? _region;
  String? _genre;
  String? _order;
  String? _error;
  bool _loading = true;
  bool _hasMore = false;
  int _page = 1;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSources());
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final version = ++_requestVersion;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final selectedSource = _source;
      if (selectedSource != null && !selectedSource.isExecutable) {
        if (!mounted || version != _requestVersion) return;
        setState(() {
          _items = const [];
          _hasMore = false;
          _loading = false;
        });
        return;
      }
      final page = append
          ? await _api.discover(
              source: selectedSource?.id,
              category: _category,
              year: _year,
              region: _region,
              genre: _genre,
              order: _order,
              page: _page + 1,
            )
          : await _api.discover(
              source: selectedSource?.id,
              category: _category,
              year: _year,
              region: _region,
              genre: _genre,
              order: _order,
              page: 1,
            );
      if (!append && _categories.isEmpty) {
        try {
          _categories = await _api.categories(source: selectedSource?.id);
          _filters = await _api.filters(source: selectedSource?.id);
        } catch (_) {
          // The catalog can still render when optional filter metadata is down.
        }
      }
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _items = append ? [..._items, ...page.list] : page.list;
        _page = page.page;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _search(String value) async {
    final keyword = value.trim();
    if (keyword.isEmpty) return _load();
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final selectedSource = _source;
      if (selectedSource != null && !selectedSource.isExecutable) {
        if (!mounted || version != _requestVersion) return;
        setState(() => _loading = false);
        return;
      }
      final page = await _api.search(
        keyword,
        source: selectedSource?.id,
        category: _category,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _items = page.list;
        _page = page.page;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (mounted && version == _requestVersion) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  void _resetAndLoad(VoidCallback change) {
    change();
    _page = 1;
    _load();
  }

  Future<void> _loadSources() async {
    try {
      final sources = await _api.sources().timeout(const Duration(seconds: 5));
      final selected = await _sourcePreferences.resolve(sources);
      if (!mounted) return;
      final changed = selected?.id != _source?.id;
      setState(() {
        _sources = sources;
        _source = selected;
        _sourceError = null;
      });
      if (changed && selected != null) {
        _resetCatalogForSource();
        await _load();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _sourceError = error.toString());
    }
  }

  void _resetCatalogForSource() {
    _searchController.clear();
    _category = null;
    _year = null;
    _region = null;
    _genre = null;
    _order = null;
    _items = const [];
    _page = 1;
    _hasMore = false;
  }

  void _selectSource(String? sourceId) {
    if (sourceId == null || sourceId == _source?.id) return;
    VideoSource? selected;
    for (final source in _sources) {
      if (source.id == sourceId) {
        selected = source;
        break;
      }
    }
    if (selected == null) return;
    setState(() {
      _source = selected;
      _sourceError = null;
      _resetCatalogForSource();
    });
    unawaited(_sourcePreferences.saveSelectedSource(selected.id));
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
                child: GPageHeader(
              title: '影视',
              subtitle: _source == null
                  ? '电影、剧集、动漫和综艺'
                  : '${_source!.name} · 电影、剧集、动漫和综艺',
              trailing: IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            )),
            if (_sources.isNotEmpty)
              SliverToBoxAdapter(child: _buildSourceSelector(context)),
            if (_source?.isUnsupported == true)
              SliverFillRemaining(child: _buildUnsupportedSource(context))
            else ...[
            SliverToBoxAdapter(child: _buildSearch(context)),
            SliverToBoxAdapter(child: _buildCategories(context)),
            SliverToBoxAdapter(child: _buildFilters(context)),
            if (_loading && _items.isEmpty)
              const SliverFillRemaining(child: GLoading())
            else if (_error != null && _items.isEmpty)
              SliverFillRemaining(
                  child: GEmptyState(
                icon: Icons.wifi_off,
                text: '影视服务暂时不可用',
                onRetry: _load,
              ))
            else if (_items.isEmpty)
              const SliverFillRemaining(
                  child: GEmptyState(
                icon: Icons.movie_outlined,
                text: '没有找到相关影视',
              ))
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisExtent: 270,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (_, index) => _VideoCard(
                    item: _items[index],
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          VideoDetailView(
                            api: _api,
                            videoId: _items[index].id,
                            source: _source?.id,
                          ),
                    )),
                  ),
                ),
              ),
              if (_hasMore)
                SliverToBoxAdapter(
                    child: Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Center(
                      child: OutlinedButton.icon(
                    onPressed: _loading ? null : () => _load(append: true),
                    icon: const Icon(Icons.expand_more),
                    label: const Text('加载更多'),
                  )),
                    )),
            ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSourceSelector(BuildContext context) {
    final selectedId = _source?.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.source_outlined, size: 18),
          const SizedBox(width: 8),
          const Text('影视源'),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _sources.any((source) => source.id == selectedId)
                    ? selectedId
                    : null,
                hint: const Text('选择源'),
                items: _sources
                    .map(
                      (source) => DropdownMenuItem<String>(
                        value: source.id,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                source.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              source.statusLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: source.isExecutable
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _selectSource,
              ),
            ),
          ),
          if (_sourceError != null)
            IconButton(
              tooltip: '刷新源目录',
              icon: const Icon(Icons.refresh),
              onPressed: _loadSources,
            ),
        ],
      ),
    );
  }

  Widget _buildUnsupportedSource(BuildContext context) {
    final source = _source;
    return GEmptyState(
      icon: Icons.block_outlined,
      text: source == null
          ? '当前影视源暂不支持'
          : '${source.name}\n${source.unavailableMessage}',
      onRetry: source == null ? _loadSources : null,
    );
  }

  Widget _buildSearch(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: '搜索电影、剧集、演员',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _load();
                      setState(() {});
                    },
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _buildCategories(BuildContext context) => _ChipStrip(
        label: '分类',
        values: [
          const VideoCategory(id: '', name: '全部', url: ''),
          ..._categories
        ],
        selected: _category ?? '',
        labelOf: (value) => value.name,
        valueOf: (value) => value.id,
        onChanged: (value) =>
            _resetAndLoad(() => _category = value.isEmpty ? null : value),
      );

  Widget _buildFilters(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _dropdown('年份', _year, _filters.years,
                (v) => _resetAndLoad(() => _year = v)),
            _dropdown('地区', _region, _filters.regions,
                (v) => _resetAndLoad(() => _region = v)),
            _dropdown('类型', _genre, _filters.genres,
                (v) => _resetAndLoad(() => _genre = v)),
            _dropdown('排序', _order, _filters.orders,
                (v) => _resetAndLoad(() => _order = v)),
          ],
        ),
      );

  Widget _dropdown(String hint, String? value, List<String> values,
      ValueChanged<String?> onChanged) {
    return DropdownButton<String>(
      value: values.contains(value) ? value : null,
      hint: Text(hint),
      items: [
        DropdownMenuItem<String>(value: null, child: Text('全部$hint')),
        ...values
            .map((item) => DropdownMenuItem(value: item, child: Text(item))),
      ],
      onChanged: onChanged,
    );
  }
}

class _ChipStrip<T> extends StatelessWidget {
  const _ChipStrip(
      {required this.label,
      required this.values,
      required this.selected,
      required this.labelOf,
      required this.valueOf,
      required this.onChanged});

  final String label;
  final List<T> values;
  final String selected;
  final String Function(T) labelOf;
  final String Function(T) valueOf;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            Padding(
                padding: const EdgeInsets.only(right: 8, top: 10),
                child: Text(label)),
            for (final value in values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(labelOf(value)),
                  selected: selected == valueOf(value),
                  onSelected: (_) => onChanged(valueOf(value)),
                ),
              ),
          ],
        ),
      );
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.item, required this.onTap});

  final VideoItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.posterUrl == null
                    ? Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const Icon(Icons.movie_outlined, size: 42),
                      )
                    : AsyncCover(
                        url: item.posterUrl!, size: double.infinity, radius: 8),
              ),
            ),
            const SizedBox(height: 7),
            Text(item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (item.status.isNotEmpty)
              Text(item.status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );
}
