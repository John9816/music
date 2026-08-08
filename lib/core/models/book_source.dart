class BookSourceCatalog {
  const BookSourceCatalog({
    required this.id,
    required this.name,
    required this.kind,
    required this.description,
    required this.catalogUrl,
    this.importUrl,
    required this.maintained,
  });

  final String id;
  final String name;
  final String kind;
  final String description;
  final String catalogUrl;
  final String? importUrl;
  final bool maintained;

  bool get isBook => kind == 'book';

  factory BookSourceCatalog.fromJson(Map<String, dynamic> json) {
    return BookSourceCatalog(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名资源',
      kind: json['kind']?.toString() ?? 'book',
      description: json['description']?.toString() ?? '',
      catalogUrl: json['catalogUrl']?.toString() ?? '',
      importUrl: _nullableText(json['importUrl']),
      maintained: json['maintained'] == true,
    );
  }

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
