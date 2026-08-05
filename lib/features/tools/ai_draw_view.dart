import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/ai_draw_api.dart';
import '../../widgets/glass.dart';

/// AI 绘画页（对应 macOS 版 AiDrawView）。
class AiDrawView extends StatefulWidget {
  const AiDrawView({super.key});

  @override
  State<AiDrawView> createState() => _AiDrawViewState();
}

class _AiDrawViewState extends State<AiDrawView> {
  final _prompt = TextEditingController();
  bool _loading = false;
  String? _imageUrl;
  String? _error;

  Future<void> _generate() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _imageUrl = null;
    });
    try {
      final url = await AiDrawApi().generate(prompt);
      if (!mounted) return;
      if (url == null) {
        setState(() => _error = '生成失败，请稍后重试');
      } else {
        setState(() => _imageUrl = url);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
              GButton(
                label: _loading ? '生成中…' : '生成图片',
                icon: Icons.auto_awesome,
                expand: true,
                loading: _loading,
                onTap: _loading ? null : _generate,
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(_imageUrl!,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
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
}
