import 'package:flutter/material.dart';

import '../../core/api/video_parse_api.dart';
import '../../widgets/glass.dart';

/// 视频解析页（对应 macOS 版 VideoParseView）。
class VideoParseView extends StatefulWidget {
  const VideoParseView({super.key});

  @override
  State<VideoParseView> createState() => _VideoParseViewState();
}

class _VideoParseViewState extends State<VideoParseView> {
  final _url = TextEditingController();
  bool _loading = false;
  String? _result;
  String? _error;

  Future<void> _parse() async {
    final input = _url.text.trim();
    if (input.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final url = await VideoParseApi().parse(input);
      if (!mounted) return;
      if (url == null) {
        setState(() => _error = '解析失败：暂不支持该链接');
      } else {
        setState(() => _result = url);
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
        title: '视频解析',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                controller: _url,
                decoration: const InputDecoration(
                  hintText: '粘贴视频分享链接，如抖音 / 快手 / 微博等',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              GButton(
                label: _loading ? '解析中…' : '解析无水印视频',
                icon: Icons.video_library,
                expand: true,
                loading: _loading,
                onTap: _loading ? null : _parse,
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_result != null) ...[
                const Text('解析结果：',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SelectableText(_result!, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
