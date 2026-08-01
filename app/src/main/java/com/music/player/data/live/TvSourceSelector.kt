package com.music.player.data.live

/**
 * Picks and ranks live stream URLs for ExoPlayer (Media3).
 *
 * Preference order among healthy sources:
 * 1. User's last successful URL (when still healthy)
 * 2. HLS (.m3u8) over progressive / FLV
 * 3. HTTPS over HTTP
 * 4. Recently failed URLs last
 *
 * RTMP/RTSP are not Exo-friendly after libmpv removal and rank worst if present.
 */
object TvSourceSelector {

    fun preferredIndex(sources: List<TvChannel>, preferredUrl: String?): Int {
        if (sources.isEmpty()) return 0
        val matched = sources.indexOfFirst { it.playUrl == preferredUrl }
        if (matched >= 0) return matched
        // No remembered URL: start on the best Exo-friendly source.
        return sources.indices.minWithOrNull(
            compareBy<Int> { protocolRank(sources[it].playUrl) }.thenBy { it }
        ) ?: 0
    }

    fun attemptOrder(
        sources: List<TvChannel>,
        startIndex: Int,
        deprioritizedUrls: Set<String> = emptySet()
    ): List<Int> {
        if (sources.isEmpty()) return emptyList()
        val safeStart = startIndex.coerceIn(0, sources.lastIndex)
        return sources.indices.sortedWith(
            compareBy<Int> { sources[it].playUrl in deprioritizedUrls }
                .thenBy { if (it == safeStart) 0 else 1 }
                .thenBy { protocolRank(sources[it].playUrl) }
                .thenBy { it }
        )
    }

    /** Stable sort used when building catalog source lists. */
    fun sortSourcesForExo(sources: List<TvChannel>): List<TvChannel> {
        if (sources.size <= 1) return sources
        return sources.sortedWith(
            compareBy<TvChannel> { protocolRank(it.playUrl) }
                .thenBy { it.playUrl }
        )
    }

    fun isExoPlayable(url: String): Boolean {
        val u = url.trim()
        if (u.isEmpty()) return false
        return u.startsWith("http://", ignoreCase = true) ||
            u.startsWith("https://", ignoreCase = true)
    }

    /**
     * Lower is better. Tuned for Media3 ExoPlayer live playback.
     */
    fun protocolRank(url: String): Int {
        val u = url.trim().lowercase()
        if (u.isEmpty()) return 100
        val isRtmp = u.startsWith("rtmp://") || u.startsWith("rtmps://") ||
            u.startsWith("rtsp://") || u.startsWith("rtsps://")
        if (isRtmp) return 90

        val isHls = u.contains(".m3u8")
        val isHttps = u.startsWith("https://")
        val isHttp = u.startsWith("http://")
        val isFlv = u.contains(".flv")
        val isMp4 = u.contains(".mp4")

        return when {
            isHls && isHttps -> 0
            isHls && isHttp -> 5
            isHttps && (isFlv || isMp4) -> 15
            isHttp && (isFlv || isMp4) -> 25
            isHttps -> 20
            isHttp -> 30
            else -> 50
        }
    }
}
