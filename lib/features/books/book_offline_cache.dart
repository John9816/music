import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/book_content.dart';

/// 章节正文离线缓存。
///
/// 与 Web 端 bookCache.ts 对齐：持久化的索引 + 逐章正文文件，每章 30 天 TTL、
/// 总量 64MB 上限按最近访问时间 LRU 淘汰、按登录账号隔离（切号不串数据），
/// 全程 fail-soft（无权限 / 磁盘满 / 隐私模式一律降级为「无缓存」而不影响在线阅读）。
///
/// 目录位于 Documents 而非临时目录，不会被缓存清理误删，与「下载」同级别持久。
class BookOfflineCache {
  BookOfflineCache._({
    required Future<Directory> Function() documentsDirectory,
    required Future<String> Function() sessionId,
  })  : _documentsDirectory = documentsDirectory,
        _sessionId = sessionId;

  static final BookOfflineCache instance = BookOfflineCache._(
    documentsDirectory: getApplicationDocumentsDirectory,
    sessionId: _defaultSessionId,
  );

  /// 供单元测试注入临时目录与固定 session，避免依赖平台通道。
  @visibleForTesting
  factory BookOfflineCache.forTesting({
    required Future<Directory> Function() documentsDirectory,
    required Future<String> Function() sessionId,
  }) = BookOfflineCache._;

  /// 与 AuthController._userIdKey 保持一致；未登录用户归到 guest。
  static const _authUserIdKey = 'auth_user_id';
  static const _ttlMs = 30 * 24 * 60 * 60 * 1000; // 30 天
  static const _maxBytes = 64 * 1024 * 1024; // 64 MB
  static const _indexName = 'index.json';
  static const _namespace = 'reading_offline';

  final Future<Directory> Function() _documentsDirectory;
  final Future<String> Function() _sessionId;

