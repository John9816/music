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

enum _AiDrawMode { generate, edit }

/// AI 绘画页（对应 macOS 版 AiDrawView）。
class AiDrawView extends StatefulWidget {
  const AiDrawView({super.key});

  @override
  State<AiDrawView> createState() => _AiDrawViewState();
}

class _AiDrawViewState extends State<AiDrawView> {
  final _prompt = TextEditingController();
  _AiDrawMode _mode = _AiDrawMode.generate;
  List<AiDrawModel> _models = const [];
  String? _selectedModel;
  Uint8List? _sourceBytes;
  String? _sourceName;
  bool _loading = false;
  bool _modelsLoading = false;
  String? _imageUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<AuthController>().isLoggedIn) {
        unawaited(_loadModels());
      }
    });
  }

  Future<void> _loadModels() async {
    if (_modelsLoading) return;
    setState(() => _modelsLoading = true);
    try {
      final models = await AiDrawApi().models();
      if (!mounted) return;
      setState(() => _models = models);
    } catch (_) {
      // The backend can still use its configured default model.
    } finally {
      if (mounted) setState(() => _modelsLoading = false);
    }
  }

  Future<void> _submit() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty || _loading) return;
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
      final api = AiDrawApi();
      final url = _mode == _AiDrawMode.generate
          ? await api.generate(prompt, model: _selectedModel)
          : await api.edit(
              bytes: _sourceBytes!,
              filename: _sourceName ?? 'source.png',
              prompt: prompt,
              model: _selectedModel,
            );
      if (!mounted) return;
      setState(() => _imageUrl = url);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickSourceImage() async {
    if (_loading) return;
    try {
      final file = await _pickImageFile();
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        setState(() => _error = '所选图片为空，请重新选择');
        return;
      }
      final extension = _imageExtension(file);
      if (extension == null) {
        setState(() => _error = '仅支持 JPG、PNG、WebP 或 GIF 图片');
        return;
      }
      setState(() {
        _sourceBytes = bytes;
        _sourceName = _normalizedFilename(file.name, extension);
        _error = null;
        _imageUrl = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取所选图片，请重新选择');
    }
  }

  Future<XFile?> _pickImageFile() {
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (isMobile) return ImagePicker().pickImage(source: ImageSource.gallery);
    return openFile(acceptedTypeGroups: <XTypeGroup>[_imageTypeGroup()]);
  }

  XTypeGroup _imageTypeGroup() {
    if (kIsWeb) {
      return const XTypeGroup(label: 'images', webWildCards: ['image/*']);
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return const XTypeGroup(
          label: 'images',
          uniformTypeIdentifiers: ['public.image'],
        );
      case TargetPlatform.android:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return const XTypeGroup(
          label: 'images',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
          mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
        );
    }
  }

  String? _imageExtension(XFile file) {
    final name = file.name.trim();
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      final extension = name.substring(dot + 1).toLowerCase();
      if (const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(extension)) {
        return extension;
      }
    }
    switch (file.mimeType?.toLowerCase()) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
    }
    return null;
  }

  String _normalizedFilename(String name, String extension) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'source.$extension' : trimmed;
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GAppBar(
        title: 'AI 绘画',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                controller: _prompt,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '描述你想要的画面，例如：夕阳下的湖面，水彩风格',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<_AiDrawMode>(
                segments: const [
                  ButtonSegment(
                    value: _AiDrawMode.generate,
                    label: Text('生成图片'),
                    icon: Icon(Icons.auto_awesome),
                  ),
                  ButtonSegment(
                    value: _AiDrawMode.edit,
                    label: Text('编辑图片'),
                    icon: Icon(Icons.edit_outlined),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: _loading
                    ? null
                    : (selection) {
                        setState(() {
                          _mode = selection.first;
                          _error = null;
                          _imageUrl = null;
                        });
                      },
              ),
              const SizedBox(height: 12),
              if (_modelsLoading)
                const LinearProgressIndicator(minHeight: 2)
              else
                DropdownButtonFormField<String>(
                  key: ValueKey(_selectedModel),
                  initialValue: _selectedModel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '模型',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('使用系统默认模型'),
                  items: [
                    for (final model in _models)
                      DropdownMenuItem(
                        value: model.id,
                        child: Text(model.id, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _models.isEmpty || _loading
                      ? null
                      : (value) => setState(() => _selectedModel = value),
                ),
              if (_mode == _AiDrawMode.edit) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickSourceImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_sourceName ?? '选择要编辑的图片'),
                ),
                if (_sourceBytes != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _sourceBytes!,
                      height: 180,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              GButton(
                label: _loading
                    ? (_mode == _AiDrawMode.edit ? '编辑中…' : '生成中…')
                    : (_mode == _AiDrawMode.edit ? '编辑图片' : '生成图片'),
                icon: _mode == _AiDrawMode.edit
                    ? Icons.edit_outlined
                    : Icons.auto_awesome,
                expand: true,
                loading: _loading,
                onTap: _loading ? null : _submit,
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildImage(_imageUrl!),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () =>
                      Clipboard.setData(ClipboardData(text: _imageUrl!)),
                  child: Text(
                    _imageUrl!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(String source) {
    if (source.startsWith('data:image/')) {
      final separator = source.indexOf(',');
      if (separator > 0) {
        try {
          return Image.memory(
            base64Decode(source.substring(separator + 1)),
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
        } catch (_) {}
      }
    }
    return Image.network(
      source,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
