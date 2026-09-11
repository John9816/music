import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/api/ai_draw_api.dart';
import '../../core/api/api_client.dart';
import '../../core/api/image_host_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../widgets/glass.dart';

enum _AiDrawMode { generate, edit, history, plaza }

class AiDrawView extends StatefulWidget {
  const AiDrawView({super.key, this.api, this.imageHost});

  final AiDrawApi? api;
  final ImageHostApi? imageHost;

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
  late final ImageHostApi _imageHost = widget.imageHost ?? ImageHostApi();
  _AiDrawMode _mode = _AiDrawMode.generate;
  List<AiDrawModel> _models = const [];
  List<AiDrawTaskRecord> _tasks = const [];
  List<AiDrawHistoryItem> _history = const [];
  List<AiDrawHistoryItem> _shared = const [];
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
  bool _sharedLoading = false;
  int _historyPage = 0;
  int _historyTotal = 0;
  int _sharedPage = 0;
  int _sharedTotal = 0;
  bool _restoringTasks = false;

  /// 已转存图床的结果：原始地址 -> 图床直链，避免同一张图重复上传。
  final Map<String, String> _mirrored = {};
  bool _mirroring = false;
  String? _mirrorHost;

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
          if (completedImage != null) {
            unawaited(_mirrorToImageHost(completedImage));
          }
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

