import 'package:flutter/foundation.dart';

import '../config/audio_quality_policy.dart';
import '../models/playback_info.dart';

bool usesNativeAudioHeaders(TargetPlatform platform) {
  return platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS;
}

Map<String, String> audioHeadersFor(String source) => {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/537.36',
      'Referer': switch (source.trim().toLowerCase()) {
        'qq' => 'https://y.qq.com/',
        'kuwo' => 'https://www.kuwo.cn/',
        _ => 'https://music.163.com/',
      },
      'Accept': 'audio/*,*/*;q=0.8',
    };

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

class ResolvedPlaybackInfo {
  const ResolvedPlaybackInfo({required this.info, required this.quality});

  final PlaybackInfo info;
  final String quality;
  String get url => info.playUrl!;
}

Future<ResolvedPlaybackInfo?> resolvePlaybackInfo({
  required String source,
  required String requestedQuality,
  required Future<PlaybackInfo> Function(String quality) loadInfo,
}) async {
  for (final quality in playbackQualityCandidates(source, requestedQuality)) {
    final info = await loadInfo(quality);
    if (info.playUrl != null && info.playUrl!.isNotEmpty) {
      return ResolvedPlaybackInfo(info: info, quality: quality);
    }
  }
  return null;
}
