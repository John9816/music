package com.music.player.playback

import org.junit.Assert.assertEquals
import org.junit.Test

class PlaybackModeControllerTest {

    @Test
    fun modesCycleInUiOrder() {
        assertEquals(PlaybackMode.REPEAT_ALL, PlaybackModeController.next(PlaybackMode.SHUFFLE))
        assertEquals(PlaybackMode.REPEAT_ONE, PlaybackModeController.next(PlaybackMode.REPEAT_ALL))
        assertEquals(PlaybackMode.SHUFFLE, PlaybackModeController.next(PlaybackMode.REPEAT_ONE))
    }
}
