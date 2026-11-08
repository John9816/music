import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/models/song.dart';
import '../../core/player/car_media_library.dart';
import '../../core/player/player_controller.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/async_cover.dart';
import 'car_player_panel.dart';

/// Large controls for directly installed Android head units. Android Auto uses
/// its own host-rendered media templates instead of this view.
class CarHomeView extends StatefulWidget {
  const CarHomeView({super.key, required this.onFavorite});
  final VoidCallback onFavorite;
  @override
  State<CarHomeView> createState() => _CarHomeViewState();
}

class _CarHomeViewState extends State<CarHomeView> {
  static const _searchId = 'search';
  final _query = TextEditingController();
  CarMediaLibrary? _library;
  String _category = CarMediaLibrary.queueId;
  String _submitted = '';
  List<Song> _songs = [];
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final library = context.read<CarMediaLibrary>();
    if (identical(library, _library)) return;
    _library?.removeListener(_changed);
    _library = library..addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    _request++;
    _library?.removeListener(_changed);
    _query.dispose();
    super.dispose();
  }

  void _changed() {
    if (_library?.changedCategory != null &&
        _library?.changedCategory != _category) {
      return;
    }
    if (mounted) unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _songs = [];
    });
    try {
      final songs = _category == _searchId
          ? await _library!.search(_submitted)
          : await _library!.songsFor(_category);
      if (!mounted || request != _request) return;
      setState(() {
        _songs = songs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = error is CarMediaLibraryException ? error.message : '加载失败，请重试';
      });
    }
  }

  void _select(String id) {
    if (_category == id) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _category = id);
    unawaited(_load());
  }

  void _search() {
    FocusManager.instance.primaryFocus?.unfocus();
    _submitted = _query.text.trim();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: const ValueKey('car-home'),
      backgroundColor: scheme.surfaceContainerLowest,
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600 &&
            constraints.maxWidth > constraints.maxHeight * 1.25;
        final content =
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(context, wide),
          if (!wide) SizedBox(height: 80, child: _navigation(horizontal: true)),
          const SizedBox(height: 12),
          Expanded(
              child: wide
                  ? LayoutBuilder(
                      builder: (context, space) => Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                    width: (space.maxWidth * .44)
                                        .clamp(256.0, 420.0),
                                    child: CarPlayerPanel(
                                        onFavorite: widget.onFavorite)),
                                const SizedBox(width: 16),
                                Expanded(child: _catalog(context)),
                              ]))
                  : Column(children: [
                      SizedBox(
                          height:
                              (constraints.maxHeight * .44).clamp(220.0, 380.0),
                          child: CarPlayerPanel(onFavorite: widget.onFavorite)),
                      const SizedBox(height: 12),
                      Expanded(child: _catalog(context)),
                    ])),
        ]);
        return Row(children: [
          if (wide) SizedBox(width: 88, child: _navigation()),
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: content)),
        ]);
      })),
    );
  }

  Widget _header(BuildContext context, bool wide) {
    final source =
        context.select<SettingsController, String>((s) => s.searchSource);
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('旅途，和喜欢的音乐',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text(
                    '车载模式 · ${_category == _searchId ? '搜索' : CarMediaLibrary.categories[_category]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant)),
              ])),
          if (_category == _searchId)
            PopupMenuButton<String>(
              tooltip: '搜索源',
              initialValue: source,
              onSelected: (value) =>
                  context.read<SettingsController>().setSearchSource(value),
              itemBuilder: (_) => [
                for (final entry in AppConfig.musicSources.entries)
                  PopupMenuItem(value: entry.key, child: Text(entry.value))
              ],
              child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minWidth: 64, minHeight: 64),
                  child: Center(
                      child: Text(AppConfig.musicSources[source] ?? source,
                          style: const TextStyle(fontSize: 14)))),
            ),
          if (!wide)
            CarControl(
                key: const ValueKey('car-exit'),
                icon: Icons.close_rounded,
                label: '退出车载模式',
                onPressed: () => context
                    .read<SettingsController>()
                    .setCarModeEnabled(false)),
        ]));
  }

  Widget _navigation({bool horizontal = false}) {
    const icons = {
      CarMediaLibrary.queueId: Icons.queue_music_rounded,
      CarMediaLibrary.favoritesId: Icons.favorite_rounded,
      CarMediaLibrary.recentId: Icons.history_rounded,
      CarMediaLibrary.downloadsId: Icons.download_done_rounded,
      _searchId: Icons.search_rounded,
    };
    const labels = {
      CarMediaLibrary.queueId: '队列',
      CarMediaLibrary.favoritesId: '喜欢',
      CarMediaLibrary.recentId: '最近',
      CarMediaLibrary.downloadsId: '下载',
      _searchId: '搜索',
    };
    final scheme = Theme.of(context).colorScheme;
    final entries = [
      for (final id in icons.keys)
        SizedBox(
            width: horizontal ? 76 : 88,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Semantics(
                  selected: _category == id,
                  child: TextButton(
                    key: ValueKey('car-category-$id'),
                    style: TextButton.styleFrom(
                        minimumSize: const Size(64, 72),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        backgroundColor: _category == id
                            ? scheme.primaryContainer
                            : Colors.transparent,
                        foregroundColor: _category == id
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20))),
                    onPressed: () => _select(id),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icons[id],
                          size: 26,
                          color: id == CarMediaLibrary.favoritesId
                              ? const Color(0xFFE5484D)
                              : null),
                      const SizedBox(height: 4),
                      Text(labels[id]!,
                          maxLines: 1, style: const TextStyle(fontSize: 12)),
                    ]),
                  )),
            ))
    ];
    if (horizontal) {
      return ListView(scrollDirection: Axis.horizontal, children: entries);
    }
    return Column(children: [
      Expanded(
          child: ListView(
              padding: const EdgeInsets.only(top: 8), children: entries)),
      CarControl(
          key: const ValueKey('car-exit'),
          icon: Icons.exit_to_app_rounded,
          label: '退出车载模式',
          onPressed: () =>
              context.read<SettingsController>().setCarModeEnabled(false)),
      const SizedBox(height: 8),
    ]);
  }

  Widget _catalog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = context.select<PlayerController, String?>((p) =>
        p.current == null ? null : CarMediaLibrary.mediaIdFor(p.current!));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_category == _searchId)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      key: const ValueKey('car-search-field'),
                      controller: _query,
                      onSubmitted: (_) => _search(),
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                          hintText: '歌曲或歌手',
                          constraints: const BoxConstraints(minHeight: 64),
                          filled: true,
                          fillColor: scheme.surfaceContainer,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none)))),
              CarControl(
                  key: const ValueKey('car-search-submit'),
                  icon: Icons.search_rounded,
                  label: '提交搜索',
                  onPressed: _search),
            ])),
      Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _message(_error!, retry: true)
                  : _songs.isEmpty
                      ? _message(_category == _searchId && _submitted.isEmpty
                          ? '输入歌曲或歌手，点击搜索'
                          : '这里还没有歌曲')
                      : ListView.builder(
                          key: ValueKey('car-list-$_category'),
                          itemCount: _songs.length,
                          itemBuilder: (context, index) {
                            final song = _songs[index];
                            final selected =
                                CarMediaLibrary.mediaIdFor(song) == current;
                            return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Material(
                                  color: selected
                                      ? scheme.primaryContainer
                                          .withValues(alpha: .5)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(18),
                                  child: InkWell(
                                    key: ValueKey('car-song-$index'),
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () => context
                                        .read<PlayerController>()
                                        .playQueue(_songs, index: index),
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(minHeight: 84),
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                          child: Row(children: [
                                            AsyncCover(
                                                url: song.album.picUrl,
                                                size: 52,
                                                radius: 12),
                                            const SizedBox(width: 12),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text(song.name,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                          fontSize: 17,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: selected
                                                              ? scheme.primary
                                                              : scheme
                                                                  .onSurface)),
                                                  const SizedBox(height: 5),
                                                  Text(song.artistNames,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                          fontSize: 14,
                                                          color: scheme
                                                              .onSurfaceVariant)),
                                                ])),
                                            if (selected)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 8),
                                                  child: Icon(
                                                      Icons.equalizer_rounded,
                                                      color: scheme.primary,
                                                      size: 22)),
                                          ])),
                                    ),
                                  ),
                                ));
                          },
                        )),
    ]);
  }

  Widget _message(String message, {bool retry = false}) => Center(
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 17,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (retry) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(128, 64)),
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试')),
            ],
          ])));
}
