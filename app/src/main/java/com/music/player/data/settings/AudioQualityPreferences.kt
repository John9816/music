package com.music.player.data.settings

import android.content.Context
import com.music.player.data.api.NetworkRuntime

object AudioQualityPreferences {

    private const val PREFS_NAME = "playback_prefs"

    // Used by both repository and settings UI.
    const val KEY_PREFERRED_LEVEL = "preferred_audio_level"
    const val DEFAULT_LEVEL_STORAGE_VALUE = "jymaster"

    enum class Level(
        val storageValue: String,
        val displayName: String
    ) {
        STANDARD("standard", "标准"),
        EXHIGH("exhigh", "极高"),
        LOSSLESS("lossless", "无损"),
        HIRES("hires", "Hi-Res"),
        JYMASTER("jymaster", "超清母带"),
        SKY("sky", "沉浸环绕声"),
        JYEFFECT("jyeffect", "高清环绕声");

        companion object {
            fun fromStorage(value: String?): Level {
                return entries.firstOrNull { it.storageValue.equals(value, ignoreCase = true) } ?: JYMASTER
            }
        }
    }

    private val defaultAttemptOrder: List<Level> = listOf(
        Level.JYMASTER,
        Level.SKY,
        Level.JYEFFECT,
        Level.HIRES,
        Level.LOSSLESS,
        Level.EXHIGH,
        Level.STANDARD
    )

    fun getPreferredLevel(context: Context): Level {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return Level.fromStorage(prefs.getString(KEY_PREFERRED_LEVEL, DEFAULT_LEVEL_STORAGE_VALUE))
    }

    fun getPreferredLevel(): Level = getPreferredLevel(NetworkRuntime.applicationContext())

    fun getPlaybackLevel(context: Context): Level {
        val preferred = getPreferredLevel(context)
        if (!NetworkRuntime.isActiveNetworkMetered()) return preferred
        return levelForMeteredNetwork(preferred, AppSettings.mobileStreamQuality(context))
    }

    fun getPlaybackLevel(): Level = getPlaybackLevel(NetworkRuntime.applicationContext())

    fun getPreferredLevelStorageValue(context: Context): String = getPreferredLevel(context).storageValue

    fun setPreferredLevel(context: Context, level: Level) {
        context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PREFERRED_LEVEL, level.storageValue)
            .apply()
    }

    fun orderedLevels(context: Context): List<Level> = orderedLevels(getPreferredLevel(context))

    fun orderedLevels(): List<Level> = orderedLevels(getPreferredLevel())

    internal fun levelForMeteredNetwork(
        preferred: Level,
        quality: AppSettings.MobileStreamQuality
    ): Level {
        val meteredLimit = when (quality) {
            AppSettings.MobileStreamQuality.WIFI_ONLY,
            AppSettings.MobileStreamQuality.STANDARD -> Level.STANDARD
            AppSettings.MobileStreamQuality.HIGH -> Level.EXHIGH
            AppSettings.MobileStreamQuality.EXTREME -> Level.LOSSLESS
        }
        return preferred.coerceAtMostQuality(meteredLimit)
    }

    private fun Level.coerceAtMostQuality(limit: Level): Level {
        val currentRank = defaultAttemptOrder.indexOf(this)
        val limitRank = defaultAttemptOrder.indexOf(limit)
        if (currentRank < 0 || limitRank < 0) return limit
        return if (currentRank <= limitRank) limit else this
    }

    fun orderedLevels(preferredLevel: Level): List<Level> {
        return if (defaultAttemptOrder.contains(preferredLevel)) {
            listOf(preferredLevel) + defaultAttemptOrder.filterNot { it == preferredLevel }
        } else {
            defaultAttemptOrder
        }
    }

    fun orderedAttemptStorageValues(preferredStorageValue: String?): List<String> {
        return orderedLevels(Level.fromStorage(preferredStorageValue)).map { it.storageValue }
    }
}
