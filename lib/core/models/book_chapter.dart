class BookChapter {
  const BookChapter({
    required this.title,
    required this.chapterUrl,
    required this.index,
    this.volume = '',
  });

  final String title;
  final String chapterUrl;
  final int index;
  final String volume;

  factory BookChapter.fromJson(Map<String, dynamic> json,
      {required int index}) {
    return BookChapter(
      title: _firstText(json, const ['title', 'chapterName', 'name']),
      chapterUrl: _firstText(json, const ['chapterUrl', 'url', 'href']),
      index: _firstInt(json, const ['index', 'chapterIndex'], fallback: index),
      volume: _firstText(json, const ['volume', 'volumeName']),
    );
  }
}

String _firstText(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'null') return value;
  }
  return '';
}

int _firstInt(
  Map<String, dynamic> json,
  List<String> keys, {
  required int fallback,
}) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return fallback;
}
