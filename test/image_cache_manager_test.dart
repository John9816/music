import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:duck_music/core/utils/image_cache_manager.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('custom cache decodes and resizes cover artwork', () async {
    final directory = await Directory.systemTemp.createTemp('duck-cover-test-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    final cache = ImageCacheManager.instance;
    addTearDown(() async {
      PaintingBinding.instance.imageCache.clear();
      await cache.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });

    const url = 'https://example.com/cover-cache-test.png';
    await cache.putFile(
      url,
      await File('assets/branding/app_icon.png').readAsBytes(),
      fileExtension: 'png',
    );
    final stream = CachedNetworkImageProvider(
      url,
      cacheManager: cache,
      maxWidth: 64,
      maxHeight: 64,
    ).resolve(ImageConfiguration.empty);
    final decoded = Completer<ImageInfo>();
    final listener = ImageStreamListener(
      (image, _) => decoded.complete(image),
      onError: decoded.completeError,
    );
    stream.addListener(listener);
    addTearDown(() => stream.removeListener(listener));

    final image = await decoded.future.timeout(const Duration(seconds: 5));
    addTearDown(image.dispose);
    expect(image.image.width, 64);
    expect(image.image.height, 64);
  });
}
