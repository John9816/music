package com.music.player.data.live

import android.content.Context
import android.util.Log
import com.music.player.data.api.NetworkRuntime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.TimeUnit

object TvLiveApiClient {

    private const val TAG = "TvLiveApiClient"
    /**
     * Primary feed first; fallbacks are tried in order when an upstream is down or returns
     * an empty/undecodable playlist, so a single dead mirror cannot take down TV live.
     */
    private val SOURCE_URLS = listOf(
        "https://danboxingqiu.cn/iptv.m3u",
        "https://live.fanmingming.cn/tv/m3u/ipv6.m3u"
    )
    private const val DEFAULT_GROUP = "Other"

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectionPool(NetworkRuntime.connectionPool())
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .callTimeout(15, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .followRedirects(true)
            .build()
    }

    @Volatile
    private var memory: TvChannelCache.Snapshot? = null
    private val memoryMutex = Mutex()

    /**
     * Single-flight guard for the network fetch. Only one fetch runs at a time and every
     * concurrent caller awaits the same result, so a slow source never causes duplicate
     * requests and never blocks the fast cache-read path.
     */
    private val fetchMutex = Mutex()
    private val fetchInFlight = AtomicReference<Deferred<Result<List<TvChannel>>>?>(null)
    private val fetchScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    data class LoadResult(
        val channels: List<TvChannel>,
        val fromCache: Boolean,
        val savedAtMs: Long
    )

    /** Returns any cached snapshot immediately, even when it is stale. */
    suspend fun loadCachedChannels(context: Context): TvChannelCache.Snapshot? =
        withContext(Dispatchers.IO) {
            memoryMutex.withLock {
                memory ?: TvChannelCache(context.applicationContext).load()?.also { memory = it }
            }
        }

    suspend fun loadChannels(
        context: Context,
        forceRefresh: Boolean = false,
        ttlMs: Long = TvChannelCache.DEFAULT_TTL_MS
    ): Result<LoadResult> = withContext(Dispatchers.IO) {
        val cache = TvChannelCache(context.applicationContext)
        val now = System.currentTimeMillis()

        // Fast path: memory/disk reads are atomic and never wait on the network.
        if (!forceRefresh) {
            val cached: Result<LoadResult>? = memoryMutex.withLock {
                val mem = memory
                when {
                    mem != null && mem.isFresh(now, ttlMs) ->
                        Result.success(LoadResult(mem.channels, true, mem.savedAtMs))
                    else -> {
                        val disk = cache.load()
                        when {
                            disk != null && disk.isFresh(now, ttlMs) -> {
                                memory = disk
                                Result.success(LoadResult(disk.channels, true, disk.savedAtMs))
                            }
                            else -> {
                                if (disk != null) memory = disk
                                null
                            }
                        }
                    }
                }
            }
            if (cached != null) return@withContext cached
        }

        // Network fetch is single-flighted: concurrent callers await the same request.
        val remote = fetchRemoteSingleFlight()
        remote.fold(
            onSuccess = { list ->
                val snap = TvChannelCache.Snapshot(list, now)
                memoryMutex.withLock {
                    memory = snap
                }
                cache.save(list, now)
                Result.success(LoadResult(list, false, now))
            },
            onFailure = { err ->
                memoryMutex.withLock {
                    val fallback = memory ?: cache.load()
                    if (fallback != null && fallback.channels.isNotEmpty()) {
                        memory = fallback
                        Result.success(LoadResult(fallback.channels, true, fallback.savedAtMs))
                    } else {
                        Result.failure(err)
                    }
                }
            }
        )
    }

    suspend fun fetchChannels(): Result<List<TvChannel>> = withContext(Dispatchers.IO) {
        fetchRemoteSingleFlight()
    }

    /**
     * Runs at most one network fetch at a time and hands every caller the same result.
     * A cancelled caller does not cancel the shared fetch, so other waiters still succeed.
     */
    private suspend fun fetchRemoteSingleFlight(): Result<List<TvChannel>> {
        val current = fetchInFlight.get()
        if (current != null && current.isActive) {
            return current.await()
        }
        return fetchMutex.withLock {
            val again = fetchInFlight.get()
            if (again != null && again.isActive) {
                again.await()
            } else {
                val fresh = fetchScope.async { fetchRemote() }
                fetchInFlight.set(fresh)
                fresh.invokeOnCompletion {
                    fetchInFlight.compareAndSet(fresh, null)
                }
                fresh.await()
            }
        }
    }

    private fun fetchRemote(): Result<List<TvChannel>> = runCatching {
        var lastError: Throwable? = null
        for (sourceUrl in SOURCE_URLS) {
            val parsed = runCatching { fetchSource(sourceUrl) }
                .getOrElse { error ->
                    Log.w(TAG, "TV live source failed: $sourceUrl", error)
                    lastError = error
                    emptyList()
                }
            if (parsed.isNotEmpty()) return@runCatching parsed
        }
        throw lastError ?: IllegalStateException("TV live sources unavailable")
    }

    private fun fetchSource(sourceUrl: String): List<TvChannel> {
        val request = Request.Builder()
            .url(sourceUrl)
            .get()
            .header("Accept", "audio/x-mpegurl, application/vnd.apple.mpegurl, text/plain, */*")
            .header("User-Agent", "MusicPlayer/1.0 (Android)")
            .build()
        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                error("TV live source failed: HTTP ${response.code} from $sourceUrl")
            }
            return parseM3u(body)
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

    /** ExoPlayer/Media3 only: drop RTMP/RTSP (no libmpv) so failover never burns time on them. */
    private fun isPlayableUrl(line: String): Boolean = TvSourceSelector.isExoPlayable(line)

    private fun String.stripLeadingEmoji(): String =
        replace(LEADING_DECORATION_PATTERN, "").trim()

    internal suspend fun clearMemoryCache() {
        memoryMutex.withLock { memory = null }
    }

    private data class ChannelMeta(
        val name: String,
        val group: String,
        val logoUrl: String
    )

    private val ATTRIBUTE_PATTERN = Regex("""([\w-]+)=(?:"([^"]*)"|([^\s]+))""")
    private val LEADING_DECORATION_PATTERN = Regex("^[^\\p{L}\\p{N}\\u4e00-\\u9fff]+")
}
