package com.music.player.data.radio

import com.music.player.data.model.RadioStation

/**
 * Best-effort region label from Chinese radio station names (e.g. 河北音乐广播 → 河北).
 */
object RadioRegionHelper {

    /** Longer keys first so 内蒙古 / 黑龙江 win over shorter prefixes. */
    private val REGIONS = listOf(
        "内蒙古", "黑龙江", "宁夏", "新疆", "西藏", "广西",
        "北京", "天津", "上海", "重庆", "河北", "山西", "辽宁", "吉林",
        "江苏", "浙江", "安徽", "福建", "江西", "山东", "河南", "湖北",
        "湖南", "广东", "海南", "四川", "贵州", "云南", "陕西", "甘肃",
        "青海", "香港", "澳门", "台湾"
    )

    const val ALL = "全部"
    const val RECENT = "最近"
    const val OTHER = "其他"

    fun regionOf(name: String): String {
        val n = name.trim()
        for (r in REGIONS) {
            if (n.startsWith(r) || n.contains(r)) return r
        }
        return OTHER
    }

    fun regionOf(station: RadioStation): String = regionOf(station.name)

    /**
     * Chip labels: 全部, 最近 (if any), then regions by frequency (cap), then 其他 if present.
     */
    fun buildChipLabels(
        stations: List<RadioStation>,
        hasRecent: Boolean,
        maxRegions: Int = 14
    ): List<String> {
        if (stations.isEmpty() && !hasRecent) return listOf(ALL)
        val counts = linkedMapOf<String, Int>()
        stations.forEach { s ->
            val r = regionOf(s)
            counts[r] = (counts[r] ?: 0) + 1
        }
        val otherCount = counts.remove(OTHER) ?: 0
        val ranked = counts.entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .map { it.key }
            .take(maxRegions)
        return buildList {
            add(ALL)
            if (hasRecent) add(RECENT)
            addAll(ranked)
            if (otherCount > 0) add(OTHER)
        }
    }

    fun avatarLetter(name: String): String {
        val t = name.trim()
        if (t.isEmpty()) return "播"
        val region = regionOf(t)
        if (region != OTHER) return region.take(1)
        return t.take(1)
    }
}
