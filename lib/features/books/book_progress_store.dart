import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/book.dart';
import '../../core/models/book_progress.dart';

class BookProgressStore {
  BookProgressStore._();

  static final BookProgressStore instance = BookProgressStore._();

  static const _indexKey = 'books.reading_progress.index';
  static const _fontSizeKey = 'books.reader.font_size';
  static const _lineHeightKey = 'books.reader.line_height';
  static const _readerModeKey = 'books.reader.mode';
  static const _readerThemeKey = 'books.reader.theme';
  static const _bookshelfKey = 'books.bookshelf';
  static const _progressPrefix = 'books.reading_progress.';

  Future<BookProgress?> load(Book book) async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_keyFor(book)));
  }

  Future<List<BookProgress>> loadRecent({int limit = 6}) async {
    final prefs = await SharedPreferences.getInstance();
    final items = <BookProgress>[];
    for (final key in prefs.getStringList(_indexKey) ?? const <String>[]) {
      final progress = _decode(prefs.getString(key));
      if (progress != null && progress.book.bookUrl.isNotEmpty) {
        items.add(progress);
      }
    }
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items.take(limit).toList(growable: false);
  }

  Future<void> save(BookProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(progress.book);
    await prefs.setString(key, jsonEncode(progress.toJson()));
    final index = prefs.getStringList(_indexKey)?.toList() ?? <String>[];
    index
      ..remove(key)
      ..insert(0, key);
    await prefs.setStringList(_indexKey, index.take(30).toList());
  }

  Future<double> loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getDouble(_fontSizeKey) ?? 18).clamp(14, 30);
  }

  Future<void> saveFontSize(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, value.clamp(14, 30));
  }

  Future<double> loadLineHeight() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getDouble(_lineHeightKey) ?? 1.9).clamp(1.4, 2.4);
  }

  Future<void> saveLineHeight(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lineHeightKey, value.clamp(1.4, 2.4));
  }

  Future<String> loadReaderMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_readerModeKey);
    return value == 'page' ? 'page' : 'scroll';
  }

  Future<void> saveReaderMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_readerModeKey, value == 'page' ? 'page' : 'scroll');
  }

  Future<String> loadReaderTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_readerThemeKey);
    return const {'system', 'paper', 'night'}.contains(value)
        ? value!
        : 'system';
  }

  Future<void> saveReaderTheme(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _readerThemeKey,
      const {'system', 'paper', 'night'}.contains(value) ? value : 'system',
    );
  }

  Future<List<Book>> loadBookshelf() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_bookshelfKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Book.fromJson(Map<String, dynamic>.from(item)))
          .where((book) => book.bookUrl.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<bool> isInBookshelf(Book book) async {
    final books = await loadBookshelf();
    return books.any((item) => item.identity == book.identity);
  }

  Future<void> setInBookshelf(Book book, bool included) async {
    final prefs = await SharedPreferences.getInstance();
    final books = (await loadBookshelf()).toList();
    books.removeWhere((item) => item.identity == book.identity);
    if (included) books.insert(0, book);
    await prefs.setString(
      _bookshelfKey,
      jsonEncode(books.map((item) => item.toJson()).toList()),
    );
  }

  BookProgress? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return BookProgress.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  String _keyFor(Book book) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(book.identity)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return '$_progressPrefix${hash.toRadixString(16).padLeft(8, '0')}';
  }
}
