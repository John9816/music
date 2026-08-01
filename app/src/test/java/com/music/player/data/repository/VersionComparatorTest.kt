package com.music.player.data.repository

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VersionComparatorTest {
    @Test
    fun comparesSemanticVersions() {
        assertTrue(VersionComparator.isNewer("1.0.2", "1.0.3"))
        assertTrue(VersionComparator.isNewer("1.9.9", "2.0.0"))
        assertFalse(VersionComparator.isNewer("1.0.2", "1.0.2"))
        assertFalse(VersionComparator.isNewer("2.0.0", "1.99.99"))
    }

    @Test
    fun ignoresTagPrefixAndPrereleaseSuffix() {
        assertTrue(VersionComparator.isNewer("v1.0.2-debug", "V1.1.0"))
    }

    @Test
    fun selectsOnlyExactReleaseAssetForCurrentChannel() {
        val assets = listOf(
            "app-debug.apk",
            "DuckMusic-v1.0.3-debug.apk",
            "DuckMusic-v1.0.3.apk",
            "DuckMusic-v1.0.3-arm64-v8a.apk",
            "DuckMusic-v1.0.3-armeabi-v7a.apk"
        )

        assertTrue(
            ReleaseApkSelector.selectName(
                assets,
                "1.0.3",
                debug = false,
                supportedAbis = listOf("arm64-v8a", "armeabi-v7a")
            ) == "DuckMusic-v1.0.3-arm64-v8a.apk"
        )
        assertTrue(
            ReleaseApkSelector.selectName(assets, "v1.0.3", debug = true) ==
                "DuckMusic-v1.0.3-debug.apk"
        )
        assertTrue(
            ReleaseApkSelector.selectName(listOf("app-debug.apk"), "1.0.3", debug = false) == null
        )
    }

    @Test
    fun selectsDownloadForFirstSupportedAbi() {
        val downloads = mapOf(
            "armeabi-v7a" to "https://example.com/app-v7a.apk",
            "arm64-v8a" to "https://example.com/app-arm64.apk"
        )

        assertTrue(
            UpdateDownloadSelector.selectUrl(
                downloads,
                supportedAbis = listOf("arm64-v8a", "armeabi-v7a"),
                legacyDownloadUrl = "https://example.com/app-default.apk"
            ) == "https://example.com/app-arm64.apk"
        )
    }

    @Test
    fun noIncompatibleUrlWhenAbiMissingFromDownloads() {
        // An ABI-mismatched device must NOT receive a URL it cannot install: the download
        // would succeed and only the install would fail with a confusing error.
        assertTrue(
            UpdateDownloadSelector.selectUrl(
                downloads = mapOf("arm64-v8a" to "https://example.com/app-arm64.apk"),
                supportedAbis = listOf("x86_64"),
                legacyDownloadUrl = "https://example.com/app-default.apk"
            ) == null
        )
    }

    @Test
    fun supportsLegacySingleDownloadManifest() {
        assertTrue(
            UpdateDownloadSelector.selectUrl(
                downloads = emptyMap(),
                supportedAbis = listOf("arm64-v8a"),
                legacyDownloadUrl = "https://example.com/app.apk"
            ) == "https://example.com/app.apk"
        )
    }
}