  Future<void> _loadShared({int page = 0}) async {
    if (_sharedLoading) return;
    setState(() => _sharedLoading = true);
    try {
      final result = await _api.shared(page: page);
      if (!mounted) return;
      setState(() {
        _shared = result.items;
        _sharedPage = result.page;
        _sharedTotal = result.total;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sharedLoading = false);
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
      _mirrorHost = null;
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
      unawaited(_mirrorToImageHost(url));
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

  /// 生成结果的直链会过期（base64 结果还得一直留在内存里），任务一完成就自动
  /// 转存图床，拿到长期外链后替换画布地址，后续查看/下载/复制都走稳定链接。
  /// 图床挂了不该拖垮生图流程，所以失败时静默保留原始地址。
  Future<void> _mirrorToImageHost(String source) async {
    if (_mirrored.containsKey(source)) {
      final mirrored = _mirrored[source]!;
      if (mounted && _imageUrl == source) {
        setState(() => _imageUrl = mirrored);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _mirroring = true);
    try {
      final upload = await _imageHost.upload(source);
      if (!mounted) return;
      setState(() {
        _mirrored[source] = upload.url;
        _mirrorHost = upload.host;
        if (_imageUrl == source) _imageUrl = upload.url;
      });
    } catch (_) {
      // 保留原始地址，用户仍然看得到图。
    } finally {
      if (mounted) setState(() => _mirroring = false);
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
                  child: switch (_mode) {
                    _AiDrawMode.history => _buildHistory(compact, colors),
                    _AiDrawMode.plaza => _buildPlaza(compact, colors),
                    _ => _buildWorkbench(compact, colors),
                  },
                ),
                if (!compact &&
                    _mode != _AiDrawMode.history &&
                    _mode != _AiDrawMode.plaza)
                  _buildQueue(compact, colors),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool compact, _LabColors colors) {
    if (compact) {
      const entries = <(_AiDrawMode, IconData, String)>[
        (_AiDrawMode.generate, Icons.auto_awesome_outlined, '创作'),
        (_AiDrawMode.edit, Icons.tune_rounded, '编辑'),
        (_AiDrawMode.history, Icons.photo_library_outlined, '我的'),
        (_AiDrawMode.plaza, Icons.explore_outlined, '广场'),
      ];
      return Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            for (final entry in entries) ...[
              Expanded(
                child: _MobileModeButton(
                  key: Key('ai-mode-${entry.$1.name}'),
                  icon: entry.$2,
                  label: entry.$3,
                  selected: _mode == entry.$1,
                  colors: colors,
                  onTap: _loading ? null : () => _selectMode(entry.$1),
                ),
              ),
              if (entry != entries.last) const SizedBox(width: 6),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Row(
        children: [
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
                label: Text('我的'),
              ),
              ButtonSegment(
                value: _AiDrawMode.plaza,
                icon: Icon(Icons.explore_outlined, size: 18),
                label: Text('广场'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged:
                _loading ? null : (value) => _selectMode(value.first),
          ),
        ],
      ),
    );
  }

  void _selectMode(_AiDrawMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
    });
    if (mode == _AiDrawMode.history) unawaited(_loadHistory());
    if (mode == _AiDrawMode.plaza) unawaited(_loadShared());
  }

  Widget _buildWorkbench(bool compact, _LabColors colors) {
    final canvas = _buildCanvas(colors, compact: compact);
    final controls = _buildControls(colors, compact: compact);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 4, compact ? 16 : 24, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: compact
              ? Column(
                  children: [
                    if (_tasks.isNotEmpty) ...[
                      _buildMobileTaskStrip(colors),
                      const SizedBox(height: 10),
                    ],
                    canvas,
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('ai-mobile-parameters'),
                      onPressed:
                          _loading ? null : () => _showParameters(colors),
                      icon: const Icon(Icons.tune_rounded),
                      label: Text(
                        '${_sizeLabel(_selectedSize)} · $_count 张 · ${_selectedModel ?? '默认模型'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  Future<void> _showParameters(_LabColors colors) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '生成参数',
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              _buildControls(
                colors,
                compact: true,
                sheetSetState: setSheetState,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas(_LabColors colors, {required bool compact}) {
    return _LabPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: compact ? 4 / 3 : 16 / 10,
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
                      ? GestureDetector(
                          key: const Key('ai-result-image'),
                          onTap: () => _openImage(
                            _imageUrl!,
                            prompt: _prompt.text.trim(),
                          ),
                          child: _buildImage(_imageUrl!),
                        )
                      : _buildEmptyCanvas(colors),
            ),
          ),
          if (_imageUrl != null && (_mirroring || _mirrorHost != null)) ...[
            const SizedBox(height: 10),
            _buildImageHostStrip(colors),
          ],
          if (compact && _mode == _AiDrawMode.edit) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('ai-source-picker'),
              onPressed: _loading ? null : _pickSourceImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _sourceName ?? '选择要编辑的图片',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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

  /// 结果转存图床的状态条：转存中显示进度，完成后给出直链复制入口。
  Widget _buildImageHostStrip(_LabColors colors) {
    final host = _mirrorHost;
    return Container(
      key: const Key('ai-imagehost-strip'),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.rule),
      ),
      child: Row(
        children: [
          if (_mirroring)
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.accent,
              ),
            )
          else
            Icon(Icons.cloud_done_outlined, size: 18, color: colors.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _mirroring
                  ? '正在转存图床'
                  : '已转存${host?.isNotEmpty == true ? ' · $host' : '图床'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (!_mirroring)
            TextButton.icon(
              key: const Key('ai-imagehost-copy'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _imageUrl!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('图床直链已复制')),
                );
              },
              icon: const Icon(Icons.link_rounded, size: 17),
              label: const Text('复制直链'),
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

  Widget _buildControls(
    _LabColors colors, {
    required bool compact,
    StateSetter? sheetSetState,
  }) {
    void update(VoidCallback change) {
      setState(change);
      sheetSetState?.call(() {});
    }

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
          onChanged:
              _loading ? null : (value) => update(() => _selectedModel = value),
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
          onChanged:
              _loading ? null : (value) => update(() => _selectedSize = value!),
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
              _loading ? null : (value) => update(() => _count = value.first),
        ),
        if (_mode == _AiDrawMode.edit && !compact) ...[
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

  Widget _buildMobileTaskStrip(_LabColors colors) {
    final failed = _tasks.where((task) => task.isFailed).length;
    final processing = _tasks.where((task) => task.isProcessing).length;
    return Container(
      key: const Key('ai-mobile-task-strip'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.queue,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.rule),
      ),
      child: Row(
        children: [
          Icon(
            failed > 0 ? Icons.error_outline : Icons.schedule_rounded,
            color: failed > 0 ? colors.error : colors.accent,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                if (processing > 0) '$processing 个任务处理中',
                if (failed > 0) '$failed 个任务可重试',
              ].join(' · '),
              style: TextStyle(
                color: colors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: _refreshTasks,
            child: const Text('刷新'),
          ),
        ],
      ),
    );
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
      key: const Key('ai-bottom-queue'),
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
              : constraints.maxWidth >= 360
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
                childAspectRatio: columns == 1
                    ? 1.35
                    : compact
                        ? 0.66
                        : 0.8,
              ),
              itemCount: _history.length,
              itemBuilder: (_, index) => _HistoryCard(
                item: _history[index],
                colors: colors,
                compact: compact,
                image: _buildImage(_history[index].imageUrl),
                onOpen: () => _openImage(
                  _history[index].imageUrl,
                  prompt: _history[index].prompt,
                  suggestedStem: 'duck_image_${_history[index].id}',
                ),
                onDownload: () => _downloadImage(
                  _history[index].imageUrl,
                  suggestedStem: 'duck_image_${_history[index].id}',
                ),
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

  Widget _buildPlaza(bool compact, _LabColors colors) {
    if (_shared.isEmpty && !_sharedLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.explore_outlined, size: 44, color: colors.muted),
              const SizedBox(height: 12),
              Text(
                '分享广场',
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text('还没有公开作品，去“我的”分享第一张图片',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.muted)),
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
              : constraints.maxWidth >= 360
                  ? 2
                  : 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                compact ? 16 : 24, 4, compact ? 16 : 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '分享广场',
                        style: TextStyle(
                          color: colors.ink,
                          fontSize: compact ? 20 : 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text('发现大家公开的 AI 图像作品',
                          style: TextStyle(color: colors.muted, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '刷新广场',
                  onPressed: _sharedLoading ? null : _loadShared,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: _sharedLoading && _shared.isEmpty
                ? Center(child: CircularProgressIndicator(color: colors.accent))
                : GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                        compact ? 16 : 24, 0, compact ? 16 : 24, 16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: columns == 1
                          ? 1.35
                          : compact
                              ? 0.7
                              : 0.84,
                    ),
                    itemCount: _shared.length,
                    itemBuilder: (_, index) => _SharedImageCard(
                      item: _shared[index],
                      colors: colors,
                      image: _buildImage(_shared[index].imageUrl),
                      onOpen: () => _openImage(
                        _shared[index].imageUrl,
                        prompt: _shared[index].prompt,
                        suggestedStem: 'duck_shared_${_shared[index].id}',
                      ),
                      onDownload: () => _downloadImage(
                        _shared[index].imageUrl,
                        suggestedStem: 'duck_shared_${_shared[index].id}',
                      ),
                      onCopy: () => Clipboard.setData(
                        ClipboardData(text: _shared[index].imageUrl),
                      ),
                    ),
                  ),
          ),
          if (_sharedTotal > 20)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: '上一页',
                    onPressed: _sharedPage > 0
                        ? () => _loadShared(page: _sharedPage - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('第 ${_sharedPage + 1} 页'),
                  ),
                  IconButton.filledTonal(
                    tooltip: '下一页',
                    onPressed: (_sharedPage + 1) * 20 < _sharedTotal
                        ? () => _loadShared(page: _sharedPage + 1)
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

  Future<void> _openImage(
    String source, {
    String? prompt,
    String? suggestedStem,
  }) {
    var downloading = false;
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog.fullscreen(
          key: const Key('ai-image-viewer'),
          backgroundColor: const Color(0xFF0D0E0C),
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  boundaryMargin: const EdgeInsets.all(80),
                  child:
                      Center(child: _buildImage(source, fit: BoxFit.contain)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                    color: Colors.black.withValues(alpha: 0.58),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '关闭',
                          color: Colors.white,
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            prompt?.trim().isNotEmpty == true
                                ? prompt!
                                : '查看原图',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '下载图片',
                          color: Colors.white,
                          onPressed: downloading
                              ? null
                              : () async {
                                  setDialogState(() => downloading = true);
                                  await _downloadImage(
                                    source,
                                    suggestedStem: suggestedStem,
                                  );
                                  if (dialogContext.mounted) {
                                    setDialogState(() => downloading = false);
                                  }
                                },
                          icon: downloading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.download_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (prompt?.trim().isNotEmpty == true)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 720),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          prompt!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadImage(
    String source, {
    String? suggestedStem,
  }) async {
    try {
      final data = await _readImageData(source);
      final extension = _downloadExtension(data.mimeType, source);
      final stem = _safeFileStem(suggestedStem ?? 'duck_image');
      final filename =
          '${stem}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      String targetPath;
      final desktop = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux);
      if (kIsWeb || desktop) {
        final location = await getSaveLocation(suggestedName: filename);
        if (location == null) return;
        targetPath = location.path;
      } else {
        final directory = await getApplicationDocumentsDirectory();
        targetPath = '${directory.path}/$filename';
      }
      await XFile.fromData(
        data.bytes,
        mimeType: data.mimeType,
        name: filename,
      ).saveTo(targetPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('图片已保存：$targetPath')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片下载失败，请检查网络后重试')),
      );
    }
  }

  Future<_DownloadedImageData> _readImageData(String source) async {
    if (source.startsWith('data:image/')) {
      final separator = source.indexOf(',');
      if (separator <= 0) throw const FormatException('Invalid image data URL');
      final metadata = source.substring(5, separator);
      final mimeType = metadata.split(';').first;
      return _DownloadedImageData(
        bytes: base64Decode(source.substring(separator + 1)),
        mimeType: mimeType,
      );
    }
    final response = await http.get(Uri.parse(source)).timeout(
          const Duration(seconds: 30),
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('图片下载失败（HTTP ${response.statusCode}）');
    }
    return _DownloadedImageData(
      bytes: response.bodyBytes,
      mimeType:
          response.headers['content-type']?.split(';').first ?? 'image/png',
    );
  }

  String _downloadExtension(String mimeType, String source) {
    final normalized = mimeType.toLowerCase();
    if (normalized.contains('jpeg')) return 'jpg';
    if (normalized.contains('webp')) return 'webp';
    if (normalized.contains('gif')) return 'gif';
    if (normalized.contains('png')) return 'png';
    final segments = Uri.tryParse(source)?.pathSegments ?? const <String>[];
    final filename = segments.isEmpty ? '' : segments.last;
    final extension =
        filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    return const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(extension)
        ? extension
        : 'png';
  }

  String _safeFileStem(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (normalized.isEmpty) return 'duck_image';
    return normalized.length > 36 ? normalized.substring(0, 36) : normalized;
  }

  Widget _buildImage(String source, {BoxFit fit = BoxFit.cover}) {
    if (source.startsWith('data:image/')) {
      final separator = source.indexOf(',');
      if (separator > 0) {
        try {
          return Image.memory(
            base64Decode(source.substring(separator + 1)),
            fit: fit,
            errorBuilder: (_, __, ___) => const _BrokenImage(),
          );
        } catch (_) {}
      }
    }
    return Image.network(
      source,
      fit: fit,
      errorBuilder: (_, __, ___) => const _BrokenImage(),
    );
  }
}

class _MobileModeButton extends StatelessWidget {
  const _MobileModeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final _LabColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colors.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? colors.paper : colors.muted,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    color: selected ? colors.paper : colors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
  });

  final _LabColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(18), child: child),
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
    required this.compact,
    required this.image,
    required this.onOpen,
    required this.onDownload,
    required this.onCopy,
    required this.onShare,
    required this.onDelete,
  });

  final AiDrawHistoryItem item;
  final _LabColors colors;
  final bool compact;
  final Widget image;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
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
          Expanded(
            child: GestureDetector(
              key: Key('ai-history-image-${item.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: image,
            ),
          ),
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
                if (compact)
                  PopupMenuButton<String>(
                    tooltip: '图片操作',
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    onSelected: (value) {
                      if (value == 'copy') onCopy();
                      if (value == 'download') onDownload();
                      if (value == 'share') onShare();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'download',
                        child: ListTile(
                          leading: Icon(Icons.download_rounded),
                          title: Text('下载图片'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'copy',
                        child: ListTile(
                          leading: Icon(Icons.link_rounded),
                          title: Text('复制图片地址'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: ListTile(
                          leading: Icon(item.isShared
                              ? Icons.public_off_outlined
                              : Icons.public_rounded),
                          title: Text(item.isShared ? '停止公开分享' : '公开到广场'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline_rounded),
                          title: Text('删除记录'),
                        ),
                      ),
                    ],
                  )
                else ...[
                  IconButton(
                    tooltip: '下载图片',
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_rounded, size: 19),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedImageCard extends StatelessWidget {
  const _SharedImageCard({
    required this.item,
    required this.colors,
    required this.image,
    required this.onOpen,
    required this.onDownload,
    required this.onCopy,
  });

  final AiDrawHistoryItem item;
  final _LabColors colors;
  final Widget image;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final VoidCallback onCopy;

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
          Expanded(
            child: GestureDetector(
              key: Key('ai-shared-image-${item.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: image,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 4, 7),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.prompt.isEmpty ? '公开作品' : item.prompt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.size ?? item.model ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '作品操作',
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (value) {
                    if (value == 'download') onDownload();
                    if (value == 'copy') onCopy();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'download',
                      child: ListTile(
                        leading: Icon(Icons.download_rounded),
                        title: Text('下载图片'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'copy',
                      child: ListTile(
                        leading: Icon(Icons.link_rounded),
                        title: Text('复制图片地址'),
                      ),
                    ),
                  ],
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

class _DownloadedImageData {
  const _DownloadedImageData({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}
