import 'package:flutter/material.dart';

import '../../core/api/book_api.dart';
import '../../core/models/book.dart';
import '../../core/models/book_chapter.dart';
import '../../core/models/book_progress.dart';
import '../../widgets/glass.dart';
import 'book_progress_store.dart';
import 'book_reader_view.dart';
import 'widgets/book_cover.dart';

class BookDetailView extends StatefulWidget {
  const BookDetailView({super.key, required this.book});

  final Book book;

  @override
  State<BookDetailView> createState() => _BookDetailViewState();
}

class _BookDetailViewState extends State<BookDetailView> {
  final _api = BookApi();
  late Future<_BookDetailData> _future;
  BookProgress? _progress;
  bool _inBookshelf = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadLocalState();
  }

  Future<_BookDetailData> _load() async {
    final values = await Future.wait<Object>([
      _api.getDetail(widget.book),
      _api.getChapters(widget.book),
    ]);
    return _BookDetailData(
      book: values[0] as Book,
      chapters: values[1] as List<BookChapter>,
    );
  }

  Future<void> _loadLocalState() async {
    final values = await Future.wait<Object?>([
      BookProgressStore.instance.load(widget.book),
      BookProgressStore.instance.isInBookshelf(widget.book),
    ]);
    if (!mounted) return;
    setState(() {
      _progress = values[0] as BookProgress?;
      _inBookshelf = values[1] as bool;
    });
  }

  Future<void> _toggleBookshelf() async {
    final included = !_inBookshelf;
    setState(() => _inBookshelf = included);
    await BookProgressStore.instance.setInBookshelf(widget.book, included);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(included ? '已加入书架' : '已从书架移除')),
    );
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _read(_BookDetailData data, int index) async {
    if (data.chapters.isEmpty) return;
    final safeIndex = index.clamp(0, data.chapters.length - 1);
    final resumePosition =
        _progress?.chapterIndex == safeIndex ? _progress!.position : 0.0;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BookReaderView(
          book: data.book,
          chapters: data.chapters,
          initialChapterIndex: safeIndex,
          initialPosition: resumePosition,
        ),
      ),
    );
    _loadLocalState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GAppBar(
        title: widget.book.name,
        onBack: () => Navigator.of(context).maybePop(),
        actions: [
          GIconButton(
            icon: _inBookshelf
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            tooltip: _inBookshelf ? '移出书架' : '加入书架',
            tint: _inBookshelf ? Theme.of(context).colorScheme.primary : null,
            onTap: _toggleBookshelf,
          ),
        ],
      ),
      body: FutureBuilder<_BookDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const GLoading();
          }
          if (snapshot.hasError) {
            return GEmptyState(
              icon: Icons.cloud_off_rounded,
              title: '详情加载失败',
              text: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          return _buildContent(snapshot.data!);
        },
      ),
    );
  }

  Widget _buildContent(_BookDetailData data) {
    final scheme = Theme.of(context).colorScheme;
    final book = data.book;
    final chapterCount = data.chapters.length;
    final resumeIndex = (_progress?.chapterIndex ?? 0).clamp(
      0,
      chapterCount > 0 ? chapterCount - 1 : 0,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              sliver: SliverToBoxAdapter(
                child: GSurface(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 500;
                      final details = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.name,
                            style: const TextStyle(
                              fontSize: TypeScale.section,
                              fontWeight: TypeScale.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            book.author.isEmpty ? '作者未知' : book.author,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          if (book.sourceName.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              '来源：${book.sourceName}',
                              style: TextStyle(
                                fontSize: TypeScale.small,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          GButton(
                            label: _progress == null ? '开始阅读' : '继续阅读',
                            icon: Icons.chrome_reader_mode_rounded,
                            expand: compact,
                            onTap: chapterCount == 0
                                ? null
                                : () => _read(data, resumeIndex),
                          ),
                        ],
                      );
                      if (compact) {
                        return Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BookCover(
                                  url: book.coverUrl,
                                  width: 88,
                                  height: 124,
                                ),
                                const SizedBox(width: 16),
                                Expanded(child: details),
                              ],
                            ),
                            if (book.intro.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _Introduction(text: book.intro),
                            ],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BookCover(
                            url: book.coverUrl,
                            width: 112,
                            height: 158,
                          ),
                          const SizedBox(width: 20),
                          SizedBox(width: 240, child: details),
                          if (book.intro.isNotEmpty) ...[
                            const SizedBox(width: 24),
                            Expanded(child: _Introduction(text: book.intro)),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SectionHeader(
                '目录',
                subtitle: chapterCount == 0 ? '暂无章节' : '共 $chapterCount 章',
              ),
            ),
            if (data.chapters.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: GEmptyState(
                  icon: Icons.format_list_numbered_rounded,
                  text: '书源没有返回可读章节',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 32),
                sliver: SliverList.builder(
                  itemCount: chapterCount,
                  itemBuilder: (context, index) {
                    final chapter = data.chapters[index];
                    final current = _progress?.chapterIndex == index;
                    return GListTile(
                      selected: current,
                      leading: SizedBox(
                        width: 34,
                        child: Text(
                          '${index + 1}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: TypeScale.small,
                            color: current ? scheme.primary : scheme.outline,
                          ),
                        ),
                      ),
                      title: Text(
                        chapter.title.isEmpty
                            ? '第 ${index + 1} 章'
                            : chapter.title,
                      ),
                      trailing: current
                          ? const Icon(Icons.bookmark_rounded, size: 18)
                          : const Icon(Icons.chevron_right_rounded, size: 19),
                      onTap: () => _read(data, index),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Introduction extends StatelessWidget {
  const _Introduction({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '简介',
          style: TextStyle(fontWeight: TypeScale.semibold),
        ),
        const SizedBox(height: 7),
        Text(
          text,
          maxLines: 7,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            height: 1.65,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BookDetailData {
  const _BookDetailData({required this.book, required this.chapters});

  final Book book;
  final List<BookChapter> chapters;
}
