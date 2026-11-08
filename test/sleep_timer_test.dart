import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expiry invokes the pause callback once after clearing the timer',
      (tester) async {
    final timer = SleepTimer();
    addTearDown(timer.dispose);
    var pauses = 0;
    bool? activeAtTimeout;
    timer.start(const Duration(seconds: 2), onTimeout: () {
      activeAtTimeout = timer.isActive;
      pauses++;
    });
    await tester.pump(const Duration(seconds: 1));
    expect(pauses, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(pauses, 1);
    expect(activeAtTimeout, isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(pauses, 1);
    expect(timer.isActive, isFalse);
  });

  testWidgets('cancelling a timer never invokes its pause callback',
      (tester) async {
    final timer = SleepTimer();
    addTearDown(timer.dispose);
    var pauses = 0;
    timer.start(const Duration(seconds: 2), onTimeout: () => pauses++);
    await tester.pump(const Duration(seconds: 1));
    timer.stop();
    await tester.pump(const Duration(seconds: 5));
    expect(pauses, 0);
    expect(timer.isActive, isFalse);
  });

  testWidgets('resetting a timer keeps only the replacement callback',
      (tester) async {
    final timer = SleepTimer();
    addTearDown(timer.dispose);
    final fired = <String>[];
    timer.start(const Duration(seconds: 2), onTimeout: () => fired.add('old'));
    await tester.pump(const Duration(seconds: 1));
    timer.start(const Duration(seconds: 3), onTimeout: () => fired.add('new'));
    await tester.pump(const Duration(seconds: 2));
    expect(fired, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(fired, ['new']);
  });
}
