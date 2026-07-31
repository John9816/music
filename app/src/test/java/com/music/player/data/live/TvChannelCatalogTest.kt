package com.music.player.data.live

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TvChannelCatalogTest {

    @Test
    fun build_mergesSourcesAndExcludesNonLiveGroups() {
        val sources = listOf(
            channel("CCTV1", "专享央视", "https://1"),
            channel("CCTV1", "专享央视", "https://2"),
            channel("CCTV1", "专享央视", "https://3"),
            channel("电影A", "电影点播", "https://4"),
            channel("定制A", "定制P3P", "https://5")
        )

        val result = TvChannelCatalog.build(sources)

        assertEquals(1, result.size)
        assertEquals("央视频道", result.single().group)
        assertEquals(3, result.single().sources.size)
    }

    @Test
    fun build_keepsSingleSourceChildrenButDropsUnstableRegularChannel() {
        val result = TvChannelCatalog.build(
            listOf(
                channel("少儿台", "儿童专享", "https://1"),
                channel("地方台", "浙江频道", "https://2")
            )
        )

        assertEquals(listOf("少儿台"), result.map { it.name })
        assertTrue(result.single().sources.size == 1)
    }

    @Test
    fun build_prefersSpecificRegionOverGenericSatelliteGroup() {
        val result = TvChannelCatalog.build(
            listOf(
                channel("广东卫视", "广东卫视", "https://1"),
                channel("广东卫视", "广东卫视", "https://2"),
                channel("广东卫视", "广东卫视", "https://3")
            )
        )

        assertEquals("广东地区", result.single().group)
    }

    private fun channel(name: String, group: String, url: String) =
        TvChannel(name = name, group = group, playUrl = url)
}
