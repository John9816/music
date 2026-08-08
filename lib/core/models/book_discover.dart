import 'book.dart';

class BookCategory {
  const BookCategory({required this.key, required this.name});

  final String key;
  final String name;

  factory BookCategory.fromJson(Map<String, dynamic> json) => BookCategory(
        key: json['key']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

class BookDiscoverSection {
  const BookDiscoverSection({
    required this.key,
    required this.title,
    required this.books,
  });

  final String key;
  final String title;
  final List<Book> books;

  factory BookDiscoverSection.fromJson(Map<String, dynamic> json) {
    final raw = json['books'] ?? json['list'];
    return BookDiscoverSection(
      key: json['key']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      books: raw is List
          ? raw
              .whereType<Map>()
              .map((item) => Book.fromJson(Map<String, dynamic>.from(item)))
              .where((book) => book.bookUrl.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }
}

class BookDiscover {
  const BookDiscover({
    required this.sourceId,
    required this.sourceName,
    required this.categories,
    required this.sections,
  });

  final String sourceId;
  final String sourceName;
  final List<BookCategory> categories;
  final List<BookDiscoverSection> sections;

  factory BookDiscover.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'];
    final rawSections = json['sections'];
    return BookDiscover(
      sourceId: json['sourceId']?.toString() ?? '',
      sourceName: json['sourceName']?.toString() ?? '',
      categories: rawCategories is List
          ? rawCategories
              .whereType<Map>()
              .map((item) => BookCategory.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .where((item) => item.key.isNotEmpty && item.name.isNotEmpty)
              .toList(growable: false)
          : const [],
      sections: rawSections is List
          ? rawSections
              .whereType<Map>()
              .map((item) => BookDiscoverSection.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
    );
  }
}
