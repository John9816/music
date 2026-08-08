import 'book.dart';

class BookProgress {
  const BookProgress({
    required this.book,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.position,
    required this.updatedAt,
  });

  final Book book;
  final int chapterIndex;
  final String chapterTitle;
  final double position;
  final DateTime updatedAt;

  factory BookProgress.fromJson(Map<String, dynamic> json) {
    final rawBook = json['book'];
    return BookProgress(
      book: Book.fromJson(
        rawBook is Map ? Map<String, dynamic>.from(rawBook) : const {},
      ),
      chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
      chapterTitle: json['chapterTitle']?.toString() ?? '',
      position: ((json['position'] as num?)?.toDouble() ?? 0).clamp(0, 1),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'book': book.toJson(),
        'chapterIndex': chapterIndex,
        'chapterTitle': chapterTitle,
        'position': position,
        'updatedAt': updatedAt.toIso8601String(),
      };
}
