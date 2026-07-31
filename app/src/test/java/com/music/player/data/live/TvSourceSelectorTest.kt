package com.music.player.data.live

import org.junit.Assert.assertEquals
import org.junit.Test

class TvSourceSelectorTest {

    private val sources = listOf(
        TvChannel("CCTV1", "CCTV", "https://one"),
        TvChannel("CCTV1", "CCTV", "https://two"),
        TvChannel("CCTV1", "CCTV", "https://three")
    )

    @Test
    fun preferredSourceIsAttemptedFirstWithoutDroppingFallbacks() {
        val start = TvSourceSelector.preferredIndex(sources, "https://two")

        assertEquals(1, start)
        assertEquals(listOf(1, 0, 2), TvSourceSelector.attemptOrder(sources, start))
    }

    @Test
    fun missingPreferenceFallsBackToFirstSource() {
        assertEquals(0, TvSourceSelector.preferredIndex(sources, "https://missing"))
        assertEquals(listOf(0, 1, 2), TvSourceSelector.attemptOrder(sources, 0))
    }

    @Test
    fun recentlyFailedSourcesAreTriedAfterHealthyFallbacks() {
        assertEquals(
            listOf(0, 2, 1),
            TvSourceSelector.attemptOrder(sources, 0, setOf("https://two"))
        )
    }

    @Test
    fun failedPreferredSourceDoesNotBlockHealthySource() {
        assertEquals(
            listOf(0, 2, 1),
            TvSourceSelector.attemptOrder(sources, 1, setOf("https://two"))
        )
    }
}
