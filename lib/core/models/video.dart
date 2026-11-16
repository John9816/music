class VideoSearchPage {
  const VideoSearchPage({
    required this.list,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.hasMore,
    this.sourceId,
    this.sourceName,
  });

  factory VideoSearchPage.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'];
    final list = rawList is List
        ? rawList
            .whereType<Map>()
            .map((item) => VideoItem.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <VideoItem>[];
    final page = _intValue(json['page'], fallback: 1);
    final pageSize = _intValue(json['pageSize'], fallback: 20);
    final total = _intValue(json['total']);
    return VideoSearchPage(
      list: list,
      page: page,
      pageSize: pageSize,
      total: total,
      hasMore: json['hasMore'] == true ||
          (total > 0 && pageSize > 0 && page * pageSize < total),
      sourceId: _sourceId(json),
      sourceName: _sourceName(json),
    );
  }

  final List<VideoItem> list;
  final int page;
  final int pageSize;
  final int total;
  final bool hasMore;
  final String? sourceId;
  final String? sourceName;
}

class VideoPage {
  const VideoPage({
    required this.list,
    required this.total,
    this.page = 1,
    this.pageSize = 20,
    this.hasMore = false,
    this.sourceId,
    this.sourceName,
  });

  factory VideoPage.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'];
    final list = rawList is List
        ? rawList
            .whereType<Map>()
            .map((item) => VideoItem.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <VideoItem>[];
    final page = _intValue(json['page'], fallback: 1);
    final pageSize = _intValue(json['pageSize'], fallback: 20);
    final total = _intValue(json['total']);
    return VideoPage(
      list: list,
      total: total,
      page: page,
      pageSize: pageSize,
      hasMore: json['hasMore'] == true ||
          (total > 0 && pageSize > 0 && page * pageSize < total),
      sourceId: _sourceId(json),
      sourceName: _sourceName(json),
    );
  }

  final List<VideoItem> list;
  final int total;
  final int page;
  final int pageSize;
  final bool hasMore;
  final String? sourceId;
  final String? sourceName;
}

class VideoCategory {
  const VideoCategory({
    required this.id,
    required this.name,
    this.url,
    this.sourceId,
    this.sourceName,
  });

  factory VideoCategory.fromJson(Map<String, dynamic> json) => VideoCategory(
        id: '${json['id'] ?? json['value'] ?? ''}',
        name: '${json['name'] ?? json['title'] ?? ''}',
        url: _stringValue(json['url']),
        sourceId: _sourceId(json),
        sourceName: _sourceName(json),
      );

  final String id;
  final String name;
  final String? url;
  final String? sourceId;
  final String? sourceName;
}

class VideoFilter {
  const VideoFilter({
    this.years = const <String>[],
    this.regions = const <String>[],
    this.genres = const <String>[],
    this.orders = const <String>[],
    this.sourceId,
    this.sourceName,
  });

  factory VideoFilter.fromJson(Map<String, dynamic> json) => VideoFilter(
        years: _stringList(json['years']),
        regions: _stringList(json['regions']),
        genres: _stringList(json['genres']),
        orders: _stringList(json['orders']),
        sourceId: _sourceId(json),
        sourceName: _sourceName(json),
      );

  final List<String> years;
  final List<String> regions;
  final List<String> genres;
  final List<String> orders;
  final String? sourceId;
  final String? sourceName;
}

class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    this.posterUrl,
    this.detailUrl,
    this.status = '',
    this.description = '',
    this.sourceId,
    this.sourceName,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? json['name'] ?? ''}',
        posterUrl: _stringValue(json['posterUrl'] ?? json['poster']),
        detailUrl: _stringValue(json['detailUrl']),
        status: _textValue(json['status']),
        description: _textValue(json['description']),
        sourceId: _sourceId(json),
        sourceName: _sourceName(json),
      );

  final String id;
  final String title;
  final String? posterUrl;
  final String? detailUrl;
  final String status;
  final String description;
  final String? sourceId;
  final String? sourceName;
}

class VideoTag {
  const VideoTag({required this.name});

