import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

/// Small platform differences shared by mobile surfaces.
///
/// Content and navigation stay structurally identical on iOS and Android, but
/// feedback follows the interaction language users expect from each platform.
class PlatformMotion {
  PlatformMotion._();

  static bool isIOS(BuildContext context) =>
      Theme.of(context).platform == TargetPlatform.iOS;

  static bool isAndroid(BuildContext context) =>
      Theme.of(context).platform == TargetPlatform.android;

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;

  static Curve curve(BuildContext context) =>
      isIOS(context) ? Curves.easeOutCubic : Curves.fastOutSlowIn;

  static void selectionFeedback(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    if (isAndroid(context)) {
      HapticFeedback.lightImpact();
    } else if (isIOS(context)) {
      HapticFeedback.selectionClick();
    }
  }

  static Duration tabDuration(BuildContext context) =>
      duration(context, Motion.normal);
}
