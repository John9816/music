import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/live_tv.dart';
import '../services/live_m3u_parser.dart';

abstract class LiveTvCacheStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesLiveTvCacheStore implements LiveTvCacheStore {
  static const String _cacheKey = 'live_tv_last_known_good_m3u';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_cacheKey);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_cacheKey, value);
  }
}

class LiveTvLoadException implements Exception {
  const LiveTvLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LiveTvApi {
  LiveTvApi({
    http.Client? client,
    LiveTvCacheStore? cacheStore,
    LiveM3uParser parser = const LiveM3uParser(),
    this.requestTimeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _cacheStore = cacheStore ?? SharedPreferencesLiveTvCacheStore(),
        _parser = parser;

  final http.Client _client;
  final LiveTvCacheStore _cacheStore;
  final LiveM3uParser _parser;
  final Duration requestTimeout;

  Future<LiveTvCatalog?> readCached() async {
    final rawM3u = await _cacheStore.read();
    if (rawM3u == null || rawM3u.trim().isEmpty) return null;
    try {
      return _parser.parse(rawM3u);
    } on FormatException {
      return null;
    }
  }

  Future<LiveTvCatalog> refresh() async {
    late http.Response response;
    try {
      response = await _client.get(
        Uri.parse(AppConfig.liveTvM3uUrl),
        headers: const {
          'Accept': 'application/x-mpegURL, audio/mpegurl, text/plain, */*',
          'Cache-Control': 'no-cache',
        },
      ).timeout(requestTimeout);
    } on TimeoutException {
      throw const LiveTvLoadException('直播源请求超时');
    } catch (_) {
      throw const LiveTvLoadException('直播源暂时不可用');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LiveTvLoadException('直播源请求失败 (${response.statusCode})');
    }

    final rawM3u = utf8.decode(response.bodyBytes, allowMalformed: true);
    late LiveTvCatalog catalog;
    try {
      catalog = _parser.parse(rawM3u);
    } on FormatException {
      throw const LiveTvLoadException('直播源格式无效');
    }
    await _cacheStore.write(rawM3u);
    return catalog;
  }
}
