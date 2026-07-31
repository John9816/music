package com.music.player.data.live

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TvLiveApiClientTest {

    @Test
    fun parsesM3uChannelsWithGroupAndLogo() {
        val m3u = """
            #EXTM3U x-tvg-url="https://live.fanmingming.cn/e.xml"
            #EXTINF:-1 tvg-name="CCTV1" tvg-logo="https://live.fanmingming.cn/tv/CCTV1.png" group-title="专享央视",CCTV1
            http://example.com/cctv1.m3u8
            #EXTINF:-1 tvg-name="湖南卫视" group-title="卫视频道",湖南卫视
            https://example.com/hunan.m3u8
        """.trimIndent()

        val channels = TvLiveApiClient.parseM3u(m3u)

        assertEquals(2, channels.size)
        assertEquals("CCTV1", channels[0].name)
        assertEquals("专享央视", channels[0].group)
        assertEquals("https://live.fanmingming.cn/tv/CCTV1.png", channels[0].logoUrl)
        assertTrue(channels[0].playUrl.endsWith("cctv1.m3u8"))
        assertEquals("湖南卫视", channels[1].name)
    }

    @Test
    fun ignoresCommentsAndMalformedEntries() {
        val m3u = """
            #EXTM3U
            #EXTINF:-1 group-title="电影点播",电影频道
            #EXTVLCOPT:http-user-agent=test
            #EXTINF:-1 group-title="体育频道",体育频道
            https://example.com/live/sports.m3u8
            #EXTINF:-1 group-title="P2P",P2P频道
            p3p://example.com/live/channel
        """.trimIndent()

        val channels = TvLiveApiClient.parseM3u(m3u)

        assertEquals(1, channels.size)
        assertEquals("体育频道", channels[0].name)
        assertEquals("https://example.com/live/sports.m3u8", channels[0].playUrl)
    }

    @Test
    fun acceptsRtmpStreamsForMpvPlayback() {
        val m3u = """
            #EXTM3U
            #EXTINF:-1 group-title="RTMP",RTMP Channel
            rtmp://example.com/live/channel
            #EXTINF:-1 group-title="P2P",P2P Channel
            p3p://example.com/live/channel
        """.trimIndent()

        val channels = TvLiveApiClient.parseM3u(m3u)

        assertEquals(1, channels.size)
        assertEquals("RTMP Channel", channels[0].name)
        assertEquals("rtmp://example.com/live/channel", channels[0].playUrl)
    }

    @Test
    fun parsesBomAndQuotedAttributesContainingSpaces() {
        val m3u = """
            \uFEFF#EXTM3U
            #EXTINF:-1 tvg-name="News Channel HD" group-title="International News",News Channel HD
            https://example.com/news.m3u8
        """.trimIndent()

        val channels = TvLiveApiClient.parseM3u(m3u)

        assertEquals(1, channels.size)
        assertEquals("News Channel HD", channels.single().name)
        assertEquals("International News", channels.single().group)
    }
}
