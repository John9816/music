package com.music.player.ui.util

import android.net.Uri
import java.util.Locale

object ImageUrl {
    fun bestQuality(url: String?): String? = sanitize(url)

    fun thumbnail(url: String?, size: Int = 240): String? = resize(url, width = size, height = size)

    fun banner(url: String?, width: Int = 720, height: Int = 720): String? =
        resize(url, width = width, height = height)

    private fun resize(url: String?, width: Int, height: Int): String? {
        val sanitized = sanitize(url) ?: return null
        val uri = runCatching { Uri.parse(sanitized) }.getOrNull() ?: return sanitized
        val host = uri.host?.lowercase(Locale.US).orEmpty()
        val supportsNeteaseResize = host.contains("music.126.net") || host.endsWith(".126.net")
        if (!supportsNeteaseResize) return sanitized

        return uri.buildUpon()
            .clearQuery()
            .appendQueryParameter("param", "${width}y$height")
            .build()
            .toString()
    }

    private fun sanitize(url: String?): String? {
        val raw = url?.trim().orEmpty()
        if (raw.isBlank()) return null
        // Kuwo still returns HTTP artwork for some songs; Android blocks
        // those requests under the app's cleartext policy.
        return raw.replaceFirst(Regex("^http://", RegexOption.IGNORE_CASE), "https://")
    }
}
