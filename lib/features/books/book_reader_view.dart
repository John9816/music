import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/book_api.dart';
import '../../core/models/book.dart';
import '../../core/models/book_chapter.dart';
import '../../core/models/book_content.dart';
import '../../core/models/book_progress.dart';
import '../../widgets/glass.dart';
import 'book_progress_store.dart';

class BookReaderView extends StatefulWidget {
  const BookReaderView({
    super.key,
    required this.book,
    required this.chapters,
    this.initialChapterIndex = 0,
    this.initialPosition = 0,
  });

  final Book book;
  final List<BookChapter> chapters;
  final int initialChapterIndex;
  final double initialPosition;

  @override
  State<BookReaderView> createState() => _BookReaderViewState();
}

class _BookReaderViewState extends State<BookReaderView> {
  final _api = BookApi();
  final _store = BookProgressStore.instance;
  late final PageController _pageController;
  late final ScrollController _scrollController;
  final _readerFocusNode = FocusNode(debugLabel: 'book-reader');

  BookContent? _content;
  List<String> _pages = const [];
  late int _chapterIndex;
  double _position = 0;
  double _fontSize = 18;
  double _lineHeight = 1.9;
  String _mode = 'scroll';
  String _readerTheme = 'system';
  bool _loading = true;
  String? _error;

  BookChapter get _chapter => widget.chapters.isEmpty
      ? const BookChapter(title: '', chapterUrl: '', index: 0)
      : widget.chapters[_chapterIndex];

  @override
  void initState() {
    super.initState();
    _chapterIndex = widget.chapters.isEmpty
        ? 0
        : widget.initialChapterIndex.clamp(0, widget.chapters.length - 1);
    _position = widget.initialPosition.clamp(0.0, 1.0);
    _pageController = PageController();
    _scrollController = ScrollController();
    _initialize();
  }

