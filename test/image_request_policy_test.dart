import 'package:cached_network_image/cached_network_image.dart';
import 'package:duck_music/core/network/image_request_policy.dart';
import 'package:duck_music/widgets/async_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeRemoteImageUrl', () {
    test('upgrades NetEase CDN covers to HTTPS', () {
      expect(
        normalizeRemoteImageUrl(
          'http://p4.music.126.net/cover-id/playlist.jpg',
        ),
        'https://p4.music.126.net/cover-id/playlist.jpg',
      );
    });

    test('normalizes protocol-relative image URLs', () {
      expect(
        normalizeRemoteImageUrl('//p3.music.126.net/cover-id/playlist.jpg'),
        'https://p3.music.126.net/cover-id/playlist.jpg',
      );
    });

    test('preserves non-NetEase HTTP URLs and rejects blanks', () {
      expect(
        normalizeRemoteImageUrl('http://img1.kwcdn.kuwo.cn/cover.jpg'),
        'http://img1.kwcdn.kuwo.cn/cover.jpg',
      );
      expect(normalizeRemoteImageUrl('  '), isNull);
    });
  });

  test('NetEase covers use source-compatible request headers', () {
    expect(
      imageRequestHeaders('https://p4.music.126.net/cover.jpg'),
      containsPair('Referer', 'https://music.163.com/'),
    );
    expect(
      imageRequestHeaders('https://p4.music.126.net/cover.jpg'),
      contains('User-Agent'),
    );
    expect(imageRequestHeaders('https://example.com/cover.jpg'), isEmpty);
  });

  testWidgets('AsyncCover applies the normalized URL and headers',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 80,
          height: 80,
          child: AsyncCover(
            url: 'http://p4.music.126.net/cover-id/playlist.jpg',
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(
      image.imageUrl,
      'https://p4.music.126.net/cover-id/playlist.jpg',
    );
    expect(image.httpHeaders?['Referer'], 'https://music.163.com/');
  });
}
