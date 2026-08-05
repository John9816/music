import 'package:flutter/material.dart';

import '../../widgets/glass.dart';
import '../playlists/playlist_import_view.dart';
import 'ai_draw_view.dart';
import 'video_parse_view.dart';

/// 工具页
class ToolsView extends StatelessWidget {
  const ToolsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const GPageHeader(
            title: '工具箱',
            subtitle: '创作、解析与歌单管理',
          ),
          const SectionHeader('常用工具'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _buildCards(context, const [
              _ToolSpec(
                  icon: Icons.auto_awesome,
                  label: 'AI 绘画',
                  desc: '一句话生成图片',
                  page: AiDrawView()),
              _ToolSpec(
                  icon: Icons.video_library,
                  label: '视频解析',
                  desc: '无水印下载地址',
                  page: VideoParseView()),
              _ToolSpec(
                  icon: Icons.playlist_add_rounded,
                  label: '导入歌单',
                  desc: '从分享链接导入',
                  page: PlaylistImportView()),
            ]),
          ),
          const SectionHeader('即将上线'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _buildCards(context, const [
              _ToolSpec(
                  icon: Icons.radio, label: '电台', desc: '全国电台直播', coming: true),
              _ToolSpec(
                  icon: Icons.live_tv,
                  label: '电视直播',
                  desc: 'IPTV 频道',
                  coming: true),
              _ToolSpec(
                  icon: Icons.videocam,
                  label: '电视点播',
                  desc: '视频点播',
                  coming: true),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildCards(BuildContext context, List<_ToolSpec> specs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 560 ? 3 : 2;
        const gap = 14.0;
        final cardWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final spec in specs)
              SizedBox(
                width: cardWidth,
                child: _ToolCard(
                  icon: spec.icon,
                  label: spec.label,
                  desc: spec.desc,
                  coming: spec.coming,
                  onTap: spec.coming
                      ? null
                      : spec.page == null
                          ? null
                          : () => _push(context, spec.page!),
                ),
              ),
          ],
        );
      },
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _ToolSpec {
  const _ToolSpec({
    required this.icon,
    required this.label,
    required this.desc,
    this.coming = false,
    this.page,
  });

  final IconData icon;
  final String label;
  final String desc;
  final bool coming;
  final Widget? page;
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.label,
    required this.desc,
    this.coming = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String desc;
  final bool coming;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = coming || onTap == null;
    final semanticLabel = '$label，$desc${coming ? '，即将上线' : ''}';
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: GPressScale(
          onTap: onTap,
          disabled: onTap == null,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: glassFill(context, alpha: 0.06),
              border: Border.all(color: glassHairline(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kRadiusMd),
                    color: muted
                        ? glassFill(context, alpha: 0.04)
                        : scheme.primary.withValues(alpha: 0.14),
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: muted ? scheme.outline : scheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: muted ? scheme.outline : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
                if (coming) ...[
                  const SizedBox(height: 8),
                  Text(
                    '即将上线',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: scheme.tertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
