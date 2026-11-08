import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/player/player_controller.dart';
import 'glass.dart';

extension PlaybackModePresentation on PlaybackMode {
  String get label => switch (this) {
        PlaybackMode.listLoop => '列表循环',
        PlaybackMode.singleLoop => '单曲循环',
        PlaybackMode.shuffle => '随机播放',
      };

  IconData get icon => switch (this) {
        PlaybackMode.listLoop => Icons.repeat_rounded,
        PlaybackMode.singleLoop => Icons.repeat_one_rounded,
        PlaybackMode.shuffle => Icons.shuffle_rounded,
      };
}

class PlaybackModeButton extends StatelessWidget {
  const PlaybackModeButton({super.key, this.showLabel = false, this.size = 22});

  final bool showLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mode = context.select<PlayerController, PlaybackMode>(
        (player) => player.playbackMode);
    final player = context.read<PlayerController>();
    if (showLabel) {
      return Tooltip(
        message: mode.label,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          icon: Icon(mode.icon, size: size),
          label: Text(mode.label),
          onPressed: player.cyclePlaybackMode,
        ),
      );
    }
    return GIconButton(
      icon: mode.icon,
      tooltip: mode.label,
      size: size,
      padding: 12,
      backgroundColor: Colors.transparent,
      onTap: player.cyclePlaybackMode,
    );
  }
}
