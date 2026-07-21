package com.music.player.update

internal class AutomaticUpdateGate(
    private val minimumIntervalMs: Long = DEFAULT_INTERVAL_MS
) {
    private var lastStartedAtMs: Long? = null

    fun tryAcquire(nowMs: Long, requestInProgress: Boolean): Boolean {
        if (requestInProgress) return false
        val previous = lastStartedAtMs
        if (previous != null && nowMs - previous < minimumIntervalMs) return false
        lastStartedAtMs = nowMs
        return true
    }

    private companion object {
        const val DEFAULT_INTERVAL_MS = 15 * 60 * 1000L
    }
}
