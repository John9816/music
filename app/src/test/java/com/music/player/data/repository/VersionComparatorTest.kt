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
            "DuckMusic-v1.0.3.apk"
        )

        assertTrue(
            ReleaseApkSelector.selectName(assets, "1.0.3", debug = false) ==
                "DuckMusic-v1.0.3.apk"
        )
        assertTrue(
            ReleaseApkSelector.selectName(assets, "v1.0.3", debug = true) ==
                "DuckMusic-v1.0.3-debug.apk"
        )
        assertTrue(
            ReleaseApkSelector.selectName(listOf("app-debug.apk"), "1.0.3", debug = false) == null
        )
    }
}
