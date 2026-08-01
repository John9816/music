package com.music.player.data.common

import com.google.gson.Gson

/**
 * Shared [Gson] singleton — Gson instances are thread-safe and relatively heavyweight
 * to construct, so one shared instance serves all disk caches and JSON serialization.
 */
object GsonProvider {
    val gson: Gson = Gson()
}
