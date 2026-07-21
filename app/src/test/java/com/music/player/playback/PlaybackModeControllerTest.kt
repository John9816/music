package com.music.player.playback

import androidx.media3.common.Player
import org.junit.Assert.assertEquals
import org.junit.Test

class PlaybackModeControllerTest {

    @Test
    fun shuffleTakesPriorityWhenResolvingMode() {
        assertEquals(
            PlaybackMode.SHUFFLE,
            PlaybackModeController.resolve(true, Player.REPEAT_MODE_ONE)
        )
    }

    @Test
    fun modesCycleInUiOrder() {
        assertEquals(PlaybackMode.REPEAT_ALL, PlaybackModeController.next(PlaybackMode.SHUFFLE))
        assertEquals(PlaybackMode.REPEAT_ONE, PlaybackModeController.next(PlaybackMode.REPEAT_ALL))
        assertEquals(PlaybackMode.SHUFFLE, PlaybackModeController.next(PlaybackMode.REPEAT_ONE))
    }
}