  factory VideoTag.fromJson(Object? value) {
    if (value is Map) {
      final json = Map<String, dynamic>.from(value);
      return VideoTag(
        name: _textValue(
            json['name'] ?? json['title'] ?? json['label'] ?? json['text']),
      );
    }
    return VideoTag(name: _textValue(value));
  }

  final String name;

  @override
  String toString() => name;
}

class VideoDetail extends VideoItem {
  const VideoDetail({
    required super.id,
    required super.title,
    super.posterUrl,
    super.detailUrl,
    super.status,
    super.description,
    super.sourceId,
    super.sourceName,
    required this.episodes,
    this.lines = const <VideoLine>[],
    this.tags = const <VideoTag>[],
  });

  factory VideoDetail.fromJson(Map<String, dynamic> json) {
    final rawEpisodes = json['episodes'];
    final rawLines = json['lines'];
    return VideoDetail(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? json['name'] ?? ''}',
      posterUrl: _stringValue(json['posterUrl'] ?? json['poster']),
      detailUrl: _stringValue(json['detailUrl']),
      status: _textValue(json['status']),
      description: _textValue(json['description']),
      sourceId: _sourceId(json),
      sourceName: _sourceName(json),
      tags: _videoTags(json['tags']),
      lines: rawLines is List
          ? rawLines
              .whereType<Map>()
              .map(
                  (item) => VideoLine.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const <VideoLine>[],
      episodes: rawEpisodes is List
          ? rawEpisodes
              .whereType<Map>()
              .map((item) =>
                  VideoEpisode.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const <VideoEpisode>[],
    );
  }

  final List<VideoEpisode> episodes;
  final List<VideoLine> lines;
  final List<VideoTag> tags;
}

class VideoEpisode {
  const VideoEpisode({
    required this.id,
    required this.name,
    this.url,
    this.description,
  });

  factory VideoEpisode.fromJson(Map<String, dynamic> json) => VideoEpisode(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? json['title'] ?? ''}',
        url: _stringValue(json['url']),
        description: _stringValue(json['description']),
      );

  final String id;
  final String name;
  final String? url;
  final String? description;
}

class VideoLine {
  const VideoLine({required this.id, required this.name, this.description});

  factory VideoLine.fromJson(Map<String, dynamic> json) => VideoLine(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? json['title'] ?? ''}',
        description: _stringValue(json['description']),
      );

  final String id;
  final String name;
  final String? description;
}

/// Container reported by the backend for a playable URL.
///
/// The backend infers this from the URL itself and reports `unknown` when it cannot
/// tell, so anything unrecognised is still attempted instead of being refused.
enum MediaContainer {
  mp4('mp4', 'MP4'),
  hls('hls', 'HLS'),
  dash('dash', 'DASH'),
  mkv('mkv', 'MKV'),
  webm('webm', 'WebM'),
  ts('ts', 'TS'),
  flv('flv', 'FLV'),
  avi('avi', 'AVI'),
  threeGp('3gp', '3GP'),
  unknown('unknown', '未知格式'),
  unsupported('unsupported', '不支持');

  const MediaContainer(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static MediaContainer parse(Object? value) {
    switch (value?.toString().trim().toLowerCase()) {
      case 'mp4':
      case 'm4v':
      case 'mov':
      case 'f4v':
        return MediaContainer.mp4;
      case 'hls':
      case 'm3u8':
        return MediaContainer.hls;
      case 'dash':
      case 'mpd':
        return MediaContainer.dash;
      case 'mkv':
        return MediaContainer.mkv;
      case 'webm':
        return MediaContainer.webm;
      case 'ts':
      case 'm2ts':
      case 'mts':
        return MediaContainer.ts;
      case 'flv':
        return MediaContainer.flv;
      case 'avi':
        return MediaContainer.avi;
      case '3gp':
      case '3gpp':
        return MediaContainer.threeGp;
      case 'wmv':
      case 'asf':
      case 'rm':
      case 'rmvb':
      case 'vob':
      case 'ogv':
        return MediaContainer.unsupported;
      default:
        return MediaContainer.unknown;
    }
  }

  /// Legacy Windows RealMedia (.wmv/.rm/.rmvb) cannot be decoded by ExoPlayer or AVPlayer.
  bool get playableInApp => this != MediaContainer.unsupported;
}

class VideoPlayback {
  const VideoPlayback({
    required this.videoId,
    required this.episodeId,
    required this.lineId,
    required this.playable,
    this.mediaUrl,
    this.format,
    this.embedUrl,
    this.upstreamUrl,
    this.message = '',
    this.sourceId,
    this.sourceName,
  });

