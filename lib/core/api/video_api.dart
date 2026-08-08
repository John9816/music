import '../models/video.dart';
import '../models/video_source.dart';
import 'api_client.dart';

/// Video catalog and playback API used by the video tools flow.
class VideoApi {
  VideoApi({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<List<VideoSource>> sources() async {
    final data = await _client.getJson('api/v1/videos/sources');
    final raw = data['list'] ?? data['sources'];
    if (raw is! List) return const <VideoSource>[];
    return raw
        .whereType<Map>()
        .map((item) => VideoSource.fromJson(Map<String, dynamic>.from(item)))
        .where((source) => source.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<VideoCategory>> categories({String? source}) async {
    final data = await _client.getJson(
      'api/v1/videos/categories',
      params: _sourceParams(source),
    );
    final raw = data['list'] ?? data['categories'];
    if (raw is! List) return const <VideoCategory>[];
    return raw
        .whereType<Map>()
        .map((item) => VideoCategory.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<VideoFilter> filters({String? source}) async {
    final data = await _client.getJson(
      'api/v1/videos/filters',
      params: _sourceParams(source),
    );
    return VideoFilter.fromJson(data);
  }

  Future<VideoPage> discover({
    String? source,
    String? category,
    String? year,
    String? region,
    String? genre,
    String? order,
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.getJson(
      'api/v1/videos/discover',
      params: {
        ..._sourceParams(source),
        if (category != null && category.isNotEmpty) 'category': category,
        if (year != null && year.isNotEmpty) 'year': year,
        if (region != null && region.isNotEmpty) 'region': region,
        if (genre != null && genre.isNotEmpty) 'genre': genre,
        if (order != null && order.isNotEmpty) 'order': order,
        'page': '$page',
        'pageSize': '$pageSize',
      },
    );
    return VideoPage.fromJson(data);
  }

  Future<VideoSearchPage> search(
    String keyword, {
    String? source,
    String? category,
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.getJson(
      'api/v1/videos/search',
      params: {
        ..._sourceParams(source),
        'keyword': keyword,
        if (category != null && category.isNotEmpty) 'category': category,
        'page': '$page',
        'pageSize': '$pageSize',
      },
    );
    return VideoSearchPage.fromJson(data);
  }

  Future<VideoDetail> detail(String videoId, {String? source}) async {
    final data = await _client.getJson(
      'api/v1/videos/$videoId/detail',
      params: _sourceParams(source),
    );
    return VideoDetail.fromJson(data);
  }

  Future<VideoPlay> play(
    String videoId, {
    String? source,
    String? episode,
    String? line,
  }) async {
    final params = <String, String>{
      if (episode != null && episode.isNotEmpty) 'episode': episode,
      if (line != null && line.isNotEmpty) 'line': line,
    };
    final data = await _client.getJson(
      'api/v1/videos/$videoId/play',
      params: params.isEmpty ? _sourceParams(source) : {..._sourceParams(source), ...params},
    );
    return VideoPlay.fromJson(data);
  }

  Map<String, String> _sourceParams(String? source) {
    final value = source?.trim();
    return value == null || value.isEmpty ? const {} : {'source': value};
  }
}
