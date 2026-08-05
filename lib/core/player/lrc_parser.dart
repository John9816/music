/// LRC 歌词解析器（对应 macOS 版 LrcParser）。
class LrcLine {
  LrcLine({required this.time, required this.text});

  final Duration time;
  final String text;
}

List<LrcLine> parseLrc(String lrc) {
  final lines = <LrcLine>[];
  if (lrc.isEmpty) return lines;
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
