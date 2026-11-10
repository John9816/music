import '../../core/player/lrc_parser.dart';

/// Folia uses seconds. Keep source word boundaries; line-only lyrics stay lines.
List<Map<String, Object>> foliaTimeline(String lrc, Duration duration) {
  final lines = parseLrc(lrc).where((l) => l.text.trim().isNotEmpty).toList();
  return List.generate(lines.length, (index) {
    final line = lines[index];
    final start = line.time.inMilliseconds / 1000;
    final next = index + 1 < lines.length
        ? lines[index + 1].time.inMilliseconds / 1000
        : duration.inMilliseconds / 1000;
    final wordEnd = line.words.isEmpty
        ? start
        : (line.words.last.time + line.words.last.duration).inMilliseconds /
            1000;
    final end = wordEnd > start ? wordEnd : (next > start ? next : start + 5);
    return {
      'startTime': start,
      'endTime': end,
      'fullText': line.text,
      'words': line.words
          .map((w) => {
                'text': w.text,
                'startTime': w.time.inMilliseconds / 1000,
                'endTime': (w.time + w.duration).inMilliseconds / 1000,
              })
          .toList(),
    };
  });
}
