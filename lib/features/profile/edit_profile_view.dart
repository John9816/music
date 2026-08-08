import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_controller.dart';
import '../../widgets/glass.dart';
import '../../widgets/user_avatar.dart';

/// 编辑登录用户的基本资料。
///
/// 资料和头像使用两个后端接口，因此保存时按顺序提交：资料成功后再上传
/// 新头像。这样资料更新失败时不会产生一个只上传头像的半成功状态。
class EditProfileView extends StatefulWidget {
  const EditProfileView({super.key});

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  static const _maxAvatarBytes = 2 * 1024 * 1024;
  static const _avatarExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

  final _username = TextEditingController();
  final _email = TextEditingController();
  Uint8List? _avatarBytes;
  String? _avatarName;
  String _initialUsername = '';
  String _initialEmail = '';
  bool _saving = false;
  String? _error;
  bool _didInitialize = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialize) return;
    _didInitialize = true;
    final auth = context.read<AuthController>();
    _username.text = auth.username ?? '';
    _email.text = auth.email ?? '';
    _initialUsername = _username.text;
    _initialEmail = _email.text;
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_saving) return;
    try {
      const typeGroup = XTypeGroup(
        label: 'images',
        extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
        mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
      );
      final file = await openFile(acceptedTypeGroups: const [typeGroup]);
      if (file == null || !mounted) return;

      final extension = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : '';
      if (!_avatarExtensions.contains(extension)) {
        setState(() => _error = '头像仅支持 JPG、PNG、WebP 或 GIF 格式');
        return;
      }
      final size = await file.length();
      if (size > _maxAvatarBytes) {
        setState(() => _error = '头像文件不能超过 2 MB');
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _avatarBytes = bytes;
        _avatarName = file.name;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '头像读取失败，请重试');
    }
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    final email = _email.text.trim();
    final profileChanged =
        username != _initialUsername || email != _initialEmail;
    final avatarSelected = _avatarBytes != null && _avatarName != null;
    if (!profileChanged && !avatarSelected) {
      setState(() => _error = '请选择头像或修改资料后再保存');
      return;
    }
    if (profileChanged) {
      final error = _validate(username, email);
      if (error != null) {
        setState(() => _error = error);
        return;
      }
    }

    final auth = context.read<AuthController>();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (profileChanged) {
        final profileSaved = await auth.updateProfile(
          username: username,
          email: email,
        );
        if (!profileSaved) {
          if (mounted) setState(() => _error = auth.error ?? '资料保存失败');
          return;
        }
      }
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
        const SnackBar(content: Text('个人资料已更新')),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validate(String username, String email) {
    if (username.length < 3 || username.length > 50) {
      return '用户名需要 3-50 个字符';
    }
    final validEmail = RegExp(r'^[1-9]\d{4,10}@qq\.com$', caseSensitive: false)
            .hasMatch(email) ||
        RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}@751152\.xyz$', caseSensitive: false)
            .hasMatch(email);
    if (!validEmail) return '请输入 QQ 邮箱或 751152.xyz 邮箱';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: GAppBar(
          title: '编辑个人资料',
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
        title: '编辑个人资料',
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
          ],
          const SizedBox(height: 28),
          _field(
            controller: _username,
            label: '用户名',
            hint: '3-50 个字符',
            icon: Icons.person_outline_rounded,
            enabled: !_saving,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          _field(
            controller: _email,
            label: '邮箱',
            hint: 'QQ 邮箱或 751152.xyz 邮箱',
            icon: Icons.mail_outline_rounded,
            enabled: !_saving,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saving ? null : _save(),
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
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? '正在保存' : '保存资料'),
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

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool enabled,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      maxLines: 1,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }
}
