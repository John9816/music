import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import '../settings/settings_controller.dart';

enum CacheCategory { songs, images, lyrics, pageData }

class CacheSnapshot {
  const CacheSnapshot({required this.bytesByCategory});

  final Map<CacheCategory, int> bytesByCategory;

  int bytesFor(CacheCategory category) => bytesByCategory[category] ?? 0;
  int get totalBytes =>
      bytesByCategory.values.fold(0, (total, value) => total + value);
}

/// 应用缓存与下载目录管理。
///
/// 下载内容位于 Documents，永远不会被缓存清理误删。歌曲缓存、图片、歌词
/// 和页面数据位于应用临时目录，可独立统计和清理。
class CacheService {
  static final CacheService instance = CacheService._(
    temporaryDirectory: getTemporaryDirectory,
    documentsDirectory: getApplicationDocumentsDirectory,
  );

  CacheService._({
    required Future<Directory> Function() temporaryDirectory,
    required Future<Directory> Function() documentsDirectory,
  })  : _temporaryDirectory = temporaryDirectory,
        _documentsDirectory = documentsDirectory;

  @visibleForTesting
  factory CacheService.forTesting({
    required Future<Directory> Function() temporaryDirectory,
    required Future<Directory> Function() documentsDirectory,
  }) = CacheService._;

  final Future<Directory> Function() _temporaryDirectory;
  final Future<Directory> Function() _documentsDirectory;

  static const int automaticLimitBytes = 2 * 1024 * 1024 * 1024;

  Future<Directory> _temporaryBase() => _temporaryDirectory();

  Future<Directory> get appCacheDirectory async {
    final base = await _temporaryBase();
    final directory = Directory('${base.path}/duck_music_cache');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> get audioCacheDirectory async {
    final base = await appCacheDirectory;
    final directory = Directory('${base.path}/songs');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> get downloadsDirectory async {
    final base = await _documentsDirectory();
    final directory = Directory('${base.path}/DuckMusic Downloads');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> audioFileFor(Song song, String quality) async {
    final directory = await audioCacheDirectory;
    final key = '${song.source}_${song.id}_$quality'
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${directory.path}/$key.audio');
  }

  Future<int> totalSizeBytes() async => (await snapshot()).totalBytes;

  Future<CacheSnapshot> snapshot() async {
    final base = await appCacheDirectory;
    final totals = <CacheCategory, int>{
      for (final category in CacheCategory.values) category: 0,
    };
    if (!await base.exists()) return CacheSnapshot(bytesByCategory: totals);
    await for (final entity in base.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final category = _categoryFor(entity.path);
        totals[category] = (totals[category] ?? 0) + await entity.length();
      } catch (_) {}
    }
    return CacheSnapshot(bytesByCategory: totals);
  }

  Future<void> clearCategory(CacheCategory category) async {
    final base = await appCacheDirectory;
    if (!await base.exists()) return;
    await for (final entity in base.list(recursive: true, followLinks: false)) {
      if (entity is! File || _categoryFor(entity.path) != category) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  Future<void> clearAll() async {
    for (final category in CacheCategory.values) {
      await clearCategory(category);
    }
  }

  Future<int> downloadsSizeBytes() async {
    final directory = await downloadsDirectory;
    return _directorySize(directory);
  }

  Future<void> clearDownloads() async {
    final directory = await downloadsDirectory;
    await for (final entity in directory.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> maintainAudioCache(SettingsController settings) async {
    final directory = await audioCacheDirectory;
    final files = <({File file, FileStat stat})>[];
    final cutoff = DateTime.now().subtract(
      Duration(days: settings.audioCacheValidityDays),
    );
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        } else {
          files.add((file: entity, stat: stat));
        }
      } catch (_) {}
    }

    final limit = settings.audioCacheLimitBytes == 0
        ? automaticLimitBytes
        : settings.audioCacheLimitBytes;
    var total = files.fold<int>(0, (sum, item) => sum + item.stat.size);
    if (total <= limit) return;
    files.sort((a, b) => a.stat.accessed.compareTo(b.stat.accessed));
    for (final item in files) {
      if (total <= limit) break;
      try {
        await item.file.delete();
        total -= item.stat.size;
      } catch (_) {}
    }
  }

  CacheCategory _categoryFor(String path) {
    final normalized = path.toLowerCase();
    if (normalized.contains('/duck_music_cache/songs/') ||
        normalized.endsWith('.audio') ||
        normalized.endsWith('.mp3') ||
        normalized.endsWith('.flac') ||
        normalized.endsWith('.m4a') ||
        normalized.endsWith('.aac')) {
      return CacheCategory.songs;
    }
    if (normalized.endsWith('.png') ||
        normalized.endsWith('.jpg') ||
        normalized.endsWith('.jpeg') ||
        normalized.endsWith('.webp') ||
        normalized.contains('imagecache') ||
        normalized.contains('cachedimage')) {
      return CacheCategory.images;
    }
    if (normalized.endsWith('.lrc') || normalized.contains('/lyrics/')) {
      return CacheCategory.lyrics;
    }
    return CacheCategory.pageData;
  }

  Future<int> _directorySize(Directory directory) async {
    var total = 0;
    if (!await directory.exists()) return total;
    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        total += await entity.length();
      } catch (_) {}
    }
    return total;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