  static Future<String> _defaultSessionId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_authUserIdKey)?.trim();
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    return 'guest';
  }

  /// 串行化索引读写，避免批量缓存时写冲突。
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Directory> _dir() async {
    final docs = await _documentsDirectory();
    final session = await _sessionId();
    final sessionHash = md5.convert(utf8.encode(session)).toString();
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}duck_music'
      '${Platform.pathSeparator}$_namespace'
      '${Platform.pathSeparator}$sessionHash',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String chapterCacheKey(String sourceId, String bookUrl, String chapterUrl) =>
      '$sourceId::$bookUrl::$chapterUrl';

  File _indexFile(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}$_indexName');

  String _fileName(String key) => '${md5.convert(utf8.encode(key)).toString()}.json';

  Future<Map<String, dynamic>> _readIndex(Directory dir) async {
    try {
      final file = _indexFile(dir);
      if (!await file.exists()) return <String, dynamic>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeIndex(Directory dir, Map<String, dynamic> entries) async {
    try {
      final file = _indexFile(dir);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(entries), flush: true);
      await tmp.rename(file.path);
    } catch (_) {}
  }

  /// 读取缓存章节；命中时刷新 LRU 时间戳，过期条目就地清除。
  Future<BookContent?> readChapter(String key) => _serial(() async {
    try {
      final dir = await _dir();
      final entries = await _readIndex(dir);
      final raw = entries[key];
      if (raw is! Map) return null;
      final now = DateTime.now().millisecondsSinceEpoch;
      final expiry = raw['expiresAt'];
      if (expiry is! int || now > expiry) {
        await _removeEntry(dir, entries, key);
        return null;
      }
      final file = File(
        '${dir.path}${Platform.pathSeparator}${_fileName(key)}',
      );
      if (!await file.exists()) {
        await _removeEntry(dir, entries, key);
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final content = BookContent.fromJson(Map<String, dynamic>.from(decoded));
      if (content.text.isEmpty) return null;
      entries[key] = {...raw, 'lastAccessedAt': now};
      await _writeIndex(dir, entries);
      return content;
    } catch (_) {
      return null;
    }
  });

  /// 写入章节正文，随后执行 TTL + 64MB LRU 淘汰。
  Future<bool> writeChapter(String key, BookContent content) => _serial(() async {
    try {
      if (content.text.isEmpty) return false;
      final dir = await _dir();
      final payload = {
        'title': content.title,
        'text': content.text,
        'chapterUrl': content.chapterUrl,
      };
      final body = jsonEncode(payload);
      final size = utf8.encode(body).length;
      final file = File(
        '${dir.path}${Platform.pathSeparator}${_fileName(key)}',
      );
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(body, flush: true);
      await tmp.rename(file.path);

      final entries = await _readIndex(dir);
      final now = DateTime.now().millisecondsSinceEpoch;
      entries[key] = {
        'file': _fileName(key),
        'size': size,
        'savedAt': now,
        'expiresAt': now + _ttlMs,
        'lastAccessedAt': now,
      };
      await _evict(dir, entries);
      await _writeIndex(dir, entries);
      return true;
    } catch (_) {
      return false;
    }
  });

  /// 当前账号已缓存、且未过期的章节 key。
  Future<Set<String>> cachedKeys() => _serial(() async {
    try {
      final dir = await _dir();
      final entries = await _readIndex(dir);
      final now = DateTime.now().millisecondsSinceEpoch;
      final keys = <String>{};
      for (final entry in entries.entries) {
        final expiry = entry.value['expiresAt'];
        if (expiry is int && now <= expiry) keys.add(entry.key);
      }
      return keys;
    } catch (_) {
      return <String>{};
    }
  });

  Future<int> countChapters() => _serial(() async {
    try {
      final dir = await _dir();
      final entries = await _readIndex(dir);
      final now = DateTime.now().millisecondsSinceEpoch;
      return entries.values
          .where((e) => e['expiresAt'] is int && now <= e['expiresAt'])
          .length;
    } catch (_) {
      return 0;
    }
  });

  /// 清空当前账号的全部离线章节缓存，返回清除的章节数。
  Future<int> clearMyCache() => _serial(() async {
    try {
      final dir = await _dir();
      final entries = await _readIndex(dir);
      final count = entries.length;
      for (final value in entries.values) {
        final name = value['file'];
        if (name is! String) continue;
        try {
          final file = File('${dir.path}${Platform.pathSeparator}$name');
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      await _writeIndex(dir, <String, dynamic>{});
      return count;
    } catch (_) {
      return 0;
    }
  });

  Future<void> _removeEntry(
    Directory dir,
    Map<String, dynamic> entries,
    String key,
  ) async {
    final raw = entries.remove(key);
    if (raw is Map && raw['file'] is String) {
      try {
        final file = File(
          '${dir.path}${Platform.pathSeparator}${raw['file']}',
        );
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _writeIndex(dir, entries);
  }

  Future<void> _evict(Directory dir, Map<String, dynamic> entries) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1) 过期条目
    final expired = <String>[];
    for (final entry in entries.entries) {
      final expiry = entry.value['expiresAt'];
      if (expiry is! int || now > expiry) expired.add(entry.key);
    }
    for (final key in expired) {
      final raw = entries.remove(key);
      if (raw is Map && raw['file'] is String) {
        try {
          final file = File(
            '${dir.path}${Platform.pathSeparator}${raw['file']}',
          );
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }

    // 2) 超过 64MB 后按最近访问时间淘汰
    int total = entries.values.fold<int>(
      0,
      (sum, e) => sum + (e['size'] is int ? e['size'] as int : 0),
    );
    if (total <= _maxBytes) return;
    final sorted = entries.entries.toList()
      ..sort((a, b) {
        final at = a.value['lastAccessedAt'];
        final bt = b.value['lastAccessedAt'];
        return (at is int ? at : 0).compareTo(bt is int ? bt : 0);
      });
    for (final entry in sorted) {
      if (total <= _maxBytes) break;
      final raw = entry.value;
      final name = raw['file'];
      if (name is String) {
        try {
          final file = File('${dir.path}${Platform.pathSeparator}$name');
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      total -= raw['size'] is int ? raw['size'] as int : 0;
      entries.remove(entry.key);
    }
  }
}
