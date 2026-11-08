import 'dart:async' show unawaited, Timer;
import 'dart:ui' show ImageFilter;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/player/lrc_parser.dart';
import '../../core/player/player_controller.dart';
import '../../core/services/song_download_service.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/settings/lyric_appearance.dart';
import 'karaoke_lyric_text.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../../widgets/playback_mode_button.dart';
import '../search/artist_names_link.dart';

enum MiniPlayerPanel { lyrics, queue }

class DesktopPlayerPanel extends StatelessWidget {
  const DesktopPlayerPanel({
    super.key,
    required this.panel,
    required this.onClose,
  });

  final MiniPlayerPanel panel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (dark ? scheme.surfaceContainer : scheme.surface)
                .withValues(alpha: dark ? 0.91 : 0.88),
            border: Border(
              left: BorderSide(color: glassHairline(context)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.28 : 0.10),
                blurRadius: 30,
                offset: const Offset(-10, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              GWindowControlsSafeRegion(
                  child: _PanelHeader(panel: panel, onClose: onClose)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Motion.fast,
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: panel == MiniPlayerPanel.lyrics
                      ? const _DesktopLyrics(key: ValueKey('desktop-lyrics'))
                      : const _DesktopQueue(key: ValueKey('desktop-queue')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.panel, required this.onClose});

  final MiniPlayerPanel panel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GToolbar(
      centerTitle: false,
      title: Text(
        panel == MiniPlayerPanel.lyrics ? '歌词' : '播放队列',
      ),
      actions: [
        GToolbarButton(
          icon: Icons.close_rounded,
          tooltip: panel == MiniPlayerPanel.lyrics ? '关闭歌词' : '关闭播放队列',
          onTap: onClose,
        ),
      ],
    );
  }
}

class _DesktopLyrics extends StatefulWidget {
  const _DesktopLyrics({super.key});

  @override
  State<_DesktopLyrics> createState() => _DesktopLyricsState();
}

class _DesktopLyricsState extends State<_DesktopLyrics> {
  final ScrollController _scrollController = ScrollController();
  String _source = '';
  List<LrcLine> _lines = const [];
  int _lastLine = -1;
  bool _userScrolling = false;
  Timer? _scrollResumeTimer;
  Object? _layoutSignature;
  final List<double> _lineHeights = [];
  final List<double> _lineOffsets = [];
  double _topPadding = 0;

