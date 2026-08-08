import 'package:flutter/foundation.dart';

bool usesNativeAudioHeaders(TargetPlatform platform) {
  return platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS;
}
