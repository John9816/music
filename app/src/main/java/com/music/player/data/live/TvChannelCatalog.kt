package com.music.player.data.live

data class TvChannelCatalogItem(
    val key: String,
    val name: String,
    val group: String,
    val logoUrl: String,
    val sources: List<TvChannel>
)

object TvChannelCatalog {

    private val categoryOrder = listOf(
        "央视频道",
        "卫视频道",
        "广东地区",
        "湖南地区",
        "浙江地区",
        "江苏地区",
        "黑龙江地区",
        "江西地区",
        "陕西地区",
        "体育频道",
        "4K频道",
        "儿童频道"
    )

    fun build(sources: List<TvChannel>): List<TvChannelCatalogItem> {
        val categorized = sources.mapNotNull { source ->
            val category = categoryOf(source.group) ?: return@mapNotNull null
            category to source
        }
        val grouped = LinkedHashMap<String, MutableList<Pair<String, TvChannel>>>()
        categorized.forEach { categorizedSource ->
            val source = categorizedSource.second
            grouped.getOrPut(normalizeName(source.name)) { mutableListOf() }
                .add(categorizedSource)
        }

        return grouped.values.mapNotNull { candidates ->
            val category = candidates.first().first
            val channelSources = candidates.map { it.second }.distinctBy { it.playUrl }
            if (channelSources.size < minimumSourceCount(category)) return@mapNotNull null
            val first = channelSources.first()
            TvChannelCatalogItem(
                key = normalizeName(first.name),
                name = first.name.trim(),
                group = category,
                logoUrl = channelSources.firstOrNull { it.logoUrl.isNotBlank() }?.logoUrl.orEmpty(),
                sources = channelSources
            )
        }.sortedWith(
            compareBy<TvChannelCatalogItem> { categoryOrder.indexOf(it.group).coerceAtLeast(0) }
                .thenBy { it.name.lowercase() }
        )
    }

    private fun categoryOf(rawGroup: String): String? {
        val group = rawGroup.trim()
        return when {
            group.contains("央视", ignoreCase = true) || group.contains("CCTV", ignoreCase = true) -> "央视频道"
            group.contains("广东", ignoreCase = true) || group.contains("广东卫视", ignoreCase = true) -> "广东地区"
            group.contains("湖南", ignoreCase = true) || group.contains("湖南卫视", ignoreCase = true) -> "湖南地区"
            group.contains("浙江", ignoreCase = true) || group.contains("浙江卫视", ignoreCase = true) -> "浙江地区"
            group.contains("江苏", ignoreCase = true) || group.contains("江苏卫视", ignoreCase = true) -> "江苏地区"
            group.contains("黑龙江", ignoreCase = true) || group.contains("黑龙江卫视", ignoreCase = true) -> "黑龙江地区"
            group.contains("江西", ignoreCase = true) || group.contains("江西卫视", ignoreCase = true) -> "江西地区"
            group.contains("陕西", ignoreCase = true) || group.contains("陕西卫视", ignoreCase = true) -> "陕西地区"
            group.contains("卫视", ignoreCase = true) || group.contains("卫视频道", ignoreCase = true) -> "卫视频道"
            group.contains("体育", ignoreCase = true) || group.equals("SPORTS", ignoreCase = true) -> "体育频道"
            group.startsWith("4K", ignoreCase = true) || group.contains("4K", ignoreCase = true) -> "4K频道"
            group.contains("儿童", ignoreCase = true) || group.contains("少儿", ignoreCase = true) -> "儿童频道"
            else -> null
        }
    }

    private fun minimumSourceCount(category: String): Int = when (category) {
        "儿童频道", "英语频道" -> 1
        "4K频道" -> 2
        else -> 3
    }

    private fun normalizeName(name: String): String =
        name.trim().lowercase().replace(WHITESPACE_PATTERN, "")

    private val WHITESPACE_PATTERN = Regex("\\s+")
}
