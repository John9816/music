package com.music.player.data.settings

import org.junit.Assert.assertEquals
import org.junit.Test

class MusicSourcePreferencesTest {

    @Test
    fun mapsSupportedBackendSources() {
        assertEquals(
            listOf("netease", "qq", "kuwo"),
            MusicSourcePreferences.Source.entries.map { it.storageValue }
        )
        assertEquals(
            MusicSourcePreferences.Source.QQ,
            MusicSourcePreferences.Source.fromStorage("qq")
        )
    }

    @Test
    fun unknownSourceFallsBackToNetease() {
        assertEquals(
            MusicSourcePreferences.Source.NETEASE,
            MusicSourcePreferences.Source.fromStorage("unsupported")
        )
    }
}
