package com.music.player.data.radio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RadioApiClientTest {

    @Test
    fun parsesRadioListEnvelope() {
        val json = """
            {
              "fetch_status": "success",
              "radio_list": [
                {"name": "河北音乐广播", "play_url": "https://example.com/a.m3u8"},
                {"name": "北京新闻广播", "play_url": "https://example.com/b.m3u8"}
              ]
            }
        """.trimIndent()
        val stations = RadioApiClient.parseStations(json)
        assertEquals(2, stations.size)
        assertEquals("河北音乐广播", stations[0].name)
        assertTrue(stations[0].playUrl.endsWith(".m3u8"))
    }
}
