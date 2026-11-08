import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _ignoreSeek(Duration value) {}

void main() {
  testWidgets('wave pauses offstage and in background then resumes',
      (tester) async {
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return TickerMode(
          enabled: enabled,
          child: const Center(
              child: SizedBox(
                  width: 300,
                  child: GProgressBar(
                      position: Duration(seconds: 20),
                      duration: Duration(seconds: 100),
                      wave: true,
                      playing: true, onSeek: _ignoreSeek))));
    })));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    update(() => enabled = false);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    update(() => enabled = true);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('wave progress retains seeking and stops animation when paused',
      (tester) async {
    Duration? sought;
    var playing = true;
    var reduced = false;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: Scaffold(
              body: Center(
                  child: SizedBox(
            width: 300,
            child: GProgressBar(
              position: const Duration(seconds: 20),
              duration: const Duration(seconds: 100),
              wave: true,
              playing: playing,
              onSeek: (value) => sought = value,
            ),
          ))),
        );
      },
    )));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    final rect = tester.getRect(find.byType(GProgressBar));
    await tester.tapAt(Offset(rect.left + rect.width * .75, rect.center.dy));
    expect(sought, const Duration(seconds: 75));
    update(() => playing = false);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    update(() {
      playing = true;
      reduced = true;
    });
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
