package com.music.player.ui.util

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LegacyRenderingCompatTest {

    @Test
    fun enablesFallbackForRedmi6AOnAndroid9() {
        assertTrue(
            requiresLegacySoftwareRendering(
                sdkInt = 28,
                manufacturer = "Xiaomi",
                model = "Redmi 6A",
                device = "cactus"
            )
        )
    }

    @Test
    fun enablesFallbackWhenOnlyDeviceCodenameMatches() {
        assertTrue(
            requiresLegacySoftwareRendering(
                sdkInt = 27,
                manufacturer = "Xiaomi",
                model = "Unknown",
                device = "cactus"
            )
        )
    }

    @Test
    fun doesNotAffectNewerOrUnrelatedDevices() {
        assertFalse(
            requiresLegacySoftwareRendering(
                sdkInt = 29,
                manufacturer = "Xiaomi",
                model = "Redmi 6A",
                device = "cactus"
            )
        )
        assertFalse(
            requiresLegacySoftwareRendering(
                sdkInt = 28,
                manufacturer = "Samsung",
                model = "SM-G9500",
                device = "dreamqltechn"
            )
        )
    }
}
