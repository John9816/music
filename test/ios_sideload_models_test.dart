import 'package:duck_music/core/models/ios_sideload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses and normalizes a valid ECS iOS manifest', () {
    final manifest = IosSideloadManifest.fromJson({
      'version': '1.2.0',
      'buildNumber': 12,
      'downloadUrl': 'https://example.com/duckmusic.ipa',
      'sha256': 'A' * 64,
      'minimumOsVersion': '16.0',
      'publishedAt': '2026-08-07T01:02:03Z',
    });

    expect(manifest.version, '1.2.0');
    expect(manifest.buildNumber, 12);
    expect(manifest.sha256, 'a' * 64);
    expect(manifest.publishedAt, DateTime.utc(2026, 8, 7, 1, 2, 3));
  });

  test('rejects a missing or malformed SHA-256', () {
    expect(
      () => IosSideloadManifest.fromJson({
        'version': '1.2.0',
        'buildNumber': 12,
        'downloadUrl': 'https://example.com/duckmusic.ipa',
        'sha256': 'not-a-hash',
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('requests a refresh only inside the configured safety window', () {
    final now = DateTime.utc(2026, 8, 7, 10);
    final status = IosSideloadStatus(
      accountLabel: 'test@example.com',
      signatureExpiresAt: now.add(const Duration(hours: 23)),
      devices: const [],
    );

    expect(status.needsRefresh(now), isTrue);
    expect(
      status
          .copyWith(
            signatureExpiresAt: now.add(const Duration(hours: 25)),
          )
          .needsRefresh(now),
      isFalse,
    );
  });
}
