import 'dart:convert';
import 'dart:io';

import 'package:duck_music/core/services/cache_service.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TuneFreeNext settings survive controller recreation', () async {
    SharedPreferences.setMockInitialValues(const {});
    final settings = SettingsController();

    await settings.setThemeMode('light');
    await settings.setAccentColor('rosePink');
    await settings.setQuality('hires');
    await settings.setGlassQuality('detailed');
    await settings.setReduceMotion(true);
    await settings.setAutomaticAudioCache(false);
    await settings.setAudioCacheLimitBytes(5 * 1024 * 1024 * 1024);
    await settings.setAudioCacheValidityDays(90);
    await settings.setDownloadQuality('lossless');
    await settings.setStatusBarLyrics(true);
    await settings.setGlobalShortcutsEnabled(false);
    await settings.setShortcutBinding(
      'playPause',
      jsonEncode({
        'key': 'space',
        'modifiers': ['meta']
      }),
    );

    final restored = SettingsController();
    await restored.load();

    expect(restored.themeMode, ThemeMode.light);
    expect(restored.accentId, 'rosePink');
    expect(restored.quality, 'hires');
    expect(restored.glassQuality, 'detailed');
    expect(restored.reduceMotion, isTrue);
    expect(restored.automaticAudioCache, isFalse);
    expect(restored.audioCacheLimitBytes, 5 * 1024 * 1024 * 1024);
    expect(restored.audioCacheValidityDays, 90);
    expect(restored.downloadQuality, 'lossless');
    expect(restored.statusBarLyrics, isTrue);
    expect(restored.globalShortcutsEnabled, isFalse);
    expect(restored.shortcutBindings, contains('playPause'));
  });

  test('all seven TuneFreeNext accent colors build in light and dark', () {
    expect(AppAccent.all, hasLength(7));
    expect(
      AppAccent.all.map((accent) => accent.name),
      orderedEquals(const [
        '律动红',
        '落日橙',
        '森林绿',
        '湖水青',
        '天际蓝',
        '幻夜紫',
        '蔷薇粉',
      ]),
    );

    for (final accent in AppAccent.all) {
      expect(AppTheme.forAccent(accent.id, dark: false).scheme.primary,
          accent.color);
      expect(AppTheme.forAccent(accent.id, dark: true).scheme.primary,
          accent.color);
    }
  });

  test('cache categories clear only DuckMusic cache files', () async {
    final temporary = await Directory.systemTemp.createTemp('duck-cache-test-');
    final documents = await Directory.systemTemp.createTemp('duck-docs-test-');
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
      if (await documents.exists()) await documents.delete(recursive: true);
    });
    final cache = CacheService.forTesting(
      temporaryDirectory: () async => temporary,
      documentsDirectory: () async => documents,
    );
    final appCache = await cache.appCacheDirectory;
    final songs = Directory('${appCache.path}/songs')..createSync();
    final lyrics = Directory('${appCache.path}/lyrics')..createSync();
    File('${songs.path}/one.audio').writeAsBytesSync(List.filled(10, 1));
    File('${appCache.path}/cover.jpg').writeAsBytesSync(List.filled(20, 1));
    File('${lyrics.path}/one.lrc').writeAsBytesSync(List.filled(30, 1));
    File('${appCache.path}/page.json').writeAsBytesSync(List.filled(40, 1));
    final unrelated = File('${temporary.path}/keep.tmp')
      ..writeAsBytesSync(List.filled(50, 1));

    final snapshot = await cache.snapshot();
    expect(snapshot.bytesFor(CacheCategory.songs), 10);
    expect(snapshot.bytesFor(CacheCategory.images), 20);
    expect(snapshot.bytesFor(CacheCategory.lyrics), 30);
    expect(snapshot.bytesFor(CacheCategory.pageData), 40);
    expect(snapshot.totalBytes, 100);

    await cache.clearCategory(CacheCategory.images);
    expect((await cache.snapshot()).bytesFor(CacheCategory.images), 0);
    await cache.clearAll();
    expect((await cache.snapshot()).totalBytes, 0);
    expect(await unrelated.exists(), isTrue);
  });

  test('downloads remain outside cache clearing', () async {
    final temporary = await Directory.systemTemp.createTemp('duck-cache-test-');
    final documents = await Directory.systemTemp.createTemp('duck-docs-test-');
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
      if (await documents.exists()) await documents.delete(recursive: true);
    });
    final cache = CacheService.forTesting(
      temporaryDirectory: () async => temporary,
      documentsDirectory: () async => documents,
    );
    final downloads = await cache.downloadsDirectory;
    final song = File('${downloads.path}/download.flac')
      ..writeAsBytesSync(List.filled(64, 1));

    await cache.clearAll();

    expect(await song.exists(), isTrue);
    expect(await cache.downloadsSizeBytes(), 64);
  });
}
