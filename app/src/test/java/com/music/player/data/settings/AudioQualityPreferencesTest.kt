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
}