  @override
  void dispose() {
    _scrollResumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final appearance =
        context.select<SettingsController, (int, LyricFontStyle)>(
            (s) => (s.lyricFontSize, s.lyricFontStyle));
    final lyric = player.lyric;
    if (_source != lyric) {
      _source = lyric;
      _lines = parseLrc(lyric);
      _layoutSignature = null;
      _lastLine = -1;
      _userScrolling = false;
      _scrollResumeTimer?.cancel();
    }
    final song = player.current;
    final scheme = Theme.of(context).colorScheme;
    final style = lyricTextStyle(
      DefaultTextStyle.of(context).style.copyWith(color: scheme.onSurface),
      fontSize: appearance.$1,
      fontStyle: appearance.$2,
      scale: 18 / 28,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
          child: Text(
            song == null ? '暂未播放' : '${song.name}  ·  ${song.artistNames}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: _lines.isEmpty
              ? _EmptyLyrics(loading: player.loading && lyric.isEmpty)
              : LayoutBuilder(builder: (context, constraints) {
                  _measureLines(context, constraints, style);
                  return StreamBuilder<int>(
                    stream: player.positionStream.map(_currentLine).distinct(),
                    initialData: _currentLine(player.position),
                    builder: (context, snapshot) {
                      final current =
                          snapshot.data ?? _currentLine(player.position);
                      _scrollToCurrent(current);
                      return Stack(
                        children: [
                          NotificationListener<ScrollNotification>(
                            onNotification: _handleScroll,
                            child: ListView.builder(
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(
                                  24,
                                  _topPadding,
                                  24,
                                  math.max(
                                      0,
                                      (constraints.maxHeight -
                                              _lineHeights.last) /
                                          2)),
                              itemCount: _lines.length,
                              itemExtentBuilder: (index, _) =>
                                  _lineHeights[index],
                              itemBuilder: (context, index) {
                                final line = _lines[index];
                                final selected = index == current;
                                return Semantics(
                                  button: true,
                                  selected: selected,
                                  label: '跳转到 ${_formatTime(line.time)}',
                                  child: GPressScale(
                                    onTap: () async {
                                      await player.seek(line.time);
                                      if (mounted) _resumeFollowing();
                                    },
                                    scale: 1,
                                    child: Container(
                                      height: _lineHeights[index],
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      child: selected && line.words.isNotEmpty
                                          ? KaraokeLyricText(
                                              line: line,
                                              style: style,
                                              position: player.position,
                                              positionStream:
                                                  player.positionStream,
                                              playing: player.playing)
                                          : Text(
                                              line.text.isEmpty
                                                  ? '· · ·'
                                                  : line.text,
                                              style: style.copyWith(
                                                color: selected
                                                    ? scheme.onSurface
                                                    : scheme.onSurface
                                                        .withValues(
                                                            alpha:
                                                                _userScrolling
                                                                    ? 0.7
                                                                    : 0.35),
                                              ),
                                            ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_userScrolling)
                            Positioned(
                              right: 16,
                              bottom: 16,
                              child: GButton(
                                label: '回到当前',
                                filled: false,
                                small: true,
                                onTap: _resumeFollowing,
                              ),
                            ),
                        ],
                      );
                    },
                  );
                }),
        ),
      ],
    );
  }

  void _measureLines(
      BuildContext context, BoxConstraints constraints, TextStyle style) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final signature = (constraints, scaler, direction, locale, style);
    if (_layoutSignature == signature) return;
    _layoutSignature = signature;
    _lastLine = -1;
    _lineHeights.clear();
    _lineOffsets.clear();
    final painter = TextPainter(
        textDirection: direction, textScaler: scaler, locale: locale);
    var offset = 0.0;
    for (final line in _lines) {
      painter.text =
          TextSpan(text: line.text.isEmpty ? '· · ·' : line.text, style: style);
      painter.layout(maxWidth: math.max(1, constraints.maxWidth - 48));
      final height = math.max(58.0, painter.height.ceilToDouble() + 24);
      _lineOffsets.add(offset);
      _lineHeights.add(height);
      offset += height;
    }
    painter.dispose();
    _topPadding = math.max(0, (constraints.maxHeight - _lineHeights.first) / 2);
  }

  bool _handleScroll(ScrollNotification notification) {
    if ((notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle)) {
      _scrollResumeTimer?.cancel();
      if (!_userScrolling) setState(() => _userScrolling = true);
    } else if (notification is ScrollEndNotification && _userScrolling) {
      _scrollResumeTimer?.cancel();
      _scrollResumeTimer = Timer(const Duration(seconds: 5), _resumeFollowing);
    }
    return false;
  }

  void _resumeFollowing() {
    _scrollResumeTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _userScrolling = false;
      _lastLine = -1;
    });
  }

  int _currentLine(Duration position) {
    var result = 0;
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].time > position) break;
      result = i;
    }
    return result;
  }

