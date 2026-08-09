import 'package:duck_music/core/models/book.dart';
import 'package:duck_music/core/models/book_chapter.dart';
import 'package:duck_music/core/models/book_content.dart';
import 'package:duck_music/core/models/book_progress.dart';
import 'package:duck_music/features/books/book_progress_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('book models accept the backend book field aliases', () {
    final book = Book.fromJson({
      'sourceId': 'yckceo',
      'sourceName': 'YckCeo',
      'bookName': '测试小说',
      'bookAuthor': '作者',
      'bookUrl': 'https://example.com/book/1',
      'bookCoverUrl': 'https://example.com/cover.jpg',
      'description': '简介',
    });
    expect(book.name, '测试小说');
    expect(book.author, '作者');
    expect(book.coverUrl, 'https://example.com/cover.jpg');

    final chapter = BookChapter.fromJson(
      {'chapterName': '第一章', 'url': 'https://example.com/chapter/1'},
      index: 0,
    );
    expect(chapter.title, '第一章');

    final content = BookContent.fromJson({
      'title': '第一章',
      'content': '第一段<br>第二段',
    });
    expect(content.text, '第一段\n第二段');

    final progress = BookProgress(
      book: book,
      chapterIndex: 2,
      chapterTitle: '第三章',
      position: .5,
      updatedAt: DateTime.utc(2025),
    );
    expect(BookProgress.fromJson(progress.toJson()).chapterIndex, 2);
  });

  test('reading progress and bookshelf survive a new store instance', () async {
    SharedPreferences.setMockInitialValues({});
    final store = BookProgressStore.instance;
    const book = Book(
      sourceId: 'source',
      name: '书架测试',
      bookUrl: 'book-url',
    );
    await store.setInBookshelf(book, true);
    await store.save(BookProgress(
      book: book,
      chapterIndex: 1,
      chapterTitle: '第二章',
      position: .25,
      updatedAt: DateTime.now(),
    ));

    expect(await store.isInBookshelf(book), isTrue);
    expect((await store.load(book))?.chapterTitle, '第二章');
    expect((await store.loadBookshelf()).single.name, '书架测试');
  });

  test('reader defaults to page mode and keeps an explicit scroll choice',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = BookProgressStore.instance;

    expect(await store.loadReaderMode(), 'page');

    await store.saveReaderMode('scroll');
    expect(await store.loadReaderMode(), 'scroll');
  });
}
