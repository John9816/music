package com.music.player.ui.util

object ImageUrl {
    fun bestQuality(url: String?): String? {
        val raw = url?.trim().orEmpty()
        if (raw.isBlank()) return null

        val hashIndex = raw.indexOf('#')
        val noHash = if (hashIndex >= 0) raw.substring(0, hashIndex) else raw
        val hash = if (hashIndex >= 0) raw.substring(hashIndex) else ""

        val qIndex = noHash.indexOf('?')
        if (qIndex < 0) return raw

        val base = noHash.substring(0, qIndex)
        return base + hash
    }
}
