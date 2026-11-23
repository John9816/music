import 'dart:convert';
import 'dart:io';

import 'package:duck_music/core/models/book_content.dart';
import 'package:duck_music/features/books/book_offline_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory base;
  late BookOfflineCache cache;
  String session = 'user-A';

  setUp(() async {
    base = await Directory.systemTemp.createTemp('book_offline_test_');
    session = 'user-A';
    cache = BookOfflineCache.forTesting(
      documentsDirectory: () async => base,
      sessionId: () async => session,
    );
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  const content = BookContent(
    title: '第一章',
    text: '这是缓存的正文内容，用于验证离线读取。',
    chapterUrl: 'https://example.com/chapter/1',
  );

  test('写入后可原样读回，并计入缓存数量', () async {
    final key = cache.chapterCacheKey('src', 'book-url', 'ch-1');
    expect(await cache.readChapter(key), isNull);

    expect(await cache.writeChapter(key, content), isTrue);

    final cached = await cache.readChapter(key);
    expect(cached, isNotNull);
    expect(cached!.title, content.title);
    expect(cached.text, content.text);
    expect(await cache.countChapters(), 1);
    expect((await cache.cachedKeys()), contains(key));
  });

  test('不同账号之间缓存隔离，切换 session 读不到彼此数据', () async {
    final key = cache.chapterCacheKey('src', 'book-url', 'ch-1');
    await cache.writeChapter(key, content);

    session = 'user-B';
    expect(await cache.readChapter(key), isNull);
    expect(await cache.countChapters(), 0);

    session = 'user-A';
    expect((await cache.readChapter(key))?.text, content.text);
  });

  test('过期条目读取时返回 null 并被清除', () async {
    final key = cache.chapterCacheKey('src', 'book-url', 'ch-1');
    await cache.writeChapter(key, content);

    // 直接改写索引里的 expiresAt 为过去，模拟 30 天过期。
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}duck_music'
      '${Platform.pathSeparator}reading_offline',
    );
    final entities = await dir.list().toList();
    final sessionDir = entities.whereType<Directory>().first;
    final indexFile = File(
      '${sessionDir.path}${Platform.pathSeparator}index.json',
    );
    final index = jsonDecode(await indexFile.readAsString()) as Map;
    (index[key] as Map)['expiresAt'] = DateTime.now()
        .millisecondsSinceEpoch - 1000;
    await indexFile.writeAsString(jsonEncode(index));

    expect(await cache.readChapter(key), isNull);
    expect(await cache.countChapters(), 0);
    expect((await cache.cachedKeys()), isEmpty);
  });

  test('超过 64MB 时按最近访问时间淘汰最旧条目', () async {
    final keyNew = cache.chapterCacheKey('src', 'b', 'ch-new');
    final keyOld = cache.chapterCacheKey('src', 'b', 'ch-old');
    await cache.writeChapter(keyNew, content);
    await cache.writeChapter(keyOld, content);

    // 构造索引：old 访问时间更早，且两者 size 之和超过 64MB，
    // 再写入一个正常条目触发淘汰。
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}duck_music'
      '${Platform.pathSeparator}reading_offline',
    );
    final sessionDir = (await dir.list().toList()).whereType<Directory>().first;
    final indexFile = File(
      '${sessionDir.path}${Platform.pathSeparator}index.json',
    );
    final index = jsonDecode(await indexFile.readAsString()) as Map;
    final now = DateTime.now().millisecondsSinceEpoch;
    (index[keyNew] as Map)['lastAccessedAt'] = now;
    (index[keyNew] as Map)['size'] = 40 * 1024 * 1024;
    (index[keyOld] as Map)['lastAccessedAt'] = now - 100000;
    (index[keyOld] as Map)['size'] = 30 * 1024 * 1024;
    await indexFile.writeAsString(jsonEncode(index));

    // 写入第三章触发 _evict：总量 ~70MB 超限，最旧的 old 应被淘汰。
    await cache.writeChapter(
      cache.chapterCacheKey('src', 'b', 'ch-3'),
      content,
    );
    final keys = await cache.cachedKeys();
    expect(keys, contains(keyNew));
    expect(keys, isNot(contains(keyOld)));
  });

  test('清空缓存只移除当前账号条目', () async {
    await cache.writeChapter(
      cache.chapterCacheKey('src', 'b', 'ch-1'),
      content,
    );
    await cache.writeChapter(
      cache.chapterCacheKey('src', 'b', 'ch-2'),
      content,
    );
    expect(await cache.countChapters(), 2);

    expect(await cache.clearMyCache(), 2);
    expect(await cache.countChapters(), 0);
  });

  test('目录不可用时全部操作降级为 fail-soft，不抛异常', () async {
    // 指向一个FilePath风格的文件而非目录，迫使目录创建失败。
    final blocker = File('${base.path}${Platform.pathSeparator}blocker');
    await blocker.writeAsString('not a dir');
    final broken = BookOfflineCache.forTesting(
      documentsDirectory: () async => Directory(blocker.path),
      sessionId: () async => 'user-A',
    );

    final key = broken.chapterCacheKey('src', 'b', 'ch');
    expect(await broken.readChapter(key), isNull);
    expect(await broken.writeChapter(key, content), isFalse);
    expect(await broken.countChapters(), 0);
    expect(await broken.cachedKeys(), isEmpty);
    expect(await broken.clearMyCache(), 0);
  });
}
