package com.music.player.data.settings

import android.content.Context
import kotlin.math.ceil

object AppSettings {
    private const val PREFS_NAME = "settings"
    private const val KEY_SLEEP_TIMER_END_TIME = "sleep_timer_end_time"
    private const val KEY_DOWNLOAD_WIFI_ONLY = "download_wifi_only"
    private const val KEY_MOBILE_STREAM_QUALITY = "stream_quality"

    enum class MobileStreamQuality(val storageValue: String) {
        WIFI_ONLY("wifi_only"),
        STANDARD("standard"),
        HIGH("high"),
        EXTREME("extreme");

        companion object {
            fun fromStorage(value: String?): MobileStreamQuality {
                return entries.firstOrNull { it.storageValue == value } ?: WIFI_ONLY
            }
        }
    }

    fun setSleepTimer(context: Context, minutes: Long): Long {
        require(minutes > 0L)
        val endTime = System.currentTimeMillis() + minutes * 60_000L
        prefs(context).edit().putLong(KEY_SLEEP_TIMER_END_TIME, endTime).apply()
        return endTime
    }

    fun clearSleepTimer(context: Context) {
        prefs(context).edit().remove(KEY_SLEEP_TIMER_END_TIME).apply()
    }

    fun sleepTimerEndTime(context: Context): Long {
        return prefs(context).getLong(KEY_SLEEP_TIMER_END_TIME, 0L)
    }

    fun remainingSleepMinutes(context: Context, nowMs: Long = System.currentTimeMillis()): Long {
        val remainingMs = (sleepTimerEndTime(context) - nowMs).coerceAtLeast(0L)
        return if (remainingMs == 0L) 0L else ceil(remainingMs / 60_000.0).toLong()
    }

    fun isDownloadWifiOnly(context: Context): Boolean {
        return prefs(context).getBoolean(KEY_DOWNLOAD_WIFI_ONLY, true)
    }

    fun setDownloadWifiOnly(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_DOWNLOAD_WIFI_ONLY, enabled).apply()
    }

    fun mobileStreamQuality(context: Context): MobileStreamQuality {
        return MobileStreamQuality.fromStorage(
            prefs(context).getString(KEY_MOBILE_STREAM_QUALITY, MobileStreamQuality.WIFI_ONLY.storageValue)
        )
    }

    fun setMobileStreamQuality(context: Context, quality: MobileStreamQuality) {
        prefs(context).edit().putString(KEY_MOBILE_STREAM_QUALITY, quality.storageValue).apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
