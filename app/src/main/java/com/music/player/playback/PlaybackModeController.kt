package com.music.player.playback

import androidx.media3.common.Player

enum class PlaybackMode {
    SHUFFLE,
    REPEAT_ALL,
    REPEAT_ONE
}

/**
 * Multi-track advance is owned by [PlaybackCoordinator] (single MediaItem pipeline).
 * ExoPlayer always stays REPEAT_OFF / shuffle off so STATE_ENDED is reliable.
 */
object PlaybackModeController {
    fun next(mode: PlaybackMode): PlaybackMode = when (mode) {
        PlaybackMode.SHUFFLE -> PlaybackMode.REPEAT_ALL
        PlaybackMode.REPEAT_ALL -> PlaybackMode.REPEAT_ONE
        PlaybackMode.REPEAT_ONE -> PlaybackMode.SHUFFLE
    }

    /** Keep the engine free of multi-item semantics; app layer decides what plays next. */
    fun applyEngineDefaults(player: Player) {
        player.shuffleModeEnabled = false
        player.repeatMode = Player.REPEAT_MODE_OFF
    }
}
