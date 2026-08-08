import '../models/book.dart';
import '../models/book_chapter.dart';
import '../models/book_content.dart';
import '../models/book_source.dart';
import '../models/book_discover.dart';
import '../models/book_user_source.dart';
import 'api_client.dart';

class BookApi {
  BookApi({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<BookDiscover> discover({
    String? sourceId,
    String section = 'home',
    String? category,
    int page = 1,
  }) async {
    final data = await _client.getJson('api/v1/books/discover', params: {
      'section': section,
      'page': '$page',
      if (sourceId != null && sourceId.isNotEmpty) 'sourceId': sourceId,
      if (category != null && category.isNotEmpty) 'category': category,
    });
    return BookDiscover.fromJson(data);
  }

  Future<List<BookSourceCatalog>> listCatalogs() async {
    final data = await _client.getJson('api/v1/books/sources');
    final raw = data['list'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => BookSourceCatalog.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }

  Future<List<BookUserSource>> listUserSources() async {
    final data = await _client.getJson('api/v1/books/user-sources');
    final raw = data['list'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => BookUserSource.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }

  Future<BookUserSource> importUserSource(String definition) async {
    final data =
        await _client.postJson('api/v1/books/user-sources/import', body: {
      'definition': definition,
    });
    return BookUserSource.fromJson(data);
  }

  Future<BookUserSource> setUserSourceEnabled(int id, bool enabled) async {
    final data =
        await _client.patchJson('api/v1/books/user-sources/$id/enabled', body: {
      'enabled': enabled,
    });
    return BookUserSource.fromJson(data);
  }

  Future<void> deleteUserSource(int id) async {
    await _client.deleteJson('api/v1/books/user-sources/$id');
  }

  Future<BookSearchPage> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    String? sourceId,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty) throw ApiException('请输入书名或作者');
    final data = await _client.getJson('api/v1/books/search', params: {
      'keyword': query,
      'page': '$page',
      'pageSize': '$pageSize',
      if (sourceId != null && sourceId.isNotEmpty) 'sourceId': sourceId,
    });
    return BookSearchPage.fromJson(data);
  }

  Future<Book> getDetail(Book book) async {
    final data = await _client.getJson('api/v1/books/detail', params: {
      'sourceId': book.sourceId,
      'bookUrl': book.bookUrl,
    });
    return book.merge(Book.fromJson(data));
  }

  Future<List<BookChapter>> getChapters(Book book) async {
    final data = await _client.getJson('api/v1/books/chapters', params: {
      'sourceId': book.sourceId,
      'bookUrl': book.bookUrl,
    });
    final raw = data['list'] ?? data['chapters'];
    if (raw is! List) return const [];
    return [
      for (var index = 0; index < raw.length; index++)
        if (raw[index] is Map)
          BookChapter.fromJson(
            Map<String, dynamic>.from(raw[index] as Map),
            index: index,
          ),
    ].where((chapter) => chapter.chapterUrl.isNotEmpty).toList(growable: false);
  }

  Future<BookContent> getContent(
    Book book,
    BookChapter chapter,
  ) async {
    final data = await _client.getJson('api/v1/books/content', params: {
      'sourceId': book.sourceId,
      'bookUrl': book.bookUrl,
      'chapterUrl': chapter.chapterUrl,
    });
    final content = BookContent.fromJson(data);
    return BookContent(
      title: content.title.isEmpty ? chapter.title : content.title,
      text: content.text,
      chapterUrl:
          content.chapterUrl.isEmpty ? chapter.chapterUrl : content.chapterUrl,
    );
  }
}

/// Kept for source compatibility with the first catalog-only implementation.
class BookSourceApi extends BookApi {
  BookSourceApi({super.client});
}
