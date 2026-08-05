import 'package:flutter/material.dart';

import '../../core/api/music_api.dart';
import '../../core/models/artist_info.dart';
import '../../core/models/song.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import 'artist_detail_view.dart';

typedef ArtistInfoLoader = Future<ArtistInfo> Function();

/// 可点击的歌手名称。多歌手时先选择歌手，再进入资料页。
class ArtistNamesLink extends StatelessWidget {
  const ArtistNamesLink({
    super.key,
    required this.artists,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
    this.source = 'netease',
    this.loader,
    this.catalogLoader,
  });

  final List<Artist> artists;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;
  final String source;
  final ArtistInfoLoader? loader;
  final Future<ArtistCatalog> Function()? catalogLoader;

  @override
  Widget build(BuildContext context) {
    final available = _availableArtists(artists);
    final names = artists.map((artist) => artist.name).join(' / ');
    final enabled = available.isNotEmpty;

    return Semantics(
      button: enabled,
      enabled: enabled,
      label: enabled ? '查看$names的歌手信息' : names,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () => openArtistInfo(
                  context,
                  artists: available,
                  source: source,
                  loader: loader,
                  catalogLoader: catalogLoader,
                )
            : null,
        child: Text(
          names,
          maxLines: maxLines,
          overflow: overflow,
          textAlign: textAlign,
          style: style,
        ),
      ),
    );
  }
}

Future<void> openArtistInfo(
  BuildContext context, {
  required List<Artist> artists,
  String source = 'netease',
  String? artistId,
  int? initialTrackCount,
  ArtistInfoLoader? loader,
  Future<ArtistCatalog> Function()? catalogLoader,
}) async {
  final available = _availableArtists(artists);
  if (available.isEmpty) return;

  final Artist? artist;
  if (available.length == 1) {
    artist = available.first;
  } else {
    artist = await showModalBottomSheet<Artist>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选择歌手',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              for (final item in available)
                GListTile(
                  leading: ClipOval(
                    child: AsyncCover(
                      url: item.picUrl,
                      size: 42,
                      radius: 21,
                    ),
                  ),
                  title: Text(item.name),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                  onTap: () => Navigator.of(sheetContext).pop(item),
                ),
            ],
          ),
        ),
      ),
    );
  }

  if (artist == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ArtistDetailView(
        artistName: artist!.name,
        artistId: artistId ?? (artist.id == 0 ? null : '${artist.id}'),
        source: source,
        initialImageUrl: artist.picUrl,
        initialTrackCount: initialTrackCount,
        loader: loader,
        catalogLoader: catalogLoader,
      ),
    ),
  );
}

List<Artist> _availableArtists(List<Artist> artists) {
  final seen = <String>{};
  return artists.where((artist) {
    final name = artist.name.trim();
    if (name.isEmpty || name == '未知' || name == '未知歌手') return false;
    return seen.add(name);
  }).toList();
}
