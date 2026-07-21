package com.music.player.update

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomaticUpdateGateTest {

    @Test
    fun firstRequestIsAllowed() {
        val gate = AutomaticUpdateGate(minimumIntervalMs = 1_000)

        assertTrue(gate.tryAcquire(nowMs = 0, requestInProgress = false))
    }

    @Test
    fun requestIsBlockedWhileAnotherCheckIsRunning() {
        val gate = AutomaticUpdateGate(minimumIntervalMs = 1_000)

        assertFalse(gate.tryAcquire(nowMs = 0, requestInProgress = true))
    }

    @Test
    fun repeatedRequestIsDebouncedUntilIntervalExpires() {
        val gate = AutomaticUpdateGate(minimumIntervalMs = 1_000)
        assertTrue(gate.tryAcquire(nowMs = 100, requestInProgress = false))

        assertFalse(gate.tryAcquire(nowMs = 1_099, requestInProgress = false))
        assertTrue(gate.tryAcquire(nowMs = 1_100, requestInProgress = false))
    }
}
