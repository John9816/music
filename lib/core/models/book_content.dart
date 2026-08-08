class BookContent {
  const BookContent({
    required this.title,
    required this.text,
    this.chapterUrl = '',
  });

  final String title;
  final String text;
  final String chapterUrl;

  factory BookContent.fromJson(Map<String, dynamic> json) {
    final nested = json['content'];
    final data = nested is Map ? Map<String, dynamic>.from(nested) : json;
    final rawText = nested is String
        ? nested
        : data['text'] ?? data['content'] ?? data['body'] ?? '';
    return BookContent(
      title: _value(data, const ['title', 'chapterName', 'name']),
      text: _normalize(rawText.toString()),
      chapterUrl: _value(data, const ['chapterUrl', 'url']),
    );
  }

  static String _normalize(String value) => value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n[ \t]+'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _value(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'null') return value;
  }
  return '';
}
