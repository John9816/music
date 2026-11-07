import 'package:flutter/material.dart';

import '../../core/api/artist_info_api.dart';
import '../../core/api/music_api.dart';
import '../../core/models/artist_info.dart';
import '../../core/models/song.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import 'artist_detail_view.dart';

typedef ArtistInfoLoader = Future<ArtistInfo> Function();

final Map<String, Future<ArtistInfo>> _artistInfoCache = {};

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
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选择歌手',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: available.length,
                  itemBuilder: (_, index) {
                    final item = available[index];
                    return GListTile(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      leading: _ArtistAvatar(artist: item),
                      title: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Theme.of(sheetContext).colorScheme.outline,
                      ),
                      onTap: () => Navigator.of(sheetContext).pop(item),
                    );
                  },
                ),
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

class _ArtistAvatar extends StatelessWidget {
  const _ArtistAvatar({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final initialUrl = artist.picUrl;
    if (initialUrl != null && initialUrl.isNotEmpty) {
      return AsyncCover(url: initialUrl, size: 48, radius: 8);
    }
    final key = artist.name.trim().toLowerCase();
    final future = _artistInfoCache.putIfAbsent(
      key,
      () => ArtistInfoApi().getArtistInfo(artist.name),
    );
    return FutureBuilder<ArtistInfo>(
      future: future,
      builder: (context, snapshot) => AsyncCover(
        url: snapshot.data?.imageUrl,
        size: 48,
        radius: 8,
      ),
    );
  }
}

List<Artist> _availableArtists(List<Artist> artists) {
  final seen = <String>{};
  return artists.where((artist) {
    final name = artist.name.trim();
    if (name.isEmpty || name == '未知' || name == '未知歌手') return false;
    return seen.add(name);
  }).toList();
}
