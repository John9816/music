package com.music.player.data.live

object TvSourceSelector {

    fun preferredIndex(sources: List<TvChannel>, preferredUrl: String?): Int {
        if (sources.isEmpty()) return 0
        val matched = sources.indexOfFirst { it.playUrl == preferredUrl }
        return matched.takeIf { it >= 0 } ?: 0
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
                .thenBy { it }
        )
    }
}
