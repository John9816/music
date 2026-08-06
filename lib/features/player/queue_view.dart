import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../widgets/glass.dart';
import '../../widgets/song_action_menu.dart';
import '../search/artist_names_link.dart';

/// 弹出播放队列面板（底部弹层，不再整窗跳转）
Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _QueueSheet(),
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final queue = context.select<PlayerController, List<Song>>((p) => p.queue);
    final queueIndex =
        context.select<PlayerController, int>((p) => p.queueIndex);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.72,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: glassHairline(context))),
      ),
      child: Column(
        children: [
          // 拖拽把手
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题栏：标题 + 关闭按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '播放队列 (${queue.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                GIconButton(
                  icon: Icons.close,
                  tooltip: '关闭播放队列',
                  size: 18,
                  padding: 2,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: queue.length,
              itemBuilder: (context, i) {
                final song = queue[i];
                final isCurrent = i == queueIndex;
                return GListTile(
                  selected: isCurrent,
                  leading: isCurrent
                      ? const _NowPlayingEQ()
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: scheme.outline,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                  title: Text(song.name),
                  subtitle: ArtistNamesLink(
                    artists: song.artists,
                    source: song.source,
                  ),
                  trailing: SongActionButton(
                    song: song,
                    queueIndex: i,
                    onPlay: () => player.playAt(i),
                  ),
                  onTap: () => player.playAt(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 当前播放动效均衡器（网易云风格：4 根红色音柱跳动）
class _NowPlayingEQ extends StatefulWidget {
  const _NowPlayingEQ();

  @override
  State<_NowPlayingEQ> createState() => _NowPlayingEQState();
}

class _NowPlayingEQState extends State<_NowPlayingEQ>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  static const _barCount = 4;
  static const _heights = [14, 22, 18, 10];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 24,
      height: 24,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(_barCount, (i) {
              // 每根音柱相位偏移，做出逐条弹跳效果
              final phase = (i / _barCount + _ctrl.value * 0.5) % 1.0;
              final barH = _heights[i] * (0.4 + 0.6 * phase);
              return Container(
                width: 3,
                height: barH.clamp(4.0, 24.0),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
