import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/api/live_tv_api.dart';
import '../../core/models/live_tv.dart';
import '../../widgets/glass.dart';
import 'live_player_view.dart';

class LiveTvView extends StatefulWidget {
  const LiveTvView({
    super.key,
    this.api,
    this.onOpenChannel,
    this.onBeforeOpenChannel,
  });

  final LiveTvApi? api;
  final ValueChanged<LiveChannel>? onOpenChannel;
  final Future<void> Function()? onBeforeOpenChannel;

  @override
  State<LiveTvView> createState() => _LiveTvViewState();
}

class _LiveTvViewState extends State<LiveTvView> {
  late final LiveTvApi _api = widget.api ?? LiveTvApi();
  final TextEditingController _searchController = TextEditingController();
  LiveTvCatalog? _catalog;
  String? _selectedGroupId;
  String _query = '';
  String? _error;
  bool _loading = true;
  bool _refreshing = false;
  bool _showingStaleCache = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool includeCache = true}) async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _error = null;
        _showingStaleCache = false;
        if (_catalog == null) _loading = true;
      });
    }

    if (includeCache) {
      final cached = await _api.readCached();
      if (!mounted || generation != _generation) return;
      if (cached != null) _applyCatalog(cached);
    }

    if (mounted) setState(() => _refreshing = true);
    try {
      final refreshed = await _api.refresh();
      if (!mounted || generation != _generation) return;
      _applyCatalog(refreshed);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (_catalog == null) {
          _error = '直播源加载失败';
        } else {
          _showingStaleCache = true;
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _applyCatalog(LiveTvCatalog catalog) {
    final selectedExists = catalog.groups.any(
      (group) => group.id == _selectedGroupId,
    );
    setState(() {
      _catalog = catalog;
      _selectedGroupId = selectedExists
          ? _selectedGroupId
          : catalog.groups.isEmpty
              ? null
              : catalog.groups.first.id;
      _loading = false;
      _error = null;
      _showingStaleCache = false;
    });
  }

  List<LiveChannel> get _visibleChannels {
    final catalog = _catalog;
    if (catalog == null) return const <LiveChannel>[];
    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      return catalog.channels
          .where(
            (channel) =>
                channel.name.toLowerCase().contains(query) ||
                channel.tvgId.toLowerCase().contains(query),
          )
          .toList(growable: false);
    }
    for (final group in catalog.groups) {
      if (group.id == _selectedGroupId) return group.channels;
    }
    return const <LiveChannel>[];
  }

  Future<void> _openChannel(LiveChannel channel) async {
    await widget.onBeforeOpenChannel?.call();
    if (!mounted) return;
    if (widget.onOpenChannel != null) {
      widget.onOpenChannel!(channel);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LivePlayerView(channel: channel)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    return Scaffold(
      appBar: GAppBar(
        title: '电视直播',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(includeCache: false),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      catalog == null
                          ? '正在读取频道源'
                          : '${catalog.groups.length} 个分组 · '
                              '${catalog.channelCount} 个频道 · '
                              '${catalog.lineCount} 条线路',
                      style: TextStyle(
                        fontSize: TypeScale.small,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_refreshing)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: SizedBox(
                          height: 2,
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_showingStaleCache)
              const SliverToBoxAdapter(child: _StaleCacheNotice()),
            if (catalog != null) ...[
              SliverToBoxAdapter(child: _buildSearch()),
              SliverToBoxAdapter(child: _buildGroups(catalog.groups)),
            ],
            if (_loading && catalog == null)
              const SliverFillRemaining(child: GLoading())
            else if (_error != null && catalog == null)
              SliverFillRemaining(
                child: GEmptyState(
                  icon: Icons.cloud_off_outlined,
                  text: _error!,
                  onRetry: _load,
                ),
              )
            else if (_visibleChannels.isEmpty)
              SliverFillRemaining(
                child: GEmptyState(
                  icon: Icons.search_off,
                  text: _query.trim().isEmpty ? '当前分组暂无频道' : '没有匹配的频道',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisExtent: 82,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _visibleChannels.length,
                  itemBuilder: (_, index) {
                    final channel = _visibleChannels[index];
                    return _ChannelTile(
                      key: ValueKey('live-channel-${channel.id}'),
                      channel: channel,
                      onTap: () => _openChannel(channel),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          key: const ValueKey('live-search-field'),
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(
            hintText: '搜索频道',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
      );

  Widget _buildGroups(List<LiveChannelGroup> groups) => SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          itemCount: groups.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            final group = groups[index];
            return ChoiceChip(
              key: ValueKey('live-group-${group.id}'),
              label: Text(group.name),
              selected: group.id == _selectedGroupId,
              onSelected: (_) => setState(() {
                _selectedGroupId = group.id;
                _query = '';
                _searchController.clear();
              }),
            );
          },
        ),
      );
}

class _StaleCacheNotice extends StatelessWidget {
  const _StaleCacheNotice();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 18, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            const Expanded(child: Text('当前显示缓存，刷新失败')),
          ],
        ),
      );
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
  });

  final LiveChannel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: glassFill(context, alpha: 0.055),
          border: Border.all(color: glassHairline(context)),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 46,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: channel.logoUrl.isEmpty
                    ? _ChannelIcon(color: scheme.primary)
                    : CachedNetworkImage(
                        imageUrl: channel.logoUrl,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) =>
                            _ChannelIcon(color: scheme.primary),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${channel.lines.length} 条线路',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.outline, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ChannelIcon extends StatelessWidget {
  const _ChannelIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: color.withValues(alpha: 0.12),
        child: Icon(Icons.live_tv, color: color, size: 24),
      );
}
