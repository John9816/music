package com.music.player.data.radio

import com.music.player.data.model.RadioStation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RadioStationCacheTest {

    @Test
    fun encodeDecode_roundTrip() {
        val list = listOf(
            RadioStation("河北音乐", "https://a.m3u8"),
            RadioStation("北京新闻", "https://b.m3u8")
        )
        val raw = RadioStationCache.encode(list)
        val back = RadioStationCache.decode(raw)
        assertEquals(list, back)
    }

    @Test
    fun snapshot_isFreshWithinTtl() {
        val now = 1_000_000L
        val snap = RadioStationCache.Snapshot(
            stations = listOf(RadioStation("A", "https://a")),
            savedAtMs = now - 1_000L
        )
        assertTrue(snap.isFresh(now, ttlMs = 10_000L))
        assertFalse(snap.isFresh(now, ttlMs = 500L))
    }

    @Test
    fun snapshot_emptyNeverFresh() {
        val snap = RadioStationCache.Snapshot(emptyList(), savedAtMs = 1L)
        assertFalse(snap.isFresh(ttlMs = RadioStationCache.DEFAULT_TTL_MS))
    }
}
