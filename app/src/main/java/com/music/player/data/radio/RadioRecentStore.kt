package com.music.player.data.radio

import android.content.Context
import com.music.player.data.model.RadioStation
import org.json.JSONArray
import org.json.JSONObject

/**
 * Local recently-played radio stations (name + playUrl), newest first.
 */
class RadioRecentStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun load(): List<RadioStation> {
        val raw = prefs.getString(KEY_RECENT, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val name = o.optString("name").trim()
                    val url = o.optString("playUrl").trim()
                    if (name.isNotBlank() && url.isNotBlank()) {
                        add(RadioStation(name = name, playUrl = url))
                    }
                }
            }
        }.getOrDefault(emptyList())
    }

    fun remember(station: RadioStation) {
        val next = buildList {
            add(station)
            load().forEach { existing ->
                if (existing.playUrl != station.playUrl && existing.name != station.name) {
                    add(existing)
                }
            }
        }.take(MAX_RECENT)
        val arr = JSONArray()
        next.forEach { s ->
            arr.put(
                JSONObject()
                    .put("name", s.name)
                    .put("playUrl", s.playUrl)
            )
        }
        prefs.edit().putString(KEY_RECENT, arr.toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "radio_recent"
        private const val KEY_RECENT = "stations"
        private const val MAX_RECENT = 12
    }
}
