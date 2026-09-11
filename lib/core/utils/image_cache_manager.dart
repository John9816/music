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
}
