package com.music.player.playback

import androidx.media3.common.Player

enum class PlaybackMode {
    SHUFFLE,
    REPEAT_ALL,
    REPEAT_ONE
}

object PlaybackModeController {
    fun resolve(shuffleEnabled: Boolean, repeatMode: Int): PlaybackMode = when {
        shuffleEnabled -> PlaybackMode.SHUFFLE
        repeatMode == Player.REPEAT_MODE_ONE -> PlaybackMode.REPEAT_ONE
        else -> PlaybackMode.REPEAT_ALL
    }

    fun resolve(player: Player): PlaybackMode =
        resolve(player.shuffleModeEnabled, player.repeatMode)

    fun next(mode: PlaybackMode): PlaybackMode = when (mode) {
        PlaybackMode.SHUFFLE -> PlaybackMode.REPEAT_ALL
        PlaybackMode.REPEAT_ALL -> PlaybackMode.REPEAT_ONE
        PlaybackMode.REPEAT_ONE -> PlaybackMode.SHUFFLE
    }

    fun apply(player: Player, mode: PlaybackMode) {
        player.shuffleModeEnabled = mode == PlaybackMode.SHUFFLE
        player.repeatMode = when (mode) {
            PlaybackMode.SHUFFLE -> Player.REPEAT_MODE_OFF
            PlaybackMode.REPEAT_ALL -> Player.REPEAT_MODE_ALL
            PlaybackMode.REPEAT_ONE -> Player.REPEAT_MODE_ONE
        }
    }
}
