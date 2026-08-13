import 'package:flutter/foundation.dart';

import '../config/audio_quality_policy.dart';

bool usesNativeAudioHeaders(TargetPlatform platform) {
  return platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS;
}

List<String> playbackQualityCandidates(String source, String requested) {
  return [normalizeQualityForSource(source, requested)];
}

typedef PlaybackUrlLoader = Future<String?> Function(String quality);

class ResolvedPlaybackUrl {
  const ResolvedPlaybackUrl({required this.url, required this.quality});

  final String url;
  final String quality;
}

Future<ResolvedPlaybackUrl?> resolvePlaybackUrl({
  required String source,
  required String requestedQuality,
  required PlaybackUrlLoader loadUrl,
}) async {
  for (final quality in playbackQualityCandidates(source, requestedQuality)) {
    final url = (await loadUrl(quality))?.trim();
    if (url != null && url.isNotEmpty) {
      return ResolvedPlaybackUrl(url: url, quality: quality);
    }
  }
  return null;
}
