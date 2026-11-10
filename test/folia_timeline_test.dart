import 'package:duck_music/features/player/folia_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('line lyrics use next nonempty line and duration without invented words',
      () {
    final rows = foliaTimeline(
        '[00:01]第一句\n[00:02]\n[00:04]第二句', const Duration(seconds: 9));
    expect(rows[0]['endTime'], 4);
    expect(rows[1]['endTime'], 9);
    expect(rows[0]['words'], isEmpty);
  });
  test('karaoke timing retains exact absolute word boundaries', () {
    final rows = foliaTimeline(
        '[1000,2000](1000,700,0)你(2000,1000,0)好', const Duration(seconds: 10));
    expect(rows.single['endTime'], 3);
    expect(rows.single['words'], [
      {'text': '你', 'startTime': 1.0, 'endTime': 1.7},
      {'text': '好', 'startTime': 2.0, 'endTime': 3.0},
    ]);
  });
  test('empty lyrics and unknown final duration are bounded', () {
    expect(foliaTimeline('', Duration.zero), isEmpty);
    expect(foliaTimeline('[00:10]终句', Duration.zero).single['endTime'], 15);
  });
}
