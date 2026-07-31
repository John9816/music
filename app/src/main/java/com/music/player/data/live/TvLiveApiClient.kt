package com.music.player.data.live

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

object TvLiveApiClient {

    private const val ENDPOINT = "https://danboxingqiu.cn/iptv.m3u"
    private const val DEFAULT_GROUP = "Other"

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .callTimeout(15, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .followRedirects(true)
            .build()
    }

    @Volatile
    private var memory: TvChannelCache.Snapshot? = null

    data class LoadResult(
        val channels: List<TvChannel>,
        val fromCache: Boolean,
        val savedAtMs: Long
    )

    /** Returns any cached snapshot immediately, even when it is stale. */
    suspend fun loadCachedChannels(context: Context): TvChannelCache.Snapshot? =
        withContext(Dispatchers.IO) {
            memory ?: TvChannelCache(context.applicationContext).load()?.also { memory = it }
        }

    suspend fun loadChannels(
        context: Context,
        forceRefresh: Boolean = false,
        ttlMs: Long = TvChannelCache.DEFAULT_TTL_MS
    ): Result<LoadResult> = withContext(Dispatchers.IO) {
        val cache = TvChannelCache(context.applicationContext)
        val now = System.currentTimeMillis()

        if (!forceRefresh) {
            val mem = memory
            if (mem != null && mem.isFresh(now, ttlMs)) {
                return@withContext Result.success(LoadResult(mem.channels, true, mem.savedAtMs))
            }
            val disk = cache.load()
            if (disk != null && disk.isFresh(now, ttlMs)) {
                memory = disk
                return@withContext Result.success(LoadResult(disk.channels, true, disk.savedAtMs))
            }
            if (disk != null) memory = disk
        }

        val remote = fetchRemote()
        remote.fold(
            onSuccess = { list ->
                val snap = TvChannelCache.Snapshot(list, now)
                memory = snap
                cache.save(list, now)
                Result.success(LoadResult(list, false, now))
            },
            onFailure = { err ->
                val fallback = memory ?: cache.load()
                if (fallback != null && fallback.channels.isNotEmpty()) {
                    memory = fallback
                    Result.success(LoadResult(fallback.channels, true, fallback.savedAtMs))
                } else {
                    Result.failure(err)
                }
            }
        )
    }

    suspend fun fetchChannels(): Result<List<TvChannel>> = withContext(Dispatchers.IO) {
        fetchRemote()
    }

    private fun fetchRemote(): Result<List<TvChannel>> = runCatching {
        val request = Request.Builder()
            .url(ENDPOINT)
            .get()
            .header("Accept", "audio/x-mpegurl, application/vnd.apple.mpegurl, text/plain, */*")
            .header("User-Agent", "MusicPlayer/1.0 (Android)")
            .build()
        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                error("TV live source failed: HTTP ${response.code}")
            }
            parseM3u(body).also {
                if (it.isEmpty()) error("TV live source is empty")
            }
        }
    }

    fun parseM3u(raw: String): List<TvChannel> {
        val text = raw.trim().removePrefix("\uFEFF")
        if (text.isBlank()) return emptyList()
        val lines = text.lineSequence().map { it.trim() }.filter { it.isNotBlank() }
        val out = ArrayList<TvChannel>()
        var pending: ChannelMeta? = null
        for (line in lines) {
            when {
                line.startsWith("#EXTINF", ignoreCase = true) -> {
                    pending = parseExtInf(line)
                }
                line.startsWith("#") -> Unit
                pending != null -> {
                    if (isPlayableUrl(line)) {
                        out += TvChannel(
                            name = pending.name,
                            group = pending.group.ifBlank { DEFAULT_GROUP },
                            playUrl = line,
                            logoUrl = pending.logoUrl
                        )
                    }
                    pending = null
                }
            }
        }
        return out.distinctBy { it.name + "\u0000" + it.playUrl }
    }

    private fun parseExtInf(line: String): ChannelMeta {
        val commaIndex = line.indexOf(',')
        val rawNamePart = if (commaIndex > 0) line.substring(commaIndex + 1).trim() else ""
        val attrsPart = if (commaIndex >= 0) line.substring(0, commaIndex).trim() else line
        val attrs = ATTRIBUTE_PATTERN.findAll(attrsPart).associate { match ->
            val key = match.groupValues[1]
            val value = match.groupValues[2].ifBlank { match.groupValues[3] }
            key to value.trim()
        }
        val rawName = rawNamePart.ifBlank { attrs["tvg-name"].orEmpty() }.trim()
        val name = rawName.ifBlank { "Unknown" }
        val group = attrs["group-title"].orEmpty().trim().stripLeadingEmoji()
        return ChannelMeta(
            name = name,
            group = group,
            logoUrl = attrs["tvg-logo"].orEmpty().trim()
        )
    }

    private fun isPlayableUrl(line: String): Boolean =
        line.startsWith("http://", ignoreCase = true) ||
            line.startsWith("https://", ignoreCase = true) ||
            line.startsWith("rtmp://", ignoreCase = true)

    private fun String.stripLeadingEmoji(): String =
        replace(LEADING_DECORATION_PATTERN, "").trim()

    internal fun clearMemoryCache() {
        memory = null
    }

    private data class ChannelMeta(
        val name: String,
        val group: String,
        val logoUrl: String
    )

    private val ATTRIBUTE_PATTERN = Regex("""([\w-]+)=(?:"([^"]*)"|([^\s]+))""")
    private val LEADING_DECORATION_PATTERN = Regex("^[^\\p{L}\\p{N}\\u4e00-\\u9fff]+")
}
