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

        // NetEase supports ?param=<w>y<h> resize; keep this for red-source covers.
        if (host.contains("music.126.net") || host.endsWith(".126.net")) {
            return uri.buildUpon()
                .clearQuery()
                .appendQueryParameter("param", "${width}y$height")
                .build()
                .toString()
        }

        // QQ Music covers embed the size tier as "R<w>x<h>" in the path
        // (e.g. .../T002R800x800M000....jpg). Rewriting the segment gives a
        // much smaller image without an extra network round-trip.
        if (host.endsWith("gtimg.cn") || host.endsWith("qpic.cn")) {
            val target = width.coerceAtMost(height)
            val tier = qqSizeTier(target)
            val rewritten = QQ_SIZE_REGEX.replace(sanitized, "R${tier}x${tier}")
            if (rewritten != sanitized) return rewritten
        }

        return sanitized
    }

    private fun qqSizeTier(target: Int): Int {
        // QQ CDN only serves a handful of fixed sizes — pick the smallest that
        // still covers our display box to keep bitmap decode cheap.
        return when {
            target <= 150 -> 150
            target <= 300 -> 300
            target <= 500 -> 500
            else -> 800
        }
    }

    private val QQ_SIZE_REGEX = Regex("R\\d{2,4}x\\d{2,4}")

    private fun sanitize(url: String?): String? {
        val raw = url?.trim().orEmpty()
        if (raw.isBlank()) return null
        // Kuwo still returns HTTP artwork for some songs; Android blocks
        // those requests under the app's cleartext policy.
        return raw.replaceFirst(Regex("^http://", RegexOption.IGNORE_CASE), "https://")
    }
}
