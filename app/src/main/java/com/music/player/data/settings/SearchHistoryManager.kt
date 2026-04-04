package com.music.player.data.settings

import android.content.Context
import android.content.SharedPreferences

class SearchHistoryManager(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("search_history", Context.MODE_PRIVATE)

    companion object {
        private const val KEY_HISTORY = "recent_queries"
        private const val SEPARATOR = "|||"
        private const val MAX_HISTORY = 15
    }

    fun getHistory(): List<String> {
        val raw = prefs.getString(KEY_HISTORY, null) ?: return emptyList()
        return raw.split(SEPARATOR).filter { it.isNotBlank() }.take(MAX_HISTORY)
    }

    fun addQuery(query: String) {
        val trimmed = query.trim()
        if (trimmed.isBlank()) return
        val list = getHistory().toMutableList()
        list.remove(trimmed)
        list.add(0, trimmed)
        val capped = list.take(MAX_HISTORY)
        prefs.edit().putString(KEY_HISTORY, capped.joinToString(SEPARATOR)).apply()
    }

    fun removeQuery(query: String) {
        val list = getHistory().toMutableList()
        list.remove(query.trim())
        prefs.edit().putString(KEY_HISTORY, list.joinToString(SEPARATOR)).apply()
    }

    fun clearAll() {
        prefs.edit().remove(KEY_HISTORY).apply()
    }
}