  factory VideoPlayback.fromJson(Map<String, dynamic> json) => VideoPlayback(
        videoId: '${json['videoId'] ?? ''}',
        episodeId: '${json['episodeId'] ?? ''}',
        lineId: '${json['lineId'] ?? ''}',
        playable: json['playable'] == true,
        mediaUrl: _stringValue(json['mediaUrl']),
        format: _stringValue(json['format']),
        embedUrl: _stringValue(json['embedUrl']),
        upstreamUrl: _stringValue(json['upstreamUrl']),
        message: _textValue(json['message']),
        sourceId: _sourceId(json),
        sourceName: _sourceName(json),
      );

  final String videoId;
  final String episodeId;
  final String lineId;
  final bool playable;
  final String? mediaUrl;
  final String? format;
  final String? embedUrl;
  final String? upstreamUrl;
  final String message;
  final String? sourceId;
  final String? sourceName;

  /// Container hint reported by the backend.
  MediaContainer get container => MediaContainer.parse(format);

  bool get isInlinePlayable {
    if (!playable) return false;
    final uri = Uri.tryParse(mediaUrl ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    final fromUrl = _containerForPath(uri.path);
    // No extension at all: trust the backend, it already resolved this to a direct URL.
    if (fromUrl == null) return container.playableInApp;
    // The URL names something no player can decode (.exe, .php, images, ...).
    if (fromUrl == MediaContainer.unsupported) return false;
    // The backend could not tell, so fall back to what the address itself says.
    if (container == MediaContainer.unknown) return fromUrl.playableInApp;
    return fromUrl == container && container.playableInApp;
  }

  /// Reason to show when [isInlinePlayable] is false but a direct URL exists.
  String get unsupportedReason {
    if (isInlinePlayable || !playable) return '';
    final url = mediaUrl;
    if (url == null || url.isEmpty) return '';
    return '该线路地址内置播放器无法解码，可换一条线路';
  }
}

/// Extensions the inline player may attempt; mirrors the backend `MediaFormat` list.
const Set<String> _mediaExtensions = {
  'm3u8', 'mp4', 'mpd', 'mkv', 'webm', 'ts', 'm2ts', 'mts', //
  'flv', 'avi', 'mov', 'm4v', 'f4v', '3gp', '3gpp', 'wmv', //
  'asf', 'rmvb', 'rm', 'vob', 'ogv',
};

/// Resolves the container named by [path].
///
/// Returns null when the path carries no extension, and [MediaContainer.unsupported]
/// when it names something that is not media at all.
MediaContainer? _containerForPath(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  final extension = name.substring(dot + 1).toLowerCase();
  if (!_mediaExtensions.contains(extension)) return MediaContainer.unsupported;
  return MediaContainer.parse(extension);
}

/// Compatibility name used by the video feature and API consumers.
typedef VideoPlay = VideoPlayback;

int _intValue(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

String? _stringValue(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _textValue(Object? value) => _stringValue(value) ?? '';

String? _sourceId(Map<String, dynamic> json) =>
    _stringValue(json['sourceId'] ?? json['source']);

String? _sourceName(Map<String, dynamic> json) =>
    _stringValue(json['sourceName'] ?? json['sourceTitle']);

List<VideoTag> _videoTags(Object? value) {
  if (value is! List) return const <VideoTag>[];
  return value
      .map(VideoTag.fromJson)
      .where((tag) => tag.name.isNotEmpty)
      .toList(growable: false);
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
