package com.music.player.data.repository

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class UpdateDownloadSelectorTest {

    @Test
    fun picksExactAbiMatch() {
        val downloads = mapOf(
            "arm64-v8a" to "https://cdn/a.apk",
            "x86_64" to "https://cdn/x.apk"
        )
        assertEquals(
            "https://cdn/x.apk",
            UpdateDownloadSelector.selectUrl(downloads, listOf("x86_64"), null)
        )
    }

    @Test
    fun matchesAbiCaseInsensitively() {
        val downloads = mapOf("ARM64-V8A" to "https://cdn/a.apk")
        assertEquals(
            "https://cdn/a.apk",
            UpdateDownloadSelector.selectUrl(downloads, listOf("arm64-v8a"), null)
        )
    }

    @Test
    fun usesFirstSupportedAbiThatMatches() {
        val downloads = mapOf(
            "arm64-v8a" to "https://cdn/a.apk",
            "armeabi-v7a" to "https://cdn/v7.apk"
        )
        assertEquals(
            "https://cdn/v7.apk",
            UpdateDownloadSelector.selectUrl(
                downloads,
                listOf("armeabi-v7a", "arm64-v8a"),
                null
            )
        )
    }

    @Test
    fun fallsBackToLegacyUrlWhenDownloadsMapIsEmpty() {
        assertEquals(
            "https://cdn/legacy.apk",
            UpdateDownloadSelector.selectUrl(emptyMap(), listOf("arm64-v8a"), "https://cdn/legacy.apk")
        )
    }

    @Test
    fun returnsNullWhenNoAbiMatches() {
        // A device ABI with no matching package must NOT receive an incompatible URL:
        // the download would succeed and only the install would fail with a confusing error.
        val downloads = mapOf("arm64-v8a" to "https://cdn/a.apk")
        assertNull(
            UpdateDownloadSelector.selectUrl(
                downloads,
                listOf("x86_64"),
                "https://cdn/legacy-arm64.apk"
            )
        )
    }
}
