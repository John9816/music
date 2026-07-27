package com.music.player.data.settings

import android.content.Context
import kotlin.math.ceil

object AppSettings {
    private const val PREFS_NAME = "settings"
    private const val KEY_SLEEP_TIMER_END_TIME = "sleep_timer_end_time"
    private const val KEY_DOWNLOAD_WIFI_ONLY = "download_wifi_only"
    private const val KEY_MOBILE_STREAM_QUALITY = "stream_quality"
    private const val KEY_OFFLINE_ONLY = "offline_only"
    private const val KEY_LYRIC_OFFSET_MS = "lyric_offset_ms"
    private const val KEY_EQUALIZER_PRESET = "equalizer_preset"
    private const val KEY_VIDEO_PARSE_API_KEY = "video_parse_api_key"

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

    fun isOfflineOnly(context: Context): Boolean =
        prefs(context).getBoolean(KEY_OFFLINE_ONLY, false)

    fun setOfflineOnly(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_OFFLINE_ONLY, enabled).apply()
    }

    /** User lyric offset in milliseconds (positive = lyrics later). */
    fun lyricOffsetMs(context: Context): Int =
        prefs(context).getInt(KEY_LYRIC_OFFSET_MS, 0)

    fun setLyricOffsetMs(context: Context, offsetMs: Int) {
        prefs(context).edit().putInt(KEY_LYRIC_OFFSET_MS, offsetMs.coerceIn(-10_000, 10_000)).apply()
    }

    fun equalizerPreset(context: Context): com.music.player.playback.AudioEqualizerController.Preset {
        return com.music.player.playback.AudioEqualizerController.Preset.fromStorage(
            prefs(context).getString(KEY_EQUALIZER_PRESET, null)
        )
    }

    fun setEqualizerPreset(
        context: Context,
        preset: com.music.player.playback.AudioEqualizerController.Preset
    ) {
        prefs(context).edit().putString(KEY_EQUALIZER_PRESET, preset.storageValue).apply()
    }

    /** Optional override for 聚合解析 apikey; empty falls back to BuildConfig. */
    fun videoParseApiKey(context: Context): String =
        prefs(context).getString(KEY_VIDEO_PARSE_API_KEY, null)?.trim().orEmpty()

    fun setVideoParseApiKey(context: Context, key: String) {
        val trimmed = key.trim()
        prefs(context).edit().apply {
            if (trimmed.isEmpty()) remove(KEY_VIDEO_PARSE_API_KEY)
            else putString(KEY_VIDEO_PARSE_API_KEY, trimmed)
        }.apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
