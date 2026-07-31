package com.music.player.data.live

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class TvChannelCache(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    data class Snapshot(
        val channels: List<TvChannel>,
        val savedAtMs: Long
    ) {
        fun isFresh(nowMs: Long = System.currentTimeMillis(), ttlMs: Long = DEFAULT_TTL_MS): Boolean =
            channels.isNotEmpty() && nowMs - savedAtMs in 0 until ttlMs
    }

    fun load(): Snapshot? {
        val raw = prefs.getString(KEY_JSON, null) ?: return null
        val savedAt = prefs.getLong(KEY_SAVED_AT, 0L)
        if (savedAt <= 0L) return null
        val channels = decode(raw)
        if (channels.isEmpty()) return null
        return Snapshot(channels, savedAt)
    }

    fun save(channels: List<TvChannel>, savedAtMs: Long = System.currentTimeMillis()) {
        if (channels.isEmpty()) return
        prefs.edit()
            .putString(KEY_JSON, encode(channels))
            .putLong(KEY_SAVED_AT, savedAtMs)
            .apply()
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val PREFS_NAME = "tv_channel_cache"
        private const val KEY_JSON = "channels_json"
        private const val KEY_SAVED_AT = "saved_at_ms"

        const val DEFAULT_TTL_MS: Long = 12L * 60L * 60L * 1000L

        fun encode(channels: List<TvChannel>): String {
            val arr = JSONArray()
            channels.forEach { channel ->
                arr.put(
                    JSONObject()
                        .put("name", channel.name)
                        .put("group", channel.group)
                        .put("playUrl", channel.playUrl)
                        .put("logoUrl", channel.logoUrl)
                )
            }
            return arr.toString()
        }

        fun decode(raw: String): List<TvChannel> {
            return runCatching {
                val arr = JSONArray(raw)
                buildList {
                    for (i in 0 until arr.length()) {
                        val o = arr.optJSONObject(i) ?: continue
                        val name = o.optString("name").trim()
                        val group = o.optString("group").trim()
                        val playUrl = o.optString("playUrl").trim()
                            .ifBlank { o.optString("play_url").trim() }
                        val logoUrl = o.optString("logoUrl").trim()
                            .ifBlank { o.optString("logo").trim() }
                        if (name.isNotBlank() && playUrl.isNotBlank()) {
                            add(TvChannel(name, group, playUrl, logoUrl))
                        }
                    }
                }
            }.getOrDefault(emptyList())
        }
    }
}
