import 'package:flutter/material.dart';

import '../../core/api/book_api.dart';
import '../../core/models/book.dart';
import '../../core/models/book_progress.dart';
import '../../core/models/book_discover.dart';
import '../../core/models/book_user_source.dart';
import '../../widgets/glass.dart';
import 'book_detail_view.dart';
import 'book_progress_store.dart';
import 'widgets/book_cover.dart';

/// The class name is retained because the tools page already links to it.
class BookSourcesView extends StatefulWidget {
  const BookSourcesView({super.key});

  @override
  State<BookSourcesView> createState() => _BookSourcesViewState();
}

class _BookSourcesViewState extends State<BookSourcesView> {
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();
  final _api = BookApi();

  List<Book> _books = const [];
  List<Book> _bookshelf = const [];
  List<BookProgress> _recent = const [];
  bool _searched = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;
  BookDiscover? _discover;
  bool _discoverLoading = false;
  String? _discoverError;
  String _mode = 'discover';
  String _discoverSection = 'home';
  String? _selectedCategory;
  List<BookUserSource> _userSources = const [];
  String _selectedSourceId = '7630';

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _loadUserSources();
    _loadDiscover();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    final values = await Future.wait<Object>([
      BookProgressStore.instance.loadBookshelf(),
      BookProgressStore.instance.loadRecent(),
    ]);
    if (!mounted) return;
    setState(() {
      _bookshelf = values[0] as List<Book>;
      _recent = values[1] as List<BookProgress>;
    });
  }

  Future<void> _loadDiscover({String? section, String? category}) async {
    if (_discoverLoading) return;
    setState(() {
      _discoverLoading = true;
      _discoverError = null;
      if (section != null) _discoverSection = section;
      if (category != null) _selectedCategory = category;
    });
    try {
      final result = await _api.discover(
        section: _discoverSection,
        category: _selectedCategory,
      );
      if (!mounted) return;
      setState(() => _discover = result);
    } catch (error) {
      if (mounted) setState(() => _discoverError = error.toString());
    } finally {
      if (mounted) setState(() => _discoverLoading = false);
    }
  }

  Future<void> _loadUserSources() async {
    try {
      final sources = await _api.listUserSources();
      if (!mounted) return;
      _setUserSources(sources);
    } catch (_) {
      // Source management is optional; the curated source remains available.
    }
  }

  void _setUserSources(List<BookUserSource> sources) {
    final readyIds = sources
        .where((source) => source.ready)
        .map((source) => source.sourceId)
        .toSet();
    final selected =
        _selectedSourceId == '7630' || readyIds.contains(_selectedSourceId)
            ? _selectedSourceId
            : '7630';
    setState(() {
      _userSources = sources;
      _selectedSourceId = selected;
    });
  }

  Future<void> _showSourceManager() async {
    try {
      final sources = await _api.listUserSources();
      if (!mounted) return;
      _setUserSources(sources);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 720),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SourceManagerSheet(
        api: _api,
        sources: _userSources,
        onChanged: () async {
          final latest = await _api.listUserSources();
          if (mounted) _setUserSources(latest);
        },
      ),
    );
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 320) _loadMore();
  }

  Future<void> _search() async {
    final keyword = _queryController.text.trim();
    if (keyword.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searched = true;
      _loading = true;
      _error = null;
      _books = const [];
      _page = 1;
      _hasMore = false;
    });
    try {
      final result = await _api.search(keyword, sourceId: _selectedSourceId);
      if (!mounted) return;
      setState(() {
        _books = result.books;
        _page = result.page;
        _hasMore = result.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loading || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _api.search(
        _queryController.text,
        page: _page + 1,
        sourceId: _selectedSourceId,
      );
      if (!mounted) return;
      setState(() {
        _books = [..._books, ...result.books];
        _page = result.page;
        _hasMore = result.hasMore;
      });
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openBook(Book book) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => BookDetailView(book: book)),
    );
    _loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GAppBar(
        title: '小说阅读',
        onBack: () => Navigator.of(context).maybePop(),
        actions: [
          IconButton(
            tooltip: '书源管理',
            onPressed: _showSourceManager,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'discover',
                      label: Text('发现'),
                      icon: Icon(Icons.explore_rounded)),
                  ButtonSegment(
                      value: 'search',
                      label: Text('搜索'),
                      icon: Icon(Icons.search_rounded)),
                ],
                selected: {_mode},
                onSelectionChanged: (value) => setState(() {
                  _mode = value.first;
                  if (_mode == 'discover' && _discover == null) _loadDiscover();
                }),
              ),
            ),
            if (_mode == 'search')
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _queryController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        decoration: InputDecoration(
                          hintText: '搜索书名或作者',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _queryController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清空',
                                  onPressed: () {
                                    _queryController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GButton(
                      label: '搜索',
                      icon: Icons.search_rounded,
                      loading: _loading,
                      onTap: _loading ? null : _search,
                    ),
                  ],
                ),
              ),
            if (_mode == 'search' && _userSources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DropdownButton<String>(
                    value: _selectedSourceId,
                    isDense: true,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedSourceId = value);
                      }
                    },
                    items: [
                      const DropdownMenuItem(value: '7630', child: Text('品书斋')),
                      ..._userSources
                          .where((item) => item.ready)
                          .map((item) => DropdownMenuItem(
                                value: item.sourceId,
                                child: Text(item.name),
                              )),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Expanded(
                child: _mode == 'discover'
                    ? _buildDiscoverBody()
                    : _buildSearchBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const GLoading();
    if (_error != null) {
      return GEmptyState(
        icon: Icons.cloud_off_rounded,
        title: '搜索失败',
        text: _error!,
        onRetry: _search,
      );
    }
    if (!_searched) {
      return _BookLibrary(
        bookshelf: _bookshelf,
        recent: _recent,
        onOpen: _openBook,
      );
    }
    if (_books.isEmpty) {
      return const GEmptyState(
        icon: Icons.search_off_rounded,
        title: '没有找到小说',
        text: '换一个书名或作者试试',
      );
    }
    return ListView.separated(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      itemCount: _books.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == _books.length) return const GLoading(padding: 18);
        final book = _books[index];
        return _BookResultTile(book: book, onTap: () => _openBook(book));
      },
    );
  }

  Widget _buildSearchBody() => _buildBody();

  Widget _buildDiscoverBody() {
    if (_discoverLoading && _discover == null) return const GLoading();
    if (_discoverError != null && _discover == null) {
      return GEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '发现加载失败',
          text: _discoverError!,
          onRetry: _loadDiscover);
    }
    final discover = _discover;
    if (discover == null) return const GLoading();
    return RefreshIndicator(
      onRefresh: _loadDiscover,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
        children: [
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final item in const [
                ('home', '首页', Icons.home_rounded),
                ('recommend', '推荐', Icons.auto_awesome_rounded),
                ('ranking', '排行榜', Icons.emoji_events_rounded),
              ]) ...[
                ChoiceChip(
                  label: Text(item.$2),
                  avatar: Icon(item.$3, size: 17),
                  selected: _discoverSection == item.$1,
                  onSelected: (_) => _loadDiscover(section: item.$1),
                ),
                const SizedBox(width: 8),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Text('分类', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: discover.categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = discover.categories[index];
                return ChoiceChip(
                  label: Text(item.name),
                  selected: _selectedCategory == item.key &&
                      _discoverSection == 'category',
                  onSelected: (_) =>
                      _loadDiscover(section: 'category', category: item.key),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          for (final section in discover.sections) ...[
            Row(children: [
              Expanded(
                  child: Text(section.title,
                      style: Theme.of(context).textTheme.titleLarge)),
              if (section.books.isNotEmpty)
                Text('${section.books.length} 本',
                    style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 8),
            if (section.books.isEmpty)
              const Text('暂时没有内容')
            else
              ...section.books.map((book) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _BookResultTile(
                        book: book, onTap: () => _openBook(book)),
                  )),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _BookLibrary extends StatelessWidget {
  const _BookLibrary({
    required this.bookshelf,
    required this.recent,
    required this.onOpen,
  });

  final List<Book> bookshelf;
  final List<BookProgress> recent;
  final ValueChanged<Book> onOpen;

  @override
  Widget build(BuildContext context) {
    if (bookshelf.isEmpty && recent.isEmpty) {
      return const GEmptyState(
        icon: Icons.menu_book_rounded,
        title: '开始读一本小说',
        text: '切换到搜索后输入书名或作者，或先浏览发现内容',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        if (bookshelf.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '我的书架',
              style: TextStyle(
                fontSize: TypeScale.title,
                fontWeight: TypeScale.bold,
              ),
            ),
          ),
          for (final book in bookshelf) ...[
            _BookResultTile(book: book, onTap: () => onOpen(book)),
            const SizedBox(height: 10),
          ],
        ],
        if (recent.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.only(
              top: bookshelf.isEmpty ? 0 : 18,
              bottom: 12,
            ),
            child: const Text(
              '最近阅读',
              style: TextStyle(
                fontSize: TypeScale.title,
                fontWeight: TypeScale.bold,
              ),
            ),
          ),
        ],
        for (final progress in recent) ...[
          _BookResultTile(
            book: progress.book,
            progress: progress,
            onTap: () => onOpen(progress.book),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SourceManagerSheet extends StatefulWidget {
  const _SourceManagerSheet(
      {required this.api, required this.sources, required this.onChanged});

  final BookApi api;
  final List<BookUserSource> sources;
  final Future<void> Function() onChanged;

  @override
  State<_SourceManagerSheet> createState() => _SourceManagerSheetState();
}

class _SourceManagerSheetState extends State<_SourceManagerSheet> {
  final _controller = TextEditingController();
  bool _importing = false;
  late List<BookUserSource> _sources;

  @override
  void initState() {
    super.initState();
    _sources = [...widget.sources];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final value = _controller.text.trim();
    if (value.isEmpty || _importing) return;
    setState(() => _importing = true);
    try {
      final source = await widget.api.importUserSource(value);
      if (!mounted) return;
      setState(() {
        _sources = [source, ..._sources.where((item) => item.id != source.id)];
        _controller.clear();
      });
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(source.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text('书源管理',
                      style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded)),
            ]),
            Text('粘贴 Legado 书源 JSON。含 @js、java 或 Packages 的规则会被标记为不支持。',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              minLines: 5,
              maxLines: 9,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '{"bookSourceName":"..."}'),
            ),
            const SizedBox(height: 10),
            SizedBox(
                width: double.infinity,
                child: GButton(
                    label: '导入书源',
                    icon: Icons.file_download_rounded,
                    loading: _importing,
                    onTap: _importing ? null : _import)),
            const SizedBox(height: 18),
            Text('已导入书源', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_sources.isEmpty)
              const Text('还没有自定义书源')
            else
              ..._sources.map((source) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        source.ready
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        color: source.ready
                            ? scheme.primary
                            : scheme.outline),
                    title: Text(source.name),
                    subtitle: Text(
                        source.ready ? '可用 · ${source.url}' : source.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Switch(
                          value: source.enabled,
                          onChanged: source.ready
                              ? (value) async {
                                  try {
                                    final updated = await widget.api
                                        .setUserSourceEnabled(source.id, value);
                                    if (mounted) {
                                      setState(() => _sources = _sources
                                          .map((item) => item.id == source.id
                                              ? updated
                                              : item)
                                          .toList());
                                    }
                                    await widget.onChanged();
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(error.toString())));
                                    }
                                  }
                                }
                              : null),
                      IconButton(
                          tooltip: '删除',
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('删除书源？'),
                                content:
                                    Text('将移除“${source.name}”，不会影响书架中的已有记录。'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            try {
                              await widget.api.deleteUserSource(source.id);
                              if (mounted) {
                                setState(() => _sources.removeWhere(
                                    (item) => item.id == source.id));
                              }
                              await widget.onChanged();
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error.toString())),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.delete_outline_rounded)),
                    ]),
                  )),
          ]),
        ),
      ),
    );
  }
}

class _BookResultTile extends StatelessWidget {
  const _BookResultTile({
    required this.book,
    required this.onTap,
    this.progress,
  });

  final Book book;
  final BookProgress? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = [
      if (book.author.isNotEmpty) book.author,
      if (book.category.isNotEmpty) book.category,
      if (book.status.isNotEmpty) book.status,
    ].join(' · ');
    return GSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      radius: RadiusToken.md,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCover(url: book.coverUrl, width: 62, height: 84),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: 84,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          book.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: TypeScale.subhead,
                            fontWeight: TypeScale.semibold,
                          ),
                        ),
                      ),
                      if (book.sourceName.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          book.sourceName,
                          style: TextStyle(
                            fontSize: TypeScale.caption,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    details.isEmpty ? '作者未知' : details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: TypeScale.small,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    progress != null
                        ? '读到 ${progress!.chapterTitle.isEmpty ? '第 ${progress!.chapterIndex + 1} 章' : progress!.chapterTitle}'
                        : (book.latestChapter.isEmpty
                            ? (book.intro.isEmpty ? '查看详情与目录' : book.intro)
                            : '最新：${book.latestChapter}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: TypeScale.small,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: scheme.outline),
        ],
      ),
    );
  }
}
