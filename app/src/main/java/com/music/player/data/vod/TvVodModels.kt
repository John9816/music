package com.music.player.data.vod

import com.google.gson.annotations.SerializedName

/**
 * TVBox 标准 JSON 数据模型 (Gson)
 * 兼容主流 TVBox 订阅源格式
 */
data class TvVodHomeResponse(
    @SerializedName("class") val categories: List<TvVodCategory>? = null,
    @SerializedName("list") val list: List<TvVodItem>? = null,
    val page: Int = 1,
    val pagecount: Int = 0,
    val limit: Int = 20,
    val total: Int = 0
)

data class TvVodCategory(
    @SerializedName("type_id") val typeId: String,
    @SerializedName("type_name") val typeName: String
)

data class TvVodDetailResponse(
    @SerializedName("list") val list: List<TvVodItem>? = null
)

data class TvVodItem(
    @SerializedName("vod_id") val vodId: String,
    @SerializedName("vod_name") val vodName: String,
    @SerializedName("vod_pic") val vodPic: String = "",
    @SerializedName("vod_remarks") val vodRemarks: String = "",
    @SerializedName("vod_year") val vodYear: String = "",
    @SerializedName("vod_score") val vodScore: String = "",
    @SerializedName("type_name") val typeName: String = "",
    @SerializedName("vod_content") val vodContent: String = "",
    @SerializedName("vod_play_from") val vodPlayFrom: String = "",
    @SerializedName("vod_play_url") val vodPlayUrl: String = "",
    @SerializedName("vod_actor") val vodActor: String = "",
    @SerializedName("vod_director") val vodDirector: String = ""
) {
    /** 解析播放列表: Map<来源名, List<(集名, URL)>> */
    fun parsePlayUrls(): Map<String, List<Pair<String, String>>> {
        if (vodPlayUrl.isBlank()) return emptyMap()
        val sources = vodPlayFrom.split("$$$").filter { it.isNotBlank() }
        val urlsBySource = vodPlayUrl.split("$$$").filter { it.isNotBlank() }
        val result = LinkedHashMap<String, List<Pair<String, String>>>()
        sources.forEachIndexed { index, source ->
            val episodes = urlsBySource.getOrNull(index)?.split("#")?.filter { it.isNotBlank() }
                ?.mapNotNull { ep ->
                    val idx = ep.lastIndexOf('$')
                    if (idx > 0 && idx < ep.length - 1) {
                        ep.substring(0, idx).trim() to ep.substring(idx + 1).trim()
                    } else null
                } ?: emptyList()
            if (episodes.isNotEmpty()) {
                result[source.trim()] = episodes
            }
        }
        return result
    }
}
