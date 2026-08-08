import 'package:duck_music/core/theme/design_tokens.dart';
import 'package:duck_music/core/theme/platform_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile motion follows platform and reduce-motion settings',
      (tester) async {
    Future<void> pump({
      required TargetPlatform platform,
      required bool disableAnimations,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Builder(
              builder: (context) => Text(
                '${PlatformMotion.tabDuration(context).inMilliseconds}: '
                '${PlatformMotion.curve(context)}',
              ),
            ),
          ),
        ),
      );
    }

    await pump(platform: TargetPlatform.iOS, disableAnimations: false);
    expect(PlatformMotion.tabDuration(tester.element(find.byType(Text))),
        Motion.normal);
    expect(
      PlatformMotion.curve(tester.element(find.byType(Text))),
      Curves.easeOutCubic,
    );

    await pump(platform: TargetPlatform.android, disableAnimations: true);
    expect(PlatformMotion.tabDuration(tester.element(find.byType(Text))),
        Duration.zero);
  });
}
