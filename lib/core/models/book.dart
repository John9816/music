class Book {
  const Book({
    required this.sourceId,
    required this.name,
    required this.bookUrl,
    this.sourceName = '',
    this.author = '',
    this.coverUrl,
    this.intro = '',
    this.latestChapter = '',
    this.status = '',
    this.category = '',
  });

  final String sourceId;
  final String sourceName;
  final String name;
  final String author;
  final String? coverUrl;
  final String bookUrl;
  final String intro;
  final String latestChapter;
  final String status;
  final String category;

  String get identity => '$sourceId\n$bookUrl';

  factory Book.fromJson(Map<String, dynamic> json) {
    final nested = json['book'];
    final data = nested is Map
        ? <String, dynamic>{...json, ...Map<String, dynamic>.from(nested)}
        : json;
    return Book(
      sourceId: _text(data, const ['sourceId', 'source', 'origin']),
      sourceName: _text(data, const ['sourceName', 'originName']),
      name: _text(data, const ['name', 'bookName', 'title'], fallback: '未命名小说'),
      author: _text(data, const ['author', 'bookAuthor']),
      coverUrl:
          _nullableText(data, const ['coverUrl', 'bookCoverUrl', 'cover']),
      bookUrl: _text(data, const ['bookUrl', 'url', 'detailUrl']),
      intro: _text(data, const ['intro', 'description', 'bookIntro']),
      latestChapter: _text(
        data,
        const ['latestChapter', 'latestChapterTitle', 'lastChapter'],
      ),
      status: _text(data, const ['status', 'bookStatus']),
      category: _text(data, const ['category', 'kind', 'bookKind']),
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'sourceName': sourceName,
        'name': name,
        'author': author,
        'coverUrl': coverUrl,
        'bookUrl': bookUrl,
        'intro': intro,
        'latestChapter': latestChapter,
        'status': status,
        'category': category,
      };

  Book merge(Book other) => Book(
        sourceId: other.sourceId.isNotEmpty ? other.sourceId : sourceId,
        sourceName: other.sourceName.isNotEmpty ? other.sourceName : sourceName,
        name: other.name != '未命名小说' ? other.name : name,
        author: other.author.isNotEmpty ? other.author : author,
        coverUrl: other.coverUrl ?? coverUrl,
        bookUrl: other.bookUrl.isNotEmpty ? other.bookUrl : bookUrl,
        intro: other.intro.isNotEmpty ? other.intro : intro,
        latestChapter: other.latestChapter.isNotEmpty
            ? other.latestChapter
            : latestChapter,
        status: other.status.isNotEmpty ? other.status : status,
        category: other.category.isNotEmpty ? other.category : category,
      );
}

class BookSearchPage {
  const BookSearchPage({
    required this.books,
    required this.page,
    required this.hasMore,
  });

  final List<Book> books;
  final int page;
  final bool hasMore;

  factory BookSearchPage.fromJson(Map<String, dynamic> json) {
    final raw = json['list'] ?? json['books'] ?? json['results'];
    final books = raw is List
        ? raw
            .whereType<Map>()
            .map((item) => Book.fromJson(Map<String, dynamic>.from(item)))
            .where((book) => book.bookUrl.isNotEmpty)
            .toList(growable: false)
        : const <Book>[];
    final page = _integer(json, const ['page', 'pageIndex'], fallback: 1);
    final total = _integer(json, const ['total', 'totalCount']);
    final pageSize = _integer(json, const ['pageSize', 'limit']);
    return BookSearchPage(
      books: books,
      page: page,
      hasMore: json['hasMore'] == true ||
          (total > 0 && pageSize > 0 && page * pageSize < total),
    );
  }
}

String _text(
  Map<String, dynamic> json,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = json[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'null') return value;
  }
  return fallback;
}

String? _nullableText(Map<String, dynamic> json, List<String> keys) {
  final value = _text(json, keys);
  return value.isEmpty ? null : value;
}

int _integer(
  Map<String, dynamic> json,
  List<String> keys, {
  int fallback = 0,
}) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return fallback;
}
