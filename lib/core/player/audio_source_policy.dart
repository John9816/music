import 'package:flutter/foundation.dart';

bool usesNativeAudioHeaders(TargetPlatform platform) {
  return platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS;
}

List<String> playbackQualityCandidates(String source, String requested) {
  final normalizedSource = source.trim().toLowerCase();
  final normalizedQuality = requested.trim().toLowerCase();
  if (normalizedSource != 'qq') return [normalizedQuality];

  return switch (normalizedQuality) {
    'hires' => const ['hires', 'lossless', 'exhigh', 'standard'],
    'lossless' => const ['lossless', 'exhigh', 'standard'],
    'standard' => const ['standard'],
    _ => const ['exhigh', 'standard'],
  };
}

bool isPlayableAudioResponse(int statusCode, String? contentType) {
  if (statusCode < 200 || statusCode >= 300) return false;
  final normalizedType = contentType?.toLowerCase() ?? '';
  return !normalizedType.startsWith('text/') &&
      !normalizedType.contains('application/json');
}
