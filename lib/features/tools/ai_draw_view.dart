import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api/ai_draw_api.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../widgets/glass.dart';

enum _AiDrawMode { generate, edit, history }

class AiDrawView extends StatefulWidget {
  const AiDrawView({super.key, this.api});

  final AiDrawApi? api;

  @override
  State<AiDrawView> createState() => _AiDrawViewState();
}

class _AiDrawViewState extends State<AiDrawView> {
  static const _sizes = <String>[
    '1024x1024',
    '1536x1024',
    '1024x1536',
    '1792x1024',
    '1024x1792',
  ];

  final _prompt = TextEditingController();
  late final AiDrawApi _api = widget.api ?? AiDrawApi();
  _AiDrawMode _mode = _AiDrawMode.generate;
  List<AiDrawModel> _models = const [];
  List<AiDrawTaskRecord> _tasks = const [];
  List<AiDrawHistoryItem> _history = const [];
  String? _selectedModel;
  String _selectedSize = _sizes.first;
  int _count = 1;
  Uint8List? _sourceBytes;
  String? _sourceName;
  String? _imageUrl;
  String? _error;
  bool _loading = false;
  bool _initialLoading = false;
  bool _historyLoading = false;
  bool _controlsExpanded = false;
  int _historyPage = 0;
  int _historyTotal = 0;
  bool _restoringTasks = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<AuthController>().isLoggedIn) {
        unawaited(_loadWorkspace());
      }
    });
  }

  Future<void> _loadWorkspace() async {
    if (_initialLoading) return;
    setState(() => _initialLoading = true);
    final results = await Future.wait<Object?>([
      _api.models().catchError((_) => <AiDrawModel>[]),
      _api.tasks().catchError((_) => const AiDrawPage<AiDrawTaskRecord>(
            items: [],
            total: 0,
            page: 0,
            size: 20,
          )),
      _api.history().catchError((_) => const AiDrawPage<AiDrawHistoryItem>(
            items: [],
            total: 0,
            page: 0,
            size: 20,
          )),
    ]);
    if (!mounted) return;
    final taskPage = results[1] as AiDrawPage<AiDrawTaskRecord>;
    final historyPage = results[2] as AiDrawPage<AiDrawHistoryItem>;
    setState(() {
      _models = results[0] as List<AiDrawModel>;
      _tasks = taskPage.items;
      _history = historyPage.items;
      _historyPage = historyPage.page;
      _historyTotal = historyPage.total;
      _initialLoading = false;
    });
    if (_tasks.any((task) => task.isProcessing)) {
      unawaited(_resumeTasks());
    }
  }

  Future<void> _resumeTasks() async {
    if (_restoringTasks) return;
    _restoringTasks = true;
    try {
      for (var attempt = 0; attempt < 60 && mounted; attempt++) {
        final active = _tasks.where((task) => task.isProcessing).toList();
        if (active.isEmpty) break;
        var completedImage = _imageUrl;
        for (final record in active) {
          try {
            final task = await _api.task(record.id);
            if (task.status == 'COMPLETED') {
              completedImage = task.imageSource ?? completedImage;
            }
          } catch (_) {}
        }
        if (!mounted) break;
        if (completedImage != _imageUrl) {
          setState(() => _imageUrl = completedImage);
        }
        await Future.wait([_refreshTasks(), _loadHistory()]);
        if (!_tasks.any((task) => task.isProcessing)) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } finally {
      _restoringTasks = false;
    }
  }

  Future<void> _refreshTasks() async {
    try {
      final page = await _api.tasks();
      if (mounted) setState(() => _tasks = page.items);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _loadHistory({int page = 0}) async {
    if (_historyLoading) return;
    setState(() => _historyLoading = true);
    try {
      final result = await _api.history(page: page);
      if (!mounted) return;
      setState(() {
        _history = result.items;
        _historyPage = result.page;
        _historyTotal = result.total;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _submit() async {
    final prompt = _prompt.text.trim();
    if (_loading || prompt.isEmpty) {
      if (prompt.isEmpty) setState(() => _error = '写下你想生成的画面');
      return;
    }
    if (!context.read<AuthController>().isLoggedIn) {
      setState(() => _error = '请先登录后使用生图功能');
      return;
    }
    if (_mode == _AiDrawMode.edit && _sourceBytes == null) {
      setState(() => _error = '请先选择要编辑的图片');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _imageUrl = null;
    });
    try {
      final url = _mode == _AiDrawMode.edit
          ? await _api.edit(
              bytes: _sourceBytes!,
              filename: _sourceName ?? 'source.png',
              prompt: prompt,
              model: _selectedModel,
              size: _selectedSize,
              n: _count,
            )
          : await _api.generate(
              prompt,
              model: _selectedModel,
              size: _selectedSize,
              n: _count,
            );
      if (!mounted) return;
      setState(() => _imageUrl = url);
      await Future.wait([_loadHistory(), _refreshTasks()]);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
      await _refreshTasks();
    } catch (_) {
      if (mounted) setState(() => _error = '图片任务未完成，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _retry(AiDrawTaskRecord task) async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await _api.retry(task.id);
      await _refreshTasks();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleShare(AiDrawHistoryItem item) async {
    try {
      await _api.setShared(item.id, !item.isShared);
      if (!mounted) return;
      setState(() {
        _history = [
          for (final value in _history)
            if (value.id == item.id)
              value.copyWith(isShared: !value.isShared)
            else
              value,
        ];
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _deleteHistory(AiDrawHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这张图片？'),
        content: const Text('历史记录会从当前账号移除，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteHistory(item.id);
      if (!mounted) return;
      setState(() {
        _history = _history.where((value) => value.id != item.id).toList();
        _historyTotal = (_historyTotal - 1).clamp(0, 1 << 31);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _pickSourceImage() async {
    if (_loading) return;
    try {
      final file = await _pickImageFile();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final extension = _imageExtension(file);
      if (!mounted) return;
      if (bytes.isEmpty || extension == null) {
        setState(() => _error = '请选择 JPG、PNG、WebP 或 GIF 图片');
        return;
      }
      setState(() {
        _sourceBytes = bytes;
        _sourceName =
            file.name.trim().isEmpty ? 'source.$extension' : file.name.trim();
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取所选图片，请重新选择');
    }
  }

  Future<XFile?> _pickImageFile() {
    final mobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (mobile) return ImagePicker().pickImage(source: ImageSource.gallery);
    return openFile(acceptedTypeGroups: <XTypeGroup>[_imageTypeGroup()]);
  }

  XTypeGroup _imageTypeGroup() {
    if (kIsWeb) {
      return const XTypeGroup(label: 'images', webWildCards: ['image/*']);
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return const XTypeGroup(
        label: 'images',
        uniformTypeIdentifiers: ['public.image'],
      );
    }
    return const XTypeGroup(
      label: 'images',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
    );
  }

  String? _imageExtension(XFile file) {
    final dot = file.name.lastIndexOf('.');
    if (dot >= 0) {
      final extension = file.name.substring(dot + 1).toLowerCase();
      if (const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(extension)) {
        return extension;
      }
    }
    return switch (file.mimeType?.toLowerCase()) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => null,
    };
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _LabColors.of(context);
    return Scaffold(
      backgroundColor: colors.paper,
      appBar: GAppBar(
        title: '图像实验室',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            return Column(
              children: [
                _buildHeader(compact, colors),
                if (_initialLoading)
                  LinearProgressIndicator(
                    minHeight: 2,
                    color: colors.accent,
                    backgroundColor: colors.rule,
                  ),
                Expanded(
                  child: _mode == _AiDrawMode.history
                      ? _buildHistory(compact, colors)
                      : _buildWorkbench(compact, colors),
                ),
                if (_mode != _AiDrawMode.history) _buildQueue(compact, colors),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool compact, _LabColors colors) {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(compact ? 16 : 24, 12, compact ? 16 : 24, 12),
      child: Row(
        children: [
          if (!compact) ...[
            Text(
              'DUCK / IMAGE LAB',
              style: TextStyle(
                color: colors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const Spacer(),
          ] else
            const Spacer(),
          SegmentedButton<_AiDrawMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _AiDrawMode.generate,
                icon: Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text('生成'),
              ),
              ButtonSegment(
                value: _AiDrawMode.edit,
                icon: Icon(Icons.tune_rounded, size: 18),
                label: Text('编辑'),
              ),
              ButtonSegment(
                value: _AiDrawMode.history,
                icon: Icon(Icons.photo_library_outlined, size: 18),
                label: Text('历史'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _loading
                ? null
                : (value) {
                    setState(() {
                      _mode = value.first;
                      _error = null;
                    });
                    if (_mode == _AiDrawMode.history) unawaited(_loadHistory());
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildWorkbench(bool compact, _LabColors colors) {
    final canvas = _buildCanvas(colors);
    final controls = _buildControls(colors, compact: compact);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 4, compact ? 16 : 24, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: compact
              ? Column(
                  children: [
                    canvas,
                    const SizedBox(height: 12),
                    _LabPanel(
                      colors: colors,
                      padding: EdgeInsets.zero,
                      child: ExpansionTile(
                        initiallyExpanded: _controlsExpanded,
                        onExpansionChanged: (value) =>
                            setState(() => _controlsExpanded = value),
                        title: const Text(
                          '生成参数',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text('$_selectedSize · $_count 张'),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [controls],
                      ),
                    ),
                  ],
                )
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 7, child: canvas),
                      const SizedBox(width: 16),
                      SizedBox(width: 300, child: controls),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCanvas(_LabColors colors) {
    return _LabPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Container(
              decoration: BoxDecoration(
                color: colors.canvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.rule),
              ),
              clipBehavior: Clip.antiAlias,
              child: _loading
                  ? _buildGeneratingState(colors)
                  : _imageUrl != null
                      ? _buildImage(_imageUrl!)
                      : _buildEmptyCanvas(colors),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('ai-prompt-field'),
            controller: _prompt,
            minLines: 3,
            maxLines: 6,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: _mode == _AiDrawMode.edit ? '修改描述' : '画面描述',
              hintText: _mode == _AiDrawMode.edit
                  ? '例如：保留主体，把背景改成雨夜街道'
                  : '例如：像唱片封面一样的夜色城市，35mm 胶片颗粒',
              alignLabelWithHint: true,
              filled: true,
              fillColor: colors.canvas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: colors.error, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: const Key('ai-submit-button'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.onAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _loading ? null : _submit,
              icon: Icon(_mode == _AiDrawMode.edit
                  ? Icons.tune_rounded
                  : Icons.auto_awesome_rounded),
              label: Text(_loading
                  ? '任务处理中'
                  : _mode == _AiDrawMode.edit
                      ? '编辑图片'
                      : '生成 $_count 张图片'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCanvas(_LabColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _mode == _AiDrawMode.edit
                  ? Icons.image_search_outlined
                  : Icons.crop_original_rounded,
              size: 40,
              color: colors.muted,
            ),
            const SizedBox(height: 12),
            Text(
              _mode == _AiDrawMode.edit ? '选择图片，再描述修改方向' : '你的画面会出现在这里',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _mode == _AiDrawMode.edit
                  ? '支持 JPG、PNG、WebP 和 GIF'
                  : '先写下一句具体的画面描述',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratingState(_LabColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colors.accent, strokeWidth: 2.5),
          const SizedBox(height: 14),
          Text(
            _mode == _AiDrawMode.edit ? '正在编辑图片' : '正在生成画面',
            style: TextStyle(color: colors.ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('离开页面后可从任务队列继续查看',
              style: TextStyle(color: colors.muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildControls(_LabColors colors, {required bool compact}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ControlLabel('模型', colors),
        DropdownButtonFormField<String>(
          key: const Key('ai-model-field'),
          initialValue: _selectedModel,
          isExpanded: true,
          hint: const Text('系统默认模型'),
          items: [
            for (final model in _models)
              DropdownMenuItem(
                value: model.id,
                child: Text(model.id, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _loading
              ? null
              : (value) => setState(() => _selectedModel = value),
        ),
        const SizedBox(height: 16),
        _ControlLabel('画布尺寸', colors),
        DropdownButtonFormField<String>(
          key: const Key('ai-size-field'),
          initialValue: _selectedSize,
          items: [
            for (final size in _sizes)
              DropdownMenuItem(value: size, child: Text(_sizeLabel(size))),
          ],
          onChanged: _loading
              ? null
              : (value) => setState(() => _selectedSize = value!),
        ),
        const SizedBox(height: 16),
        _ControlLabel('图片数量', colors),
        SegmentedButton<int>(
          key: const Key('ai-count-field'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 1, label: Text('1')),
            ButtonSegment(value: 2, label: Text('2')),
            ButtonSegment(value: 3, label: Text('3')),
          ],
          selected: {_count},
          onSelectionChanged:
              _loading ? null : (value) => setState(() => _count = value.first),
        ),
        if (_mode == _AiDrawMode.edit) ...[
          const SizedBox(height: 16),
          _ControlLabel('源图片', colors),
          OutlinedButton.icon(
            key: const Key('ai-source-picker'),
            onPressed: _loading ? null : _pickSourceImage,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              _sourceName ?? '选择图片',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_sourceBytes != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _sourceBytes!,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
        ],
        const SizedBox(height: 20),
        Divider(color: colors.rule),
        const SizedBox(height: 8),
        Text(
          '任务完成后自动保存到历史。普通会员每日可提交 1 次，单次可生成 1–3 张。',
          style: TextStyle(color: colors.muted, fontSize: 12, height: 1.45),
        ),
      ],
    );
    if (compact) return content;
    return _LabPanel(colors: colors, child: content);
  }

  Widget _buildQueue(bool compact, _LabColors colors) {
    final cards = <Widget>[
      for (final task in _tasks)
        _TaskCard(
          task: task,
          colors: colors,
          loading: _loading,
          onRetry: task.isFailed ? () => _retry(task) : null,
        ),
      _QueueHistoryCard(
        colors: colors,
        count: _historyTotal,
        onTap: () {
          setState(() => _mode = _AiDrawMode.history);
          unawaited(_loadHistory());
        },
      ),
    ];
    return Container(
      height: compact ? 112 : 104,
      decoration: BoxDecoration(
        color: colors.queue,
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      child: ListView.separated(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 24,
          vertical: 12,
        ),
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, index) => cards[index],
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: cards.length,
      ),
    );
  }

  Widget _buildHistory(bool compact, _LabColors colors) {
    if (_historyLoading && _history.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined, size: 44, color: colors.muted),
              const SizedBox(height: 12),
              Text('还没有生成记录',
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 6),
              Text('完成的图片会自动出现在这里', style: TextStyle(color: colors.muted)),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1100
          ? 4
          : constraints.maxWidth >= 760
              ? 3
              : constraints.maxWidth >= 460
                  ? 2
                  : 1;
      return Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 24, 4, compact ? 16 : 24, 16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: columns == 1 ? 1.35 : 0.8,
              ),
              itemCount: _history.length,
              itemBuilder: (_, index) => _HistoryCard(
                item: _history[index],
                colors: colors,
                image: _buildImage(_history[index].imageUrl),
                onCopy: () => Clipboard.setData(
                  ClipboardData(text: _history[index].imageUrl),
                ),
                onShare: () => _toggleShare(_history[index]),
                onDelete: () => _deleteHistory(_history[index]),
              ),
            ),
          ),
          if (_historyTotal > 20)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: '上一页',
                    onPressed: _historyPage > 0
                        ? () => _loadHistory(page: _historyPage - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('第 ${_historyPage + 1} 页'),
                  ),
                  IconButton.filledTonal(
                    tooltip: '下一页',
                    onPressed: (_historyPage + 1) * 20 < _historyTotal
                        ? () => _loadHistory(page: _historyPage + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  String _sizeLabel(String size) {
    final parts = size.split('x');
    if (parts.length != 2) return size;
    final width = int.tryParse(parts[0]) ?? 0;
    final height = int.tryParse(parts[1]) ?? 0;
    final shape = width == height
        ? '方形'
        : width > height
            ? '横向'
            : '纵向';
    return '$shape  $size';
  }

  Widget _buildImage(String source) {
    if (source.startsWith('data:image/')) {
      final separator = source.indexOf(',');
      if (separator > 0) {
        try {
          return Image.memory(
            base64Decode(source.substring(separator + 1)),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _BrokenImage(),
          );
        } catch (_) {}
      }
    }
    return Image.network(
      source,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _BrokenImage(),
    );
  }
}

class _LabColors {
  const _LabColors({
    required this.paper,
    required this.canvas,
    required this.queue,
    required this.ink,
    required this.muted,
    required this.rule,
    required this.accent,
    required this.onAccent,
    required this.error,
  });

  final Color paper;
  final Color canvas;
  final Color queue;
  final Color ink;
  final Color muted;
  final Color rule;
  final Color accent;
  final Color onAccent;
  final Color error;

  factory _LabColors.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const _LabColors(
            paper: Color(0xFF171915),
            canvas: Color(0xFF21231E),
            queue: Color(0xFF1D201B),
            ink: Color(0xFFF3F0E8),
            muted: Color(0xFFA7A59D),
            rule: Color(0xFF42443D),
            accent: Color(0xFFD97852),
            onAccent: Color(0xFFFFFFFF),
            error: Color(0xFFFF8A70),
          )
        : const _LabColors(
            paper: Color(0xFFF2F0E9),
            canvas: Color(0xFFFFFDF8),
            queue: Color(0xFFE7E3DA),
            ink: Color(0xFF24372D),
            muted: Color(0xFF77756D),
            rule: Color(0xFFD2CDC2),
            accent: Color(0xFFD97852),
            onAccent: Color(0xFFFFFFFF),
            error: Color(0xFFB64232),
          );
  }
}

class _LabPanel extends StatelessWidget {
  const _LabPanel({
    required this.colors,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final _LabColors colors;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class _ControlLabel extends StatelessWidget {
  const _ControlLabel(this.text, this.colors);

  final String text;
  final _LabColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: TextStyle(
          color: colors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.colors,
    required this.loading,
    this.onRetry,
  });

  final AiDrawTaskRecord task;
  final _LabColors colors;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.rule),
      ),
      child: Row(
        children: [
          Icon(
            task.isFailed ? Icons.error_outline : Icons.schedule_rounded,
            size: 20,
            color: task.isFailed ? colors.error : colors.accent,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.isFailed ? '失败 · #${task.id}' : '处理中 · #${task.id}',
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  task.prompt.isEmpty ? '图片任务' : task.prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            IconButton(
              tooltip: '重试任务',
              onPressed: loading ? null : onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}

class _QueueHistoryCard extends StatelessWidget {
  const _QueueHistoryCard({
    required this.colors,
    required this.count,
    required this.onTap,
  });

  final _LabColors colors;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: colors.canvas,
          foregroundColor: colors.ink,
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
        icon: const Icon(Icons.photo_library_outlined),
        label: Text('历史图片 · $count'),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.colors,
    required this.image,
    required this.onCopy,
    required this.onShare,
    required this.onDelete,
  });

  final AiDrawHistoryItem item;
  final _LabColors colors;
  final Widget image;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: image),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.prompt.isEmpty ? '未命名图片' : item.prompt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [item.size, item.model]
                            .where((value) => value?.isNotEmpty == true)
                            .join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '复制图片地址',
                  onPressed: onCopy,
                  icon: const Icon(Icons.link_rounded, size: 19),
                ),
                IconButton(
                  tooltip: item.isShared ? '停止公开分享' : '公开分享',
                  onPressed: onShare,
                  icon: Icon(
                    item.isShared
                        ? Icons.public_rounded
                        : Icons.public_off_outlined,
                    size: 19,
                    color: item.isShared ? colors.accent : null,
                  ),
                ),
                IconButton(
                  tooltip: '删除记录',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFE7E3DA),
      child: Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
