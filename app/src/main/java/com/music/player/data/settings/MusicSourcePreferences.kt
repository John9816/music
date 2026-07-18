package com.music.player.data.settings

import android.content.Context
import com.music.player.data.api.NetworkRuntime

object MusicSourcePreferences {

    private const val PREFS_NAME = "music_sources"
    private const val KEY_ACTIVE_SOURCE = "active_source"

    enum class Source(val storageValue: String, val displayName: String) {
        NETEASE("netease", "网易云音乐"),
        QQ("qq", "QQ 音乐"),
        KUWO("kuwo", "酷我音乐");

        companion object {
            fun fromStorage(value: String?): Source =
                entries.firstOrNull { it.storageValue == value } ?: NETEASE
        }
    }

    fun activeSource(context: Context): Source {
        return Source.fromStorage(prefs(context).getString(KEY_ACTIVE_SOURCE, null))
    }

    fun activeSource(): Source = activeSource(NetworkRuntime.applicationContext())

    fun setActiveSource(context: Context, source: Source) {
        prefs(context).edit().putString(KEY_ACTIVE_SOURCE, source.storageValue).apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
