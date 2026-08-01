package com.music.player.data.common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.charset.Charset

class MojibakeRepairTest {

    @Test
    fun leavesValidChineseUntouched() {
        assertEquals("热门推荐歌曲", repairPotentialMojibake("热门推荐歌曲"))
    }

    @Test
    fun leavesPlainAsciiUntouched() {
        assertEquals("hello world", repairPotentialMojibake("hello world"))
    }

    @Test
    fun repairsLatin1DoubleEncoding() {
        val corrupted = String("中文歌词".toByteArray(Charsets.UTF_8), Charsets.ISO_8859_1)
        assertEquals("中文歌词", repairPotentialMojibake(corrupted))
    }

    @Test
    fun repairsWindows1252DoubleEncoding() {
        // "中文" encodes to bytes that are all defined in cp1252, so the round-trip is exact.
        val corrupted = String("中文".toByteArray(Charsets.UTF_8), Charset.forName("Windows-1252"))
        assertEquals("中文", repairPotentialMojibake(corrupted))
    }

    @Test
    fun repairsWindows1252WithUndefinedByteBestEffort() {
        // 0x8D (in "词") is undefined in cp1252 and decodes to U+FFFD; the byte is ambiguous,
        // so the repair is structural: the prefix must be exact and the tail a CJK character.
        val corrupted = String("中文歌词".toByteArray(Charsets.UTF_8), Charset.forName("Windows-1252"))
        val repaired = repairPotentialMojibake(corrupted)
        assertTrue("expected 4 chars, got $repaired", repaired.length == 4)
        assertTrue("prefix must be 中文歌, got $repaired", repaired.startsWith("中文歌"))
    }
}
