package com.music.player.data.repository

/**
 * Pure helpers for user-library list pagination (favorites / history / playlists / tracks).
 * Keeps page-walking logic unit-testable without Retrofit.
 */
object LibraryPageParser {

    const val DEFAULT_PAGE_SIZE = 100
    /** Hard cap so a buggy API cannot loop forever. */
    const val MAX_PAGES = 50

    /**
     * Whether another page should be requested after receiving [pageItemCount] items
     * for the given [page] (0-based) and [pageSize].
     *
     * Rules:
     * - empty page → stop
     * - fewer than pageSize → last page
     * - [totalElements] known and already covered → stop
     * - [totalPages] known and next page would exceed → stop
     * - otherwise continue while under [maxPages]
     */
    fun shouldFetchNextPage(
        page: Int,
        pageSize: Int,
        pageItemCount: Int,
        totalElements: Int? = null,
        totalPages: Int? = null,
        maxPages: Int = MAX_PAGES
    ): Boolean {
        if (pageItemCount <= 0) return false
        if (pageItemCount < pageSize) return false
        val nextPage = page + 1
        if (nextPage >= maxPages) return false
        if (totalPages != null && totalPages > 0 && nextPage >= totalPages) return false
        if (totalElements != null && totalElements >= 0) {
            val loadedThrough = (page + 1) * pageSize
            // If the page was full we may still have more; stop only when covered.
            if (loadedThrough >= totalElements) return false
        }
        return true
    }

    /**
     * Extract pagination metadata from a Spring-style / website envelope `data` object fields.
     * Accepts common aliases; missing values stay null.
     */
    fun readTotalElements(dataKeys: Map<String, Any?>): Int? =
        intOrNull(dataKeys, "totalElements", "total", "totalCount", "count")

    fun readTotalPages(dataKeys: Map<String, Any?>): Int? =
        intOrNull(dataKeys, "totalPages", "pages", "pageCount")

    private fun intOrNull(map: Map<String, Any?>, vararg keys: String): Int? {
        for (key in keys) {
            val raw = map[key] ?: continue
            when (raw) {
                is Number -> return raw.toInt().takeIf { it >= 0 }
                is String -> raw.trim().toIntOrNull()?.takeIf { it >= 0 }?.let { return it }
            }
        }
        return null
    }
}