  Future<void> _initialize() async {
    final settings = await Future.wait<Object>([
      _store.loadFontSize(),
      _store.loadLineHeight(),
      _store.loadReaderMode(),
      _store.loadReaderTheme(),
    ]);
    if (!mounted) return;
    setState(() {
      _fontSize = settings[0] as double;
      _lineHeight = settings[1] as double;
      _mode = settings[2] as String;
      _readerTheme = settings[3] as String;
    });
    if (widget.chapters.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    await _loadChapter(_chapterIndex, position: _position);
  }

  Future<void> _loadChapter(int index, {double position = 0}) async {
    if (index < 0 || index >= widget.chapters.length) return;
    setState(() {
      _chapterIndex = index;
      _position = position.clamp(0.0, 1.0);
      _loading = true;
      _error = null;
      _content = null;
      _pages = const [];
    });
    try {
      final content =
          await _api.getContent(widget.book, widget.chapters[index]);
      if (!mounted) return;
      setState(() {
        _content = content;
        _pages = _paginate(content.text);
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_mode == 'page' &&
            _pages.isNotEmpty &&
            _pageController.hasClients) {
          final page = ((_pages.length - 1) * _position).round();
          _pageController.jumpToPage(page);
        } else if (_mode == 'scroll' && _scrollController.hasClients) {
          final offset = _scrollController.position.maxScrollExtent * _position;
          _scrollController.jumpTo(offset);
        }
      });
      _saveProgress(_position);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<String> _paginate(String text) {
    if (text.isEmpty) return const ['正文为空'];
    final maxCharacters =
        (850 * (18 / _fontSize) * (1.9 / _lineHeight)).round().clamp(360, 1300);
    final chunks = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = (start + maxCharacters).clamp(0, text.length);
      if (end < text.length) {
        final newline = text.lastIndexOf('\n', end);
        if (newline > start + maxCharacters ~/ 2) end = newline;
      }
      chunks.add(text.substring(start, end).trim());
      start = end;
      while (start < text.length && text[start] == '\n') {
        start++;
      }
    }
    return chunks.where((chunk) => chunk.isNotEmpty).toList(growable: false);
  }

  void _saveProgress(double position) {
    if (widget.chapters.isEmpty) return;
    final chapter = _chapter;
    _store.save(
      BookProgress(
        book: widget.book,
        chapterIndex: _chapterIndex,
        chapterTitle: chapter.title,
        position: position.clamp(0.0, 1.0),
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _onPageChanged(int page) {
    if (_pages.length <= 1) return;
    _position = page / (_pages.length - 1);
    _saveProgress(_position);
  }

  void _onScrollChanged(ScrollNotification notification) {
    if (notification.metrics.maxScrollExtent <= 0) {
      _position = 0;
    } else {
      _position =
          (notification.metrics.pixels / notification.metrics.maxScrollExtent)
              .clamp(0.0, 1.0);
    }
    if (notification is ScrollEndNotification) _saveProgress(_position);
  }

  Future<void> _setFontSize(double value) async {
    final size = value.roundToDouble();
    setState(() {
      _fontSize = size;
      if (_content != null) _pages = _paginate(_content!.text);
    });
    await _store.saveFontSize(size);
  }

  Future<void> _setLineHeight(double value) async {
    final lineHeight = double.parse(value.toStringAsFixed(1));
    setState(() {
      _lineHeight = lineHeight;
      if (_content != null) _pages = _paginate(_content!.text);
    });
    await _store.saveLineHeight(lineHeight);
  }

  Future<void> _setReaderTheme(String value) async {
    setState(() => _readerTheme = value);
    await _store.saveReaderTheme(value);
  }

  Future<void> _setMode(String mode) async {
    if (_mode == mode) return;
    final previous = _position;
    setState(() {
      _mode = mode;
      _position = previous;
    });
    await _store.saveReaderMode(mode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (mode == 'page' && _pageController.hasClients && _pages.isNotEmpty) {
        _pageController.jumpToPage(((_pages.length - 1) * previous).round());
      } else if (mode == 'scroll' && _scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent * previous,
        );
      }
    });
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '阅读设置',
                style: TextStyle(
                  fontSize: TypeScale.title,
                  fontWeight: TypeScale.bold,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text('字号'),
                  Expanded(
                    child: Slider(
                      value: _fontSize,
                      min: 14,
                      max: 30,
                      divisions: 16,
                      label: '${_fontSize.toInt()}',
                      onChanged: (value) {
                        setSheetState(() {});
                        _setFontSize(value);
                      },
                    ),
                  ),
                  Text('${_fontSize.toInt()}'),
                ],
              ),
              Row(
                children: [
                  const Text('行距'),
                  Expanded(
                    child: Slider(
                      value: _lineHeight,
                      min: 1.4,
                      max: 2.4,
                      divisions: 10,
                      label: _lineHeight.toStringAsFixed(1),
                      onChanged: (value) {
                        setSheetState(() {});
                        _setLineHeight(value);
                      },
                    ),
                  ),
                  Text(_lineHeight.toStringAsFixed(1)),
                ],
              ),
              const SizedBox(height: 12),
              GSegmented(
                items: const ['滚动', '翻页'],
                selected: _mode == 'scroll' ? 0 : 1,
                onSelected: (index) {
                  setSheetState(() {});
                  _setMode(index == 0 ? 'scroll' : 'page');
                },
              ),
              const SizedBox(height: 14),
              GSegmented(
                items: const ['跟随系统', '护眼', '夜间'],
                selected: switch (_readerTheme) {
                  'paper' => 1,
                  'night' => 2,
                  _ => 0,
                },
                onSelected: (index) {
                  setSheetState(() {});
                  _setReaderTheme(switch (index) {
                    1 => 'paper',
                    2 => 'night',
                    _ => 'system',
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveProgress(_position);
    _pageController.dispose();
    _scrollController.dispose();
    _readerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final readerBackground = switch (_readerTheme) {
      'paper' => const Color(0xFFF2F1E8),
      'night' => const Color(0xFF101112),
      _ => scheme.surface,
    };
    final chapterTitle =
        _content?.title.isNotEmpty == true ? _content!.title : _chapter.title;
    return Scaffold(
      backgroundColor: readerBackground,
      appBar: GAppBar(
        titleWidget: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.book.name),
            Text(
              chapterTitle,
              style: TextStyle(
                fontSize: TypeScale.caption,
                fontWeight: TypeScale.regular,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        onBack: () => Navigator.of(context).maybePop(),
        actions: [
          GIconButton(
            icon: Icons.tune_rounded,
            tooltip: '阅读设置',
            onTap: _showSettings,
          ),
        ],
      ),
      body: Focus(
        focusNode: _readerFocusNode,
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.pageDown) {
            _loadChapter(_chapterIndex + 1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.pageUp) {
            _loadChapter(_chapterIndex - 1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: _buildBody(),
      ),
      bottomNavigationBar: _buildNavigation(),
    );
  }

  Widget _buildBody() {
    if (widget.chapters.isEmpty) {
      return const GEmptyState(
        icon: Icons.menu_book_outlined,
        title: '暂无可读章节',
        text: '这本书暂时没有可用的章节内容',
      );
    }
    if (_loading) return const GLoading();
    if (_error != null) {
      return GEmptyState(
        icon: Icons.error_outline_rounded,
        title: '正文加载失败',
        text: _error!,
        onRetry: () => _loadChapter(_chapterIndex, position: _position),
      );
    }
    if (_mode == 'page') {
      return PageView.builder(
        controller: _pageController,
        itemCount: _pages.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) => _PageText(
          text: _pages[index],
          fontSize: _fontSize,
          lineHeight: _lineHeight,
          foreground: _readerForeground(context),
          page: index + 1,
          total: _pages.length,
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _onScrollChanged(notification);
        return false;
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 44),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SelectableText(
              _content?.text ?? '',
              style: TextStyle(
                fontSize: _fontSize,
                height: _lineHeight,
                color: _readerForeground(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _readerForeground(BuildContext context) => switch (_readerTheme) {
        'paper' => const Color(0xFF292A25),
        'night' => const Color(0xFFE4E4E4),
        _ => Theme.of(context).colorScheme.onSurface,
      };

  Widget _buildNavigation() {
    if (widget.chapters.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 7),
        decoration: BoxDecoration(
          color: glassFill(context, alpha: 0.1),
          border: Border(top: BorderSide(color: glassHairline(context))),
        ),
        child: Row(
          children: [
            GIconButton(
              icon: Icons.chevron_left_rounded,
              tooltip: '上一章',
              disabled: _chapterIndex == 0 || _loading,
              onTap: () => _loadChapter(_chapterIndex - 1),
            ),
            Expanded(
              child: Text(
                '${_chapterIndex + 1} / ${widget.chapters.length}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: TypeScale.small,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            GIconButton(
              icon: Icons.chevron_right_rounded,
              tooltip: '下一章',
              disabled: _chapterIndex >= widget.chapters.length - 1 || _loading,
              onTap: () => _loadChapter(_chapterIndex + 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageText extends StatelessWidget {
  const _PageText({
    required this.text,
    required this.fontSize,
    required this.lineHeight,
    required this.foreground,
    required this.page,
    required this.total,
  });

  final String text;
  final double fontSize;
  final double lineHeight;
  final Color foreground;
  final int page;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SingleChildScrollView(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: fontSize,
                      height: lineHeight,
                      color: foreground,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$page / $total',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: TypeScale.caption,
              color: scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
