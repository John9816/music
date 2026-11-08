/// LRC 歌词解析器（对应 macOS 版 LrcParser）。
class LrcLine {
  LrcLine({required this.time, required this.text, this.words = const []});

  final Duration time;
  final String text;
  final List<LrcWord> words;
}

class LrcWord {
  const LrcWord(
      {required this.time, required this.duration, required this.text});

  final Duration time;
  final Duration duration;
  final String text;

  double progressAt(Duration position) {
    if (position < time) return 0;
    if (duration == Duration.zero) return 1;
    return ((position - time).inMicroseconds / duration.inMicroseconds)
        .clamp(0.0, 1.0);
  }
}

List<LrcLine> parseLrc(String lrc) {
  final lines = <LrcLine>[];
  if (lrc.isEmpty) return lines;
  final karaoke = parseKaraokeLrc(lrc);
  if (karaoke.isNotEmpty) return karaoke;
  final re = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  for (final line in lrc.split('\n')) {
    final matches = re.allMatches(line);
    if (matches.isEmpty) continue;
    final text = line.replaceAll(re, '').trim();
    for (final m in matches) {
      final minutes = int.parse(m.group(1)!);
      final seconds = int.parse(m.group(2)!);
      final msRaw = m.group(3) ?? '0';
      final ms = int.parse(msRaw.padRight(3, '0').substring(0, 3));
      lines.add(
        LrcLine(
          time: Duration(minutes: minutes, seconds: seconds, milliseconds: ms),
          text: text,
        ),
      );
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

/// NetEase YRC uses absolute milliseconds for both row and word start times.
/// Unknown formats remain unsupported so callers can use the ordinary LRC.
List<LrcLine> parseKaraokeLrc(String source) {
  final rows = <LrcLine>[];
  final rowPattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  final wordPattern = RegExp(r'\((\d+),(\d+),(\d+)\)');
  for (final raw in source.split('\n')) {
    final row = rowPattern.firstMatch(raw.trim());
    if (row == null) continue;
    final start = int.tryParse(row[1]!);
    final duration = int.tryParse(row[2]!);
    if (start == null || duration == null || duration <= 0) continue;
    final content = row[3]!;
    final tags = wordPattern.allMatches(content).toList();
    if (tags.isEmpty || tags.first.start != 0) continue;
    final words = <LrcWord>[];
    var previous = start;
    var valid = true;
    for (var i = 0; i < tags.length; i++) {
      final tag = tags[i];
      final time = int.tryParse(tag[1]!);
      final length = int.tryParse(tag[2]!);
      if (time == null ||
          length == null ||
          time < previous ||
          time > start + duration ||
          time + length > start + duration + 100) {
        valid = false;
        break;
      }
      final text = content.substring(
          tag.end, i + 1 < tags.length ? tags[i + 1].start : content.length);
      if (RegExp(r'\(-?\d+,').hasMatch(text)) {
        valid = false;
        break;
      }
      words.add(LrcWord(
        time: Duration(milliseconds: time),
        duration: Duration(milliseconds: length),
        text: text,
      ));
      previous = time;
    }
    final text = words.map((word) => word.text).join();
    if (!valid || text.trim().isEmpty) continue;
    rows.add(LrcLine(
        time: Duration(milliseconds: start),
        text: text,
        words: List.unmodifiable(words)));
  }
  rows.sort((a, b) => a.time.compareTo(b.time));
  return rows;
}
