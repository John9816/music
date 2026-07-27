package com.music.player.data.settings

import org.junit.Assert.assertEquals
import org.junit.Test

class AudioQualityPreferencesTest {
    @Test
    fun mapsMeteredNetworkPolicyToRealPlaybackQuality() {
        val preferred = AudioQualityPreferences.Level.JYMASTER
        assertEquals(
            AudioQualityPreferences.Level.STANDARD,
            AudioQualityPreferences.levelForMeteredNetwork(
                preferred,
                AppSettings.MobileStreamQuality.WIFI_ONLY
            )
        )
        assertEquals(
            AudioQualityPreferences.Level.EXHIGH,
            AudioQualityPreferences.levelForMeteredNetwork(
                preferred,
                AppSettings.MobileStreamQuality.HIGH
            )
        )
        assertEquals(
            AudioQualityPreferences.Level.LOSSLESS,
            AudioQualityPreferences.levelForMeteredNetwork(
                preferred,
                AppSettings.MobileStreamQuality.EXTREME
            )
        )
    }

    @Test
    fun meteredNetworkPolicyDoesNotUpgradeLowerPreferredQuality() {
        val preferred = AudioQualityPreferences.Level.STANDARD
        assertEquals(
            AudioQualityPreferences.Level.STANDARD,
            AudioQualityPreferences.levelForMeteredNetwork(
                preferred,
                AppSettings.MobileStreamQuality.EXTREME
            )
        )
    }

    @Test
    fun orderedLevelsStartsAtPreferredAndCapsAttempts() {
        val levels = AudioQualityPreferences.orderedLevels(AudioQualityPreferences.Level.JYMASTER)
        assertEquals(AudioQualityPreferences.Level.JYMASTER, levels.first())
        assertEquals(3, levels.size)
        // Only descend in quality — never try unrelated higher tiers after preferred.
        assertEquals(
            listOf(
                AudioQualityPreferences.Level.JYMASTER,
                AudioQualityPreferences.Level.SKY,
                AudioQualityPreferences.Level.JYEFFECT
            ),
            levels
        )
    }

    @Test
    fun orderedLevelsForStandardIsShort() {
        val levels = AudioQualityPreferences.orderedLevels(AudioQualityPreferences.Level.STANDARD)
        assertEquals(listOf(AudioQualityPreferences.Level.STANDARD), levels)
    }
}
