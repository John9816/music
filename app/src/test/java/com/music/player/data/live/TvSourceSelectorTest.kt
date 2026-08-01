package com.music.player.data.live

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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
    fun missingPreferenceFallsBackToBestRankedSource() {
        val mixed = listOf(
            TvChannel("CCTV1", "CCTV", "http://plain/live"),
            TvChannel("CCTV1", "CCTV", "https://cdn/live.m3u8"),
            TvChannel("CCTV1", "CCTV", "https://cdn/live.flv")
        )
        assertEquals(1, TvSourceSelector.preferredIndex(mixed, "https://missing"))
        assertEquals(listOf(1, 2, 0), TvSourceSelector.attemptOrder(mixed, 1))
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

    @Test
    fun hlsRanksAboveProgressiveAndRtmp() {
        assertTrue(TvSourceSelector.protocolRank("https://a/live.m3u8") <
            TvSourceSelector.protocolRank("https://a/live.flv"))
        assertTrue(TvSourceSelector.protocolRank("https://a/live.flv") <
            TvSourceSelector.protocolRank("http://a/live"))
        assertTrue(TvSourceSelector.protocolRank("http://a/live") <
            TvSourceSelector.protocolRank("rtmp://a/live"))
    }

    @Test
    fun sortSourcesForExoPutsHlsFirst() {
        val sorted = TvSourceSelector.sortSourcesForExo(
            listOf(
                TvChannel("A", "G", "rtmp://x/live"),
                TvChannel("A", "G", "http://x/live.ts"),
                TvChannel("A", "G", "https://x/live.m3u8")
            )
        )
        assertEquals("https://x/live.m3u8", sorted.first().playUrl)
        assertEquals("rtmp://x/live", sorted.last().playUrl)
    }

    @Test
    fun exoPlayableAcceptsHttpOnly() {
        assertTrue(TvSourceSelector.isExoPlayable("https://x/a.m3u8"))
        assertTrue(TvSourceSelector.isExoPlayable("http://x/a.m3u8"))
        assertFalse(TvSourceSelector.isExoPlayable("rtmp://x/live"))
        assertFalse(TvSourceSelector.isExoPlayable("p3p://x/live"))
    }
}
