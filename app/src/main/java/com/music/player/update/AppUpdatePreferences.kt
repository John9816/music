package com.music.player.update

import android.content.Context

class AppUpdatePreferences(context: Context) {

    companion object {
        private const val PREFS_NAME = "app_update_prefs"
        private const val KEY_SKIPPED_BUILD = "skipped_build_number"
        private const val KEY_LAST_AUTO_CHECK_AT = "last_auto_check_at_ms"

        /** Auto checks re-hit the network at most once per interval, even across restarts. */
        const val AUTO_CHECK_MIN_INTERVAL_MS = 6L * 60L * 60L * 1000L
    }

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun lastAutoCheckAtMs(): Long = prefs.getLong(KEY_LAST_AUTO_CHECK_AT, 0L)

    fun markAutoCheckAt(nowMs: Long = System.currentTimeMillis()) {
        prefs.edit().putLong(KEY_LAST_AUTO_CHECK_AT, nowMs).apply()
    }

    fun shouldSuppressAutoPrompt(buildNumber: Int, force: Boolean): Boolean {
        if (force) return false
        return prefs.getInt(KEY_SKIPPED_BUILD, -1) >= buildNumber
    }

    fun markSkipped(buildNumber: Int) {
        prefs.edit().putInt(KEY_SKIPPED_BUILD, buildNumber).apply()
    }

    fun clearSkippedIfOlderThan(buildNumber: Int) {
        val skippedBuild = prefs.getInt(KEY_SKIPPED_BUILD, -1)
        if (skippedBuild in 0 until buildNumber) {
            prefs.edit().remove(KEY_SKIPPED_BUILD).apply()
        }
    }
}
