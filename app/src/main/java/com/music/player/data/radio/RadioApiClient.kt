package com.music.player.data.radio

import android.content.Context
import com.music.player.data.model.RadioStation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Live radio directory: https://api.qhsou.com/api/ygdf.php
 *
 * Uses [RadioStationCache] so opening the page does not always hit the network.
 * Fresh cache (default 24h) is returned as-is; only expired/missing/forced loads fetch remote.
 */
object RadioApiClient {

    private const val ENDPOINT = "https://api.qhsou.com/api/ygdf.php"

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .callTimeout(35, TimeUnit.SECONDS)
            .build()
    }

    @Volatile
    private var memory: RadioStationCache.Snapshot? = null

    data class LoadResult(
        val stations: List<RadioStation>,
        /** true when served from memory/disk without a successful network round-trip this call */
        val fromCache: Boolean,
        val savedAtMs: Long
    )

    /**
     * @param forceRefresh skip TTL and always request remote (pull-to-refresh / menu refresh)
     * @param ttlMs cache freshness window; default [RadioStationCache.DEFAULT_TTL_MS]
     */
    suspend fun loadStations(
        context: Context,
        forceRefresh: Boolean = false,
        ttlMs: Long = RadioStationCache.DEFAULT_TTL_MS
    ): Result<LoadResult> = withContext(Dispatchers.IO) {
        val cache = RadioStationCache(context.applicationContext)
        val now = System.currentTimeMillis()

        if (!forceRefresh) {
            val mem = memory
            if (mem != null && mem.isFresh(now, ttlMs)) {
                return@withContext Result.success(
                    LoadResult(mem.stations, fromCache = true, savedAtMs = mem.savedAtMs)
                )
            }
            val disk = cache.load()
            if (disk != null && disk.isFresh(now, ttlMs)) {
                memory = disk
                return@withContext Result.success(
                    LoadResult(disk.stations, fromCache = true, savedAtMs = disk.savedAtMs)
                )
            }
            // Stale disk: still usable as fallback if network fails
            if (disk != null) {
                memory = disk
            }
        }

        val remote = fetchRemote()
        remote.fold(
            onSuccess = { list ->
                val snap = RadioStationCache.Snapshot(stations = list, savedAtMs = now)
                memory = snap
                cache.save(list, now)
                Result.success(LoadResult(list, fromCache = false, savedAtMs = now))
            },
            onFailure = { err ->
                val fallback = memory ?: cache.load()
                if (fallback != null && fallback.stations.isNotEmpty()) {
                    memory = fallback
                    Result.success(
                        LoadResult(
                            stations = fallback.stations,
                            fromCache = true,
                            savedAtMs = fallback.savedAtMs
                        )
                    )
                } else {
                    Result.failure(err)
                }
            }
        )
    }

    /** Network-only; does not touch cache. Prefer [loadStations]. */
    suspend fun fetchStations(): Result<List<RadioStation>> = withContext(Dispatchers.IO) {
        fetchRemote()
    }

    private fun fetchRemote(): Result<List<RadioStation>> = runCatching {
        val request = Request.Builder()
            .url(ENDPOINT)
            .get()
            .header("Accept", "application/json")
            .header("User-Agent", "MusicPlayer/1.0 (Android)")
            .build()
        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                error("电台列表加载失败 HTTP ${response.code}")
            }
            parseStations(body).also {
                if (it.isEmpty()) error("电台列表为空")
            }
        }
    }

    fun parseStations(raw: String): List<RadioStation> {
        val text = raw.trim()
        if (text.isBlank()) return emptyList()
        val root = runCatching { JSONObject(text) }.getOrNull() ?: return emptyList()
        val list = root.optJSONArray("radio_list") ?: return emptyList()
        val out = ArrayList<RadioStation>(list.length())
        for (i in 0 until list.length()) {
            val item = list.optJSONObject(i) ?: continue
            val name = item.optString("name").trim()
            val url = item.optString("play_url").trim()
                .ifBlank { item.optString("url").trim() }
                .ifBlank { item.optString("playUrl").trim() }
            if (name.isBlank() || url.isBlank()) continue
            out += RadioStation(name = name, playUrl = url)
        }
        return out
    }

    /** Test / debug helper */
    internal fun clearMemoryCache() {
        memory = null
    }
}
