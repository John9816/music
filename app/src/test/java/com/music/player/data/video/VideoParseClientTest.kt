package com.music.player.data.video

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VideoParseClientTest {

    @Test
    fun extractUrlFromShareText() {
        val text = "0.23 复制打开抖音，看看【作者】的作品 https://v.douyin.com/iAbc123/ 这是描述"
        val url = VideoParseClient.extractUrl(text)
        assertTrue(url.startsWith("https://v.douyin.com/"))
    }

    @Test
    fun parseDataEnvelopeWithVideo() {
        val json = """
            {
              "code": 200,
              "msg": "success",
              "data": {
                "title": "测试视频",
                "cover": "https://cdn.example.com/cover.jpg",
                "url": "https://cdn.example.com/a.mp4"
              }
            }
        """.trimIndent()
        val r = VideoParseClient.parseResponse(json)
        assertEquals("测试视频", r.title)
        assertEquals("https://cdn.example.com/a.mp4", r.videoUrl)
        assertEquals("https://cdn.example.com/cover.jpg", r.coverUrl)
        assertTrue(r.hasMedia)
    }

    @Test
    fun parseNestedErrorHasNoMedia() {
        val json = """{"error":{"code":403,"message":"访问被拒绝: 无效的apikey"}}"""
        val r = VideoParseClient.parseResponse(json)
        assertFalse(r.hasMedia)
        assertEquals("访问被拒绝: 无效的apikey", VideoParseClient.extractErrorMessage(json))
    }

    @Test
    fun parseImageList() {
        val json = """
            {
              "code": 1,
              "data": {
                "title": "图集",
                "images": [
                  "https://cdn.example.com/1.jpg",
                  "https://cdn.example.com/2.jpg"
                ]
              }
            }
        """.trimIndent()
        val r = VideoParseClient.parseResponse(json)
        assertEquals(2, r.imageUrls.size)
        assertTrue(r.hasMedia)
    }
}
