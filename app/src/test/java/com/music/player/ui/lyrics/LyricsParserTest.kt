package com.music.player.ui.lyrics

import org.junit.Assert.assertEquals
import org.junit.Test

class LyricsParserTest {

    @Test
    fun appliesGlobalOffsetBeforeSelectingActiveLine() {
        val lines = LyricsParser.parse(
            """
            [offset:500]
            [00:01.00]First line
            [00:02.50]Second line
            """.trimIndent()
        )

        assertEquals(1.5f, lines[0].time)
        assertEquals(3.0f, lines[1].time)
        assertEquals(-1, LyricsParser.findActiveIndex(lines, 1_499))
        assertEquals(0, LyricsParser.findActiveIndex(lines, 1_500))
        assertEquals(1, LyricsParser.findActiveIndex(lines, 3_000))
    }

    @Test
    fun supportsMultipleTimeTagsAndKeepsLinesSorted() {
        val lines = LyricsParser.parse("[00:03.00][00:01.00]Repeat\n[00:02.00]Middle")

        assertEquals(listOf(1f, 2f, 3f), lines.map { it.time })
        assertEquals("Repeat", lines.first().text)
    }

    @Test
    fun removesInlineWordTimingTagsFromKaraokeLyrics() {
        val lines = LyricsParser.parse(
            "[00:29.00]<0,280>や<280,170>っ<450,250>ぱ<700,410>り<1110,190>摘<1300,300>み<1600,260>取<1860,180>る"
        )

        assertEquals(1, lines.size)
        assertEquals(29f, lines.single().time)
        assertEquals("やっぱり摘み取る", lines.single().text)
    }
}
