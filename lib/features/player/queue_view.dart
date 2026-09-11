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
    enableDrag: false,
    sheetAnimationStyle: AnimationStyle(
      duration: PlatformMotion.duration(context, Motion.slow),
      reverseDuration: PlatformMotion.duration(context, Motion.normal),
    ),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.42,
      maxChildSize: 0.94,
      expand: false,
      snap: !MediaQuery.disableAnimationsOf(context),
      snapSizes: const [0.72],
      snapAnimationDuration: Motion.normal,
      builder: (context, scrollController) =>
          _QueueSheet(scrollController: scrollController),
    ),
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final queue = context.select<PlayerController, List<Song>>((p) => p.queue);
    final queueIndex =
        context.select<PlayerController, int>((p) => p.queueIndex);
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: ColoredBox(
        color: scheme.surfaceContainerLow,
        child: SafeArea(
          top: false,
          child: CustomScrollView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _QueueHeader(count: queue.length),
              ),
              if (queue.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('播放队列为空')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  sliver: SliverList.builder(
                    itemCount: queue.length,
                    itemBuilder: (context, i) {
                      final song = queue[i];
                      final isCurrent = i == queueIndex;
                      return GListTile(
                        key: ValueKey((song.source, song.id, i)),
                        selected: isCurrent,
                        leading: SizedBox.square(
                          dimension: 24,
                          child: isCurrent
                              ? const _NowPlayingEQ()
                              : Center(
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: scheme.outline,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
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
        ),
      ),
    );
  }
}

class _QueueHeader extends SliverPersistentHeaderDelegate {
  const _QueueHeader({required this.count});

  final int count;

  @override
  double get minExtent => 72;

  @override
  double get maxExtent => 72;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 20, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '播放队列 ($count)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  GIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '关闭播放队列',
                    size: 18,
                    padding: 2,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _QueueHeader oldDelegate) =>
      count != oldDelegate.count;
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
  bool? _lastAnimating;
  static const _barCount = 4;
  static const _heights = [14, 22, 18, 10];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final animate = playing &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_lastAnimating != animate) {
      _lastAnimating = animate;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (animate) {
          _ctrl.repeat(reverse: true);
        } else {
          _ctrl.stop();
        }
      });
    }
    return SizedBox(
      key: const ValueKey('queue-now-playing-eq'),
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
