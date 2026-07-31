package com.music.player.data.live

import org.junit.Assert.assertEquals
import org.junit.Test

class TvLogoUrlTest {

    @Test
    fun replacesUnavailableFanmingmingHostWithCdnMirror() {
        assertEquals(
            "https://cdn.jsdelivr.net/gh/fanmingming/live@main/tv/CCTV1.png",
            TvLogoUrl.resolve("https://live.fanmingming.cn/tv/CCTV1.png")
        )
    }

    @Test
    fun keepsOtherLogoHostsUnchanged() {
        assertEquals(
            "https://example.com/channel.png",
            TvLogoUrl.resolve("https://example.com/channel.png")
        )
    }
}
