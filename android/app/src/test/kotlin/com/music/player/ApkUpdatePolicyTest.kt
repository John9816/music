package com.music.player

import org.junit.Assert.*
import org.junit.Test

class ApkUpdatePolicyTest {
    private val installed = InstalledApk("com.music.player", 2066, setOf("production"))

    @Test fun acceptsNewerSameApplicationAndSigner() {
        assertNull(ApkUpdatePolicy.rejection(installed, installed.copy(versionCode = 2067)))
    }

    @Test fun refusesProductionAsAnUpdateToDebugApp() {
        assertEquals("WRONG_PACKAGE", ApkUpdatePolicy.rejection(
            installed.copy(packageName = "com.music.player.debug"), installed.copy(versionCode = 2067)
        )?.code)
    }

    @Test fun refusesDifferentOrMissingSigners() {
        for (signers in listOf(setOf("debug"), emptySet())) {
            assertEquals("WRONG_SIGNATURE", ApkUpdatePolicy.rejection(
                installed, installed.copy(versionCode = 2067, signers = signers)
            )?.code)
        }
    }

    @Test fun refusesSameVersionAndArchitectureDowngrades() {
        for (version in listOf(2066L, 67L)) {
            assertEquals("NOT_NEWER", ApkUpdatePolicy.rejection(
                installed, installed.copy(versionCode = version)
            )?.code)
        }
    }
}
