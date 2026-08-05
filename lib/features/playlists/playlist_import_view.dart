import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../widgets/glass.dart';
import '../profile/login_view.dart';

/// 从网易云、QQ 音乐等平台的歌单链接导入用户歌单。
class PlaylistImportView extends StatefulWidget {
  const PlaylistImportView({super.key, this.onImported});

  final VoidCallback? onImported;

  @override
  State<PlaylistImportView> createState() => _PlaylistImportViewState();
}

class _PlaylistImportViewState extends State<PlaylistImportView> {
  final TextEditingController _urlController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final url = _urlController.text.trim();
    final auth = context.read<AuthController>();
    if (_loading) return;
    if (!auth.isLoggedIn || auth.token == null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginView()),
      );
      return;
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      setState(() {
        _error = '请输入有效的歌单链接';
        _success = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      final result = await UserApi().importPlaylist(url, auth.token!);
      if (!mounted) return;
      final name = result['name'] as String?;
      final count = (result['trackCount'] as num?)?.toInt();
      final suffix = count == null ? '' : '，共 $count 首歌曲';
      widget.onImported?.call();
      setState(() {
        _success = '导入成功${name == null || name.isEmpty ? '' : '：$name'}$suffix';
        _urlController.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: GAppBar(
        title: '导入歌单',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            children: [
              GSurface(
                padding: const EdgeInsets.all(20),
                alpha: 0.06,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.playlist_add_rounded,
                            color: scheme.primary, size: 24),
                        const SizedBox(width: 10),
                        const Text(
                          '导入外部歌单',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '粘贴网易云音乐、QQ 音乐或其他支持平台的歌单分享链接。',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _import(),
                      enabled: !_loading,
                      decoration: const InputDecoration(
                        labelText: '歌单链接',
                        hintText: 'https://music.163.com/playlist?id=...',
                        prefixIcon: Icon(Icons.link_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GButton(
                      label: _loading ? '导入中…' : '开始导入',
                      icon: Icons.file_download_outlined,
                      expand: true,
                      loading: _loading,
                      onTap: _loading ? null : _import,
                    ),
                    if (!auth.isLoggedIn) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const LoginView()),
                          ),
                          icon: const Icon(Icons.login, size: 16),
                          label: const Text('登录后导入到你的歌单'),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!,
                          style: TextStyle(color: scheme.error, fontSize: 13)),
                    ],
                    if (_success != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle,
                              color: scheme.primary, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_success!,
                                style: TextStyle(
                                    color: scheme.primary, fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '导入后的歌单会同步到“我的歌单”，歌曲列表由服务端从原平台重新获取。',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
