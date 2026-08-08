import 'package:duck_music/features/live_tv/live_line_failover.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tries each line once in source order', () {
    final failover = LiveLineFailover(['line-1', 'line-2', 'line-3']);

    expect(failover.start(), 'line-1');
    expect(failover.failCurrent(), 'line-2');
    expect(failover.failCurrent(), 'line-3');
    expect(failover.failCurrent(), isNull);
    expect(failover.attemptedIds, {'line-1', 'line-2', 'line-3'});
  });

  test('starts at a selected line and wraps through every remaining line', () {
    final failover = LiveLineFailover(['line-1', 'line-2', 'line-3']);

    expect(failover.start(preferredId: 'line-2'), 'line-2');
    expect(failover.failCurrent(), 'line-3');
    expect(failover.failCurrent(), 'line-1');
    expect(failover.failCurrent(), isNull);
  });

  test('manual selection begins a fresh attempt cycle', () {
    final failover = LiveLineFailover(['line-1', 'line-2']);
    expect(failover.start(), 'line-1');
    expect(failover.failCurrent(), 'line-2');
    expect(failover.failCurrent(), isNull);

    expect(failover.select('line-2'), 'line-2');
    expect(failover.attemptedIds, {'line-2'});
    expect(failover.failCurrent(), 'line-1');
  });

  test('rejects an unknown selection without changing the cycle', () {
    final failover = LiveLineFailover(['line-1', 'line-2']);
    expect(failover.start(), 'line-1');

    expect(failover.select('missing'), isNull);
    expect(failover.currentId, 'line-1');
    expect(failover.failCurrent(), 'line-2');
  });

  test('restart begins a new source-order cycle after exhaustion', () {
    final failover = LiveLineFailover(['line-1']);
    expect(failover.start(), 'line-1');
    expect(failover.failCurrent(), isNull);

    expect(failover.restart(), 'line-1');
    expect(failover.attemptedIds, {'line-1'});
  });
}