  void _scrollToCurrent(int index) {
    if (index == _lastLine) return;
    if (_userScrolling) return; // Don't auto-scroll when user is scrolling
    final initial = _lastLine == -1;
    _lastLine = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userScrolling || index != _lastLine) return;
      if (!_scrollController.hasClients) {
        _lastLine = -1;
        return;
      }
      final target = (_topPadding +
              _lineOffsets[index] +
              _lineHeights[index] / 2 -
              _scrollController.position.viewportDimension / 2)
          .clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      final duration = PlatformMotion.duration(context, Motion.normal);
      if (initial || duration == Duration.zero) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _EmptyLyrics extends StatelessWidget {
  const _EmptyLyrics({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            loading ? '歌词加载中' : '暂无歌词',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

enum _QueueSongAction { play, playNext, favorite, playlist, download }

class _DesktopQueue extends StatefulWidget {
  const _DesktopQueue({super.key});

  @override
  State<_DesktopQueue> createState() => _DesktopQueueState();
}

class _DesktopQueueState extends State<_DesktopQueue> {
  final UserApi _userApi = UserApi();
  final Set<String> _favorites = {};
  final Set<String> _downloading = {};
  String? _favoritesToken;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = context.read<AuthController>().token;
    if (token == _favoritesToken) return;
    _favoritesToken = token;
    _favorites.clear();
    if (token != null) unawaited(_loadFavorites(token));
  }

  Future<void> _loadFavorites(String token) async {
    try {
      final items = await _userApi.getFavorites(token);
      if (!mounted || token != _favoritesToken) return;
      setState(() {
        _favorites
          ..clear()
          ..addAll(items.map((item) {
            final id = item['songId'] ?? item['id'];
            final source = item['source'] ?? 'netease';
            return '$source:$id';
          }));
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final queue = player.queue;
    final upcomingIndexes = <int>[
      for (var index = player.queueIndex + 1; index < queue.length; index++)
        index,
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _ModeButton(
                icon: player.playbackMode.icon,
                label: player.playbackMode.label,
                selected: true,
                onTap: player.cyclePlaybackMode,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '接下来播放',
                  style: TextStyle(fontSize: 17, fontWeight: TypeScale.bold),
                ),
              ),
              Text(
                '${upcomingIndexes.length} 首',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: upcomingIndexes.isEmpty
              ? Center(
                  child: Text(
                    '没有更多待播放歌曲',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: upcomingIndexes.length,
                  itemBuilder: (context, visibleIndex) {
                    final queueIndex = upcomingIndexes[visibleIndex];
                    final song = queue[queueIndex];
                    final key = _songKey(song);
                    return _QueueRow(
                      song: song,
                      liked: _favorites.contains(key),
                      downloading: _downloading.contains(key),
                      onTap: () => player.playAt(queueIndex),
                      onAction: (action) => unawaited(
                        _handleAction(action, song, queueIndex),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _handleAction(
    _QueueSongAction action,
    Song song,
    int queueIndex,
  ) async {
    final player = context.read<PlayerController>();
    switch (action) {
      case _QueueSongAction.play:
        await player.playAt(queueIndex);
      case _QueueSongAction.playNext:
        player.moveToNext(queueIndex);
        _message('已设为下一首播放');
      case _QueueSongAction.favorite:
        await _toggleFavorite(song, player);
      case _QueueSongAction.playlist:
        await _addToPlaylist(song);
      case _QueueSongAction.download:
        await _download(song);
    }
  }

  Future<void> _toggleFavorite(Song song, PlayerController player) async {
    final token = context.read<AuthController>().token;
    if (token == null) {
      _message('请先登录后再喜欢歌曲');
      return;
    }
    final key = _songKey(song);
    final liked = _favorites.contains(key);
    try {
      if (liked) {
        await _userApi.removeFavorite(song.id, song.source, token);
      } else {
        await _userApi.addFavorite(song, token);
      }
      if (!mounted) return;
      setState(() {
        liked ? _favorites.remove(key) : _favorites.add(key);
      });
      if (player.current?.id == song.id &&
          player.current?.source == song.source) {
        player.setLiked(!liked);
      }
      _message(liked ? '已取消喜欢' : '已加入喜欢的音乐');
    } catch (error) {
      _message(_errorText(error, '喜欢操作失败'));
    }
  }

  Future<void> _addToPlaylist(Song song) async {
    final token = context.read<AuthController>().token;
    if (token == null) {
      _message('请先登录后再收藏到歌单');
      return;
    }
    try {
      final playlists = await _userApi.getOwnedPlaylists(token);
      if (!mounted) return;
      final selection = await showModalBottomSheet<Object>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => _PlaylistChooser(playlists: playlists),
      );
      if (!mounted || selection == null) return;

      String? playlistId;
      String? playlistName;
      if (selection == _PlaylistChooser.createNew) {
        final name = await showDialog<String>(
          context: context,
          useRootNavigator: true,
          builder: (_) => const _CreatePlaylistDialog(),
        );
        if (!mounted || name == null) return;
        final created = await _userApi.createPlaylist(name, null, token);
        playlistId = _playlistId(created);
        playlistName = name;
      } else if (selection is Map<String, dynamic>) {
        playlistId = _playlistId(selection);
        playlistName = _playlistName(selection);
      }
      if (playlistId == null) throw Exception('歌单数据缺少 ID');
      await _userApi.addSongToPlaylist(playlistId, song, token);
      _message('已收藏到歌单“${playlistName ?? '未命名歌单'}”');
    } catch (error) {
      _message(_errorText(error, '收藏到歌单失败'));
    }
  }

  Future<void> _download(Song song) async {
    final key = _songKey(song);
    if (_downloading.contains(key)) return;
    setState(() => _downloading.add(key));
    _message('开始下载“${song.name}”');
    try {
      final quality = context.read<SettingsController>().downloadQuality;
      final result = await SongDownloadService.instance.download(
        song,
        quality: quality,
      );
      _message(result.alreadyExists ? '歌曲已在下载目录中' : '下载完成：${result.file.path}');
    } catch (error) {
      _message(_errorText(error, '下载失败'));
    } finally {
      if (mounted) setState(() => _downloading.remove(key));
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _errorText(Object error, String fallback) {
    final text = error.toString().replaceFirst(RegExp(r'^Exception: '), '');
    return text.isEmpty ? fallback : text;
  }

  String _songKey(Song song) => '${song.source}:${song.id}';

  String? _playlistId(Map<String, dynamic> json) {
    final raw = json['id'] ?? json['playlistId'];
    if (raw != null && raw.toString().isNotEmpty) return raw.toString();
    final playlist = json['playlist'];
    return playlist is Map
        ? _playlistId(Map<String, dynamic>.from(playlist))
        : null;
  }

  String _playlistName(Map<String, dynamic> json) {
    return (json['name'] ?? json['title'] ?? '未命名歌单').toString();
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.14)
              : scheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: TypeScale.semibold,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.song,
    required this.liked,
    required this.downloading,
    required this.onTap,
    required this.onAction,
  });

  final Song song;
  final bool liked;
  final bool downloading;
  final VoidCallback onTap;
  final ValueChanged<_QueueSongAction> onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 62,
      child: Row(
        children: [
          Expanded(
            child: GPressScale(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Row(
                  children: [
                    AsyncCover(url: song.album.picUrl, size: 44, radius: 7),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: TypeScale.semibold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          ArtistNamesLink(
                            artists: song.artists,
                            source: song.source,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<_QueueSongAction>(
            tooltip: '更多：${song.name}',
            useRootNavigator: true,
            position: PopupMenuPosition.under,
            constraints: const BoxConstraints(minWidth: 210, maxWidth: 244),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: onAction,
            itemBuilder: (context) => [
              _menuItem(
                _QueueSongAction.play,
                Icons.play_arrow_rounded,
                '播放',
              ),
              _menuItem(
                _QueueSongAction.playNext,
                Icons.skip_next_rounded,
                '下一首播放',
              ),
              _menuItem(
                _QueueSongAction.favorite,
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                liked ? '取消喜欢' : '喜欢',
                color: liked ? AppBrand.favoriteRed : null,
              ),
              _menuItem(
                _QueueSongAction.playlist,
                Icons.playlist_add_rounded,
                '收藏到歌单',
              ),
              _menuItem(
                _QueueSongAction.download,
                downloading
                    ? Icons.downloading_rounded
                    : Icons.download_rounded,
                downloading ? '下载中' : '下载',
                enabled: !downloading,
              ),
            ],
            child: SizedBox(
              width: 42,
              height: 44,
              child: Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_QueueSongAction> _menuItem(
    _QueueSongAction action,
    IconData icon,
    String label, {
    Color? color,
    bool enabled = true,
  }) {
    return PopupMenuItem<_QueueSongAction>(
      value: action,
      enabled: enabled,
      height: 46,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

class _PlaylistChooser extends StatelessWidget {
  const _PlaylistChooser({required this.playlists});

  static const createNew = '__create_new_playlist__';

  final List<Map<String, dynamic>> playlists;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.68,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '收藏到歌单',
                style: TextStyle(fontSize: 17, fontWeight: TypeScale.bold),
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.add_rounded, color: scheme.primary),
            title: Text(
              '新建歌单',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: TypeScale.semibold,
              ),
            ),
            onTap: () => Navigator.of(context).pop(createNew),
          ),
          if (playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                '还没有歌单',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  final name =
                      (playlist['name'] ?? playlist['title'] ?? '未命名歌单')
                          .toString();
                  final count = (playlist['trackCount'] as num?)?.toInt();
                  return ListTile(
                    leading: const Icon(Icons.queue_music_rounded),
                    title: Text(name),
                    subtitle: count == null ? null : Text('$count 首歌曲'),
                    onTap: () => Navigator.of(context).pop(playlist),
                  );
                },
              ),
            ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建歌单'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: '歌单名称'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (value) {
          final name = value.trim();
          if (name.isNotEmpty) Navigator.of(context).pop(name);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('创建'),
        ),
      ],
    );
  }
}
