package com.music.player.data.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AiDrawClientTest {

    @Test
    fun parsesPlainUrl() {
        val r = AiDrawClient.parseImageResult("https://cdn.example.com/a.png")
        assertEquals("https://cdn.example.com/a.png", r.imageUrl)
    }

    @Test
    fun parsesJsonUrlField() {
        val r = AiDrawClient.parseImageResult("""{"code":0,"data":{"url":"https://img.example/x.jpg"}}""")
        assertEquals("https://img.example/x.jpg", r.imageUrl)
    }

    @Test
    fun parsesHtmlImg() {
        val r = AiDrawClient.parseImageResult("""<html><img src="https://img.example/y.png"/></html>""")
        assertEquals("https://img.example/y.png", r.imageUrl)
    }

    @Test
    fun parsesDataUri() {
        val r = AiDrawClient.parseImageResult("data:image/png;base64,abc123")
        assertTrue(r.imageBase64!!.startsWith("data:image/png"))
    }
}
