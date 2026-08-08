import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_controller.dart';
import '../../widgets/glass.dart';
import '../../widgets/user_avatar.dart';

/// 编辑登录用户头像。用户名和邮箱是账号身份字段，只读展示。
class EditProfileView extends StatefulWidget {
  const EditProfileView({super.key});

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  static const _maxAvatarBytes = 2 * 1024 * 1024;
  static const _avatarExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

  Uint8List? _avatarBytes;
  String? _avatarName;
  bool _saving = false;
  String? _error;

  bool get _hasSelectedAvatar => _avatarBytes != null && _avatarName != null;

  Future<void> _pickAvatar() async {
    if (_saving) return;
    try {
      final file = await _pickAvatarFile();
      if (file == null || !mounted) return;

      // Content URIs from Android/iOS may not support XFile.length(). Reading
      // once also avoids a second provider permission check.
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) setState(() => _error = '所选图片为空，请重新选择');
        return;
      }
      if (bytes.length > _maxAvatarBytes) {
        setState(() => _error = '头像文件不能超过 2 MB');
        return;
      }
      final extension = _avatarExtension(file, bytes);
      if (extension == null) {
        setState(() => _error = '头像仅支持 JPG、PNG、WebP 或 GIF 格式');
        return;
      }
      if (!mounted) return;
      setState(() {
        _avatarBytes = bytes;
        _avatarName = _avatarFilename(file.name, extension);
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取所选图片，请重新选择');
    }
  }

  Future<XFile?> _pickAvatarFile() {
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (isMobile) {
      return ImagePicker().pickImage(source: ImageSource.gallery);
    }
    return openFile(acceptedTypeGroups: <XTypeGroup>[_avatarTypeGroup()]);
  }

  XTypeGroup _avatarTypeGroup() {
    if (kIsWeb) {
      return const XTypeGroup(
        label: 'images',
        webWildCards: ['image/*'],
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return const XTypeGroup(
          label: 'images',
          uniformTypeIdentifiers: ['public.image'],
        );
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return const XTypeGroup(
          label: 'images',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
        );
      case TargetPlatform.android:
      case TargetPlatform.linux:
        return const XTypeGroup(
          label: 'images',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
          mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
        );
    }
  }

  String? _avatarExtension(XFile file, Uint8List bytes) {
    final name = file.name.trim();
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      final extension = name.substring(dot + 1).toLowerCase();
      if (_avatarExtensions.contains(extension)) return extension;
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

    if (_isPng(bytes)) return 'png';
    if (_isGif(bytes)) return 'gif';
    if (_isJpeg(bytes)) return 'jpg';
    if (_isWebp(bytes)) return 'webp';
    return null;
  }

  String _avatarFilename(String name, String extension) {
    final trimmed = name.trim();
    final dot = trimmed.lastIndexOf('.');
    if (dot > 0 &&
        _avatarExtensions.contains(trimmed.substring(dot + 1).toLowerCase())) {
      return trimmed;
    }
    return 'avatar.$extension';
  }

  bool _isPng(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a;

  bool _isGif(Uint8List bytes) =>
      bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) &&
      bytes[5] == 0x61;

  bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;

  bool _isWebp(Uint8List bytes) =>
      bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50;

  Future<void> _save() async {
    if (!_hasSelectedAvatar) {
      setState(() => _error = '请先选择新的头像');
      return;
    }

    final auth = context.read<AuthController>();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final avatar = _avatarBytes;
      final filename = _avatarName;
      if (avatar != null && filename != null) {
        final avatarSaved = await auth.uploadAvatar(
          bytes: avatar,
          filename: filename,
        );
        if (!avatarSaved) {
          if (mounted) setState(() => _error = auth.error ?? '头像上传失败');
          return;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像已更新')),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: GAppBar(
          title: '编辑头像',
          onBack: () => Navigator.of(context).maybePop(),
        ),
        body: const GEmptyState(
          icon: Icons.person_outline_rounded,
          title: '尚未登录',
          text: '登录后才能编辑个人资料',
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: GAppBar(
        title: '编辑头像',
        onBack: _saving ? null : () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Center(
            child: Semantics(
              button: true,
              label: '更换头像',
              child: GestureDetector(
                onTap: _saving ? null : _pickAvatar,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _avatarPreview(auth),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scheme.surface,
                            width: 3,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: Icon(
                            Icons.edit_rounded,
                            size: 17,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_avatarName != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                _avatarName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                '点击头像选择图片',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          const SizedBox(height: 28),
          _readOnlyInfo(
            label: '用户名',
            value: auth.username,
            icon: Icons.person_outline_rounded,
            scheme: scheme,
          ),
          const SizedBox(height: 14),
          _readOnlyInfo(
            label: '邮箱',
            value: auth.email,
            icon: Icons.mail_outline_rounded,
            scheme: scheme,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: _saving || !_hasSelectedAvatar ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? '正在上传' : '保存头像'),
          ),
        ],
      ),
    );
  }

  Widget _avatarPreview(AuthController auth) {
    final bytes = _avatarBytes;
    if (bytes != null) {
      return ClipOval(
        child: SizedBox.square(
          dimension: 112,
          child: Image.memory(bytes, fit: BoxFit.cover),
        ),
      );
    }
    return UserAvatar(
      radius: 56,
      name: auth.username ?? '',
      showInitial: true,
      imageUrl: auth.avatarUrl,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    );
  }

  Widget _readOnlyInfo({
    required String label,
    required String? value,
    required IconData icon,
    required ColorScheme scheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: glassHairline(context)),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value?.isNotEmpty == true ? value! : '未设置',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: scheme.outline,
          ),
        ],
      ),
    );
  }
}
