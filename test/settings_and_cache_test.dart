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

  test('streaming audio cache is limited to compatible sources', () {
    expect(CacheService.supportsAutomaticAudioCache('netease'), isTrue);
    expect(CacheService.supportsAutomaticAudioCache('NETEASE'), isTrue);
    expect(CacheService.supportsAutomaticAudioCache('qq'), isFalse);
    expect(CacheService.supportsAutomaticAudioCache('kuwo'), isFalse);
  });

  test('settings survive controller recreation', () async {
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

  test('legacy music source seeds search once without linking future changes',
      () async {
    SharedPreferences.setMockInitialValues(const {'music_source': 'qq'});
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('search_music_source'), 'qq');

    await settings.setSource('kuwo');
    final restored = SettingsController();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.source, 'kuwo');
    expect(restored.searchSource, 'qq');
    expect(preferences.getString('search_music_source'), 'qq');
  });

  test('playback quality is saved independently for each music source',
      () async {
    SharedPreferences.setMockInitialValues(const {'quality': 'hires'});
    final settings = SettingsController();
    await settings.load();

    expect(settings.qualityForSource('netease'), 'hires');
    expect(settings.qualityForSource('qq'), 'exhigh');

    await settings.setQualityForSource('qq', 'lossless');
    await settings.setQualityForSource('netease', 'hires');

    final restored = SettingsController();
    await restored.load();
    expect(restored.qualityForSource('qq'), 'lossless');
    expect(restored.qualityForSource('netease'), 'hires');
  });

  test('all seven accent colors build in light and dark', () {
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
      final light = AppTheme.forAccent(accent.id, dark: false);
      final dark = AppTheme.forAccent(accent.id, dark: true);
      expect(light.scheme.primary, accent.color);
      expect(dark.scheme.primary, accent.color);
      expect(light.data.scaffoldBackgroundColor,
          light.scheme.surfaceContainerLowest);
      expect(dark.data.scaffoldBackgroundColor,
          dark.scheme.surfaceContainerLowest);
    }

    final red = AppTheme.forAccent('rhythmRed', dark: true).scheme;
    final blue = AppTheme.forAccent('skyBlue', dark: true).scheme;
    expect(red.surfaceContainerLowest, blue.surfaceContainerLowest);
    expect(red.surfaceContainer, blue.surfaceContainer);
    expect(red.surfaceContainerHighest, blue.surfaceContainerHighest);
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
