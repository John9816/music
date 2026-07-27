package com.music.player.data.radio

import com.music.player.data.model.RadioStation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RadioRegionHelperTest {

    @Test
    fun regionOf_prefersLongerPrefix() {
        assertEquals("黑龙江", RadioRegionHelper.regionOf("黑龙江交通广播"))
        assertEquals("内蒙古", RadioRegionHelper.regionOf("内蒙古音乐之声"))
        assertEquals("北京", RadioRegionHelper.regionOf("北京新闻广播"))
    }

    @Test
    fun buildChipLabels_includesAllAndRecent() {
        val stations = listOf(
            RadioStation("河北音乐", "https://a"),
            RadioStation("河北新闻", "https://b"),
            RadioStation("上海动感", "https://c")
        )
        val labels = RadioRegionHelper.buildChipLabels(stations, hasRecent = true)
        assertEquals(RadioRegionHelper.ALL, labels.first())
        assertTrue(labels.contains(RadioRegionHelper.RECENT))
        assertTrue(labels.contains("河北"))
        assertTrue(labels.contains("上海"))
    }

    @Test
    fun avatarLetter_usesRegionOrFirstChar() {
        assertEquals("河", RadioRegionHelper.avatarLetter("河北音乐广播"))
        assertEquals("X", RadioRegionHelper.avatarLetter("XFM 88.7"))
    }
}
