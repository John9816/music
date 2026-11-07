import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_cache_manager/flutter_cache_manager.dart' as cache;

/// 自定义图片缓存管理器
///
/// 优化策略：
/// - 缓存期限：7 天（平衡存储空间和网络请求）
/// - 最大缓存数：200 张图片（约 50-100MB）
/// - 提供预加载功能减少首次加载时间
class ImageCacheManager {
  static const key = 'duckMusicImageCache';

  static cache.CacheManager? _instance;

  /// 获取单例实例
  static cache.CacheManager get instance {
    _instance ??= _CoverCacheManager(
      cache.Config(
        key,
        stalePeriod: const Duration(days: 7),
        maxNrOfCacheObjects: 200,
        repo: cache.JsonCacheInfoRepository(databaseName: key),
        fileService: cache.HttpFileService(),
      ),
    );
    return _instance!;
  }

  /// 预加载封面图列表
  ///
  /// [urls] 图片 URL 列表
  /// [limit] 预加载数量限制（默认 10）
  static Future<void> preloadCovers(
    List<String?> urls, {
    int limit = 10,
  }) async {
    final validUrls =
        urls.where((url) => url != null && url.isNotEmpty).take(limit).toList();

    // 并发预加载，但不等待完成（避免阻塞）
    for (final url in validUrls) {
      instance.downloadFile(url!).ignore();
    }
  }

  /// 清理过期缓存
  static Future<void> cleanCache() async {
    await instance.emptyCache();
  }

  /// 获取缓存统计信息
  static Future<Map<String, dynamic>> getCacheStats() async {
    try {
      await instance.getFileFromCache('');
      // 简化实现：只返回是否有缓存，不计算详细大小
      return {
        'enabled': true,
        'message': 'Cache manager is active',
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}

class _CoverCacheManager extends cache.CacheManager
    with cache.ImageCacheManager {
  _CoverCacheManager(super.config);

  final _resizing = <String, Stream<cache.FileResponse>>{};

  @override
  Stream<cache.FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) async* {
    if (maxWidth == null && maxHeight == null) {
      yield* getFileStream(url,
          key: key, headers: headers, withProgress: withProgress);
      return;
    }
    final originalKey = key ?? url;
    final resizedKey = 'resized'
        '${maxWidth == null ? '' : '_w$maxWidth'}'
        '${maxHeight == null ? '' : '_h$maxHeight'}_$originalKey';
    // Every subscriber receives the existing artwork, including subscribers
    // that arrive after a shared refresh has already started.
    final cached = await getFileFromCache(resizedKey);
    if (cached != null) {
      yield cached;
      if (cached.validTill.isAfter(DateTime.now())) return;
    }
    final refresh = _resizing.putIfAbsent(
      resizedKey,
      () => _resizeStream(
        url,
        originalKey,
        resizedKey,
        headers,
        maxWidth,
        maxHeight,
      ).asBroadcastStream(),
    );
    var hasArtwork = cached != null;
    try {
      await for (final response in refresh) {
        if (response is cache.FileInfo) hasArtwork = true;
        if (response is! cache.DownloadProgress ||
            (withProgress && !hasArtwork)) {
          yield response;
        }
      }
    } on Object {
      // A failed background refresh must not replace already decoded artwork
      // with an error. An initial failure still reaches the retry control.
      if (!hasArtwork) rethrow;
    }
  }

  Stream<cache.FileResponse> _resizeStream(
    String url,
    String originalKey,
    String resizedKey,
    Map<String, String>? headers,
    int? maxWidth,
    int? maxHeight,
  ) async* {
    try {
      await for (final response in getFileStream(
        url,
        key: originalKey,
        headers: headers,
        withProgress: true,
      )) {
        yield response is cache.FileInfo
            ? await _resizeFile(response, resizedKey, maxWidth, maxHeight)
            : response;
      }
    } finally {
      // The broadcast stream finishes even when a codec listener cancels on
      // error, so failed requests can never be reused by a later retry.
      _resizing.remove(resizedKey);
    }
  }

  Future<cache.FileInfo> _resizeFile(
    cache.FileInfo original,
    String resizedKey,
    int? maxWidth,
    int? maxHeight,
  ) async {
    final extension = original.file.path.split('.').last.toLowerCase();
    final canResize =
        const {'jpg', 'jpeg', 'png', 'tga', 'cur', 'ico'}.contains(extension);
    var bytes = await original.file.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      // Keep animated formats in their original encoding. Decoding a frame
      // validates the bytes before they can replace usable cached artwork.
      final scale = canResize
          ? math.min(
              1.0,
              math.min(
                maxWidth == null ? 1.0 : maxWidth / descriptor.width,
                maxHeight == null ? 1.0 : maxHeight / descriptor.height,
              ),
            )
          : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      var outputExtension = extension;
      if (scale < 1) {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('封面缩放失败');
        bytes = data.buffer.asUint8List();
        outputExtension = 'png';
      }
      // Every format needs the same cache key contract so a late subscriber
      // can display it while the shared refresh is still pending. Small and
      // animated originals retain their bytes, encoding, and expiration.
      final file = await putFile(
        original.originalUrl,
        bytes,
        key: resizedKey,
        maxAge: original.validTill.difference(DateTime.now()),
        fileExtension: outputExtension,
      );
      return cache.FileInfo(
          file, original.source, original.validTill, original.originalUrl,
          statusCode: original.statusCode);
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
