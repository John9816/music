package com.music.player.data.vod

import android.util.Log
import com.google.gson.Gson
import com.music.player.data.api.NetworkRuntime
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * TVBox 标准订阅源 API 客户端
 * 支持分类 / 列表 / 详情 / 搜索
 */
object TvVodApiClient {

    private const val TAG = "TvVodApi"
    private const val DEFAULT_SOURCE = "https://tv.laotv.top"

    private val gson = Gson()
    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectionPool(NetworkRuntime.connectionPool())
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .callTimeout(20, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .followRedirects(true)
            .build()
    }

    /** 获取分类列表 */
    fun fetchCategories(source: String = DEFAULT_SOURCE): Result<List<TvVodCategory>> =
        runCatching {
            val url = "$source/api.php/provide/vod/at/xml/?ac=list"
            val json = executeGet(url)
            val resp = gson.fromJson(json, TvVodHomeResponse::class.java)
            resp.categories ?: emptyList()
        }

    /** 获取分类下的影片列表 (分页) */
    fun fetchVodList(
        source: String = DEFAULT_SOURCE,
        typeId: String = "",
        page: Int = 1
    ): Result<TvVodHomeResponse> = runCatching {
        val url = buildString {
            append("$source/api.php/provide/vod/at/xml/?ac=list")
            if (typeId.isNotBlank()) append("&t=$typeId")
            if (page > 1) append("&pg=$page")
        }
        val json = executeGet(url)
        gson.fromJson(json, TvVodHomeResponse::class.java)
    }

    /** 搜索影片 */
    fun searchVod(
        source: String = DEFAULT_SOURCE,
        keyword: String,
        page: Int = 1
    ): Result<TvVodHomeResponse> = runCatching {
        val url = buildString {
            append("$source/api.php/provide/vod/at/xml/?ac=search")
            append("&wd=$keyword")
            if (page > 1) append("&pg=$page")
        }
        val json = executeGet(url)
        gson.fromJson(json, TvVodHomeResponse::class.java)
    }

    /** 获取影片详情 (包含播放地址) */
    fun fetchVodDetail(
        source: String = DEFAULT_SOURCE,
        vodId: String
    ): Result<TvVodItem?> = runCatching {
        val url = "$source/api.php/provide/vod/at/xml/?ac=detail&ids=$vodId"
        val json = executeGet(url)
        val resp = gson.fromJson(json, TvVodDetailResponse::class.java)
        resp.list?.firstOrNull()
    }

    private fun executeGet(url: String): String {
        Log.d(TAG, "GET $url")
        val request = Request.Builder()
            .url(url)
            .get()
            .header("Accept", "application/json, text/plain, */*")
            .header("User-Agent", "MusicPlayer/1.0 (Android; TV VOD)")
            .build()
        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                error("TV VOD request failed: HTTP ${response.code}")
            }
            return body
        }
    }

    /** 持久化存储用户配置的订阅源 */
    object SourceStore {
        private const val PREFS_NAME = "tv_vod_source"
        private const val KEY_SOURCE = "source_url"

        fun get(context: android.content.Context): String {
            val prefs = context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            return prefs.getString(KEY_SOURCE, DEFAULT_SOURCE) ?: DEFAULT_SOURCE
        }

        fun set(context: android.content.Context, url: String) {
            context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_SOURCE, url)
                .apply()
        }
    }
}
