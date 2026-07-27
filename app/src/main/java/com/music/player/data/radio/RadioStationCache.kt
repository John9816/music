package com.music.player.data.radio

import android.content.Context
import com.music.player.data.model.RadioStation
import org.json.JSONArray
import org.json.JSONObject

/**
 * Disk cache for the live radio directory. Station lists change rarely;
 * default TTL avoids hitting the remote API on every page open.
 */
class RadioStationCache(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    data class Snapshot(
        val stations: List<RadioStation>,
        val savedAtMs: Long
    ) {
        fun isFresh(nowMs: Long = System.currentTimeMillis(), ttlMs: Long = DEFAULT_TTL_MS): Boolean =
            stations.isNotEmpty() && nowMs - savedAtMs in 0 until ttlMs

        fun ageMs(nowMs: Long = System.currentTimeMillis()): Long =
            (nowMs - savedAtMs).coerceAtLeast(0L)
    }

    fun load(): Snapshot? {
        val raw = prefs.getString(KEY_JSON, null) ?: return null
        val savedAt = prefs.getLong(KEY_SAVED_AT, 0L)
        if (savedAt <= 0L) return null
        val stations = decode(raw)
        if (stations.isEmpty()) return null
        return Snapshot(stations = stations, savedAtMs = savedAt)
    }

    fun save(stations: List<RadioStation>, savedAtMs: Long = System.currentTimeMillis()) {
        if (stations.isEmpty()) return
        prefs.edit()
            .putString(KEY_JSON, encode(stations))
            .putLong(KEY_SAVED_AT, savedAtMs)
            .apply()
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val PREFS_NAME = "radio_station_cache"
        private const val KEY_JSON = "stations_json"
        private const val KEY_SAVED_AT = "saved_at_ms"

        /** 24h — directory rarely changes; pull-to-refresh still forces network. */
        const val DEFAULT_TTL_MS: Long = 24L * 60L * 60L * 1000L

        fun encode(stations: List<RadioStation>): String {
            val arr = JSONArray()
            stations.forEach { s ->
                arr.put(
                    JSONObject()
                        .put("name", s.name)
                        .put("playUrl", s.playUrl)
                )
            }
            return arr.toString()
        }

        fun decode(raw: String): List<RadioStation> {
            return runCatching {
                val arr = JSONArray(raw)
                buildList {
                    for (i in 0 until arr.length()) {
                        val o = arr.optJSONObject(i) ?: continue
                        val name = o.optString("name").trim()
                        val url = o.optString("playUrl").trim()
                            .ifBlank { o.optString("play_url").trim() }
                        if (name.isNotBlank() && url.isNotBlank()) {
                            add(RadioStation(name = name, playUrl = url))
                        }
                    }
                }
            }.getOrDefault(emptyList())
        }
    }
}
