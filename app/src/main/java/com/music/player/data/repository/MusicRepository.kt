package com.music.player.data.repository

import android.content.Context
import com.google.gson.JsonElement
import com.google.gson.JsonParser
import com.music.player.data.auth.AuthSessionManager
import com.music.player.data.auth.SupabaseClient
import com.music.player.data.api.RetrofitClient
import com.music.player.data.api.SongData
import com.music.player.data.common.RequestCoalescer
import com.music.player.data.common.TimedMemoryCache
import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.Playlist
import com.music.player.data.model.PlaylistCategory
import com.music.player.data.model.PlaylistCategoryCatalog
import com.music.player.data.model.PlaylistCategoryGroup
import com.music.player.data.model.Song
import com.music.player.data.settings.AudioQualityPreferences
import com.music.player.data.settings.MusicSourcePreferences
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import java.nio.charset.StandardCharsets

class MusicRepository(context: Context? = null) {

    private val api = RetrofitClient.musicApi
    private val sessionManager = context?.applicationContext?.let { AuthSessionManager(it) }

    companion object {
        private const val DISCOVER_TTL_MS = 3 * 60 * 1000L
        private const val PLAYLIST_TTL_MS = 10 * 60 * 1000L
        private const val CATEGORY_TTL_MS = 30 * 60 * 1000L
        private const val LYRICS_TTL_MS = 24 * 60 * 60 * 1000L
        private const val URL_TTL_MS = 20 * 60 * 1000L
        private const val SEARCH_TTL_MS = 5 * 60 * 1000L

        private val dailyRecommendCache = TimedMemoryCache<String, List<Song>>()
        private val topListsCache = TimedMemoryCache<String, List<Playlist>>()
        private val topPlaylistsCache = TimedMemoryCache<String, List<Playlist>>()
        private val playlistCategoryCache = TimedMemoryCache<String, PlaylistCategoryCatalog>()
        private val weeklyHotCache = TimedMemoryCache<String, List<Song>>()
        private val playlistDetailCache = TimedMemoryCache<String, Pair<Playlist, List<Song>>>()
        private val lyricsCache = TimedMemoryCache<String, String>()
        private val songUrlCache = TimedMemoryCache<String, String>()
        private val searchCache = TimedMemoryCache<String, List<Song>>()

        private val songListRequests = RequestCoalescer<String, Result<List<Song>>>()
        private val playlistListRequests = RequestCoalescer<String, Result<List<Playlist>>>()
        private val categoryRequests = RequestCoalescer<String, Result<PlaylistCategoryCatalog>>()
        private val playlistDetailRequests = RequestCoalescer<String, Result<Pair<Playlist, List<Song>>>>()
        private val stringRequests = RequestCoalescer<String, Result<String>>()
        private val searchRequests = RequestCoalescer<String, Result<List<Song>>>()

        @Volatile
        private var sharedApplicationContext: Context? = null

        fun setApplicationContext(context: Context) {
            sharedApplicationContext = context.applicationContext
        }

        fun clearCaches() {
            dailyRecommendCache.clear()
            topListsCache.clear()
            topPlaylistsCache.clear()
            playlistCategoryCache.clear()
            weeklyHotCache.clear()
            playlistDetailCache.clear()
            lyricsCache.clear()
            songUrlCache.clear()
            searchCache.clear()
        }
    }

    private suspend fun authorizationHeader(): String? {
        val manager = sessionManagerOrNull() ?: return null
        val token = manager.getValidAccessToken(SupabaseClient.authApi) ?: return null
        return "Bearer $token"
    }

    private fun sessionManagerOrNull(): AuthSessionManager? {
        return sessionManager ?: sharedApplicationContext?.let(::AuthSessionManager)
    }

    suspend fun getDailyRecommend(): Result<List<Song>> {
        return getDailyRecommend(forceRefresh = false)
    }

    suspend fun getDailyRecommend(forceRefresh: Boolean): Result<List<Song>> {
        val source = activeSourceValue()
        val cacheKey = "daily_recommend|$source"

        if (!forceRefresh) {
            dailyRecommendCache.get(cacheKey, DISCOVER_TTL_MS)?.let { return Result.success(it) }
        }

        return withContext(Dispatchers.IO) {
            songListRequests.run(cacheKey) {
                if (!forceRefresh) {
                    dailyRecommendCache.get(cacheKey, DISCOVER_TTL_MS)?.let { return@run Result.success(it) }
                }

                val direct = runCatching { api.getDailyRecommend(source = source) }
                if (direct.isSuccess) {
                    val response = direct.getOrThrow()
                    if (response.isSuccessful) {
                        val songs = parseSongsFromEnvelope(response.body()?.string().orEmpty())
                        if (songs.isNotEmpty()) {
                            dailyRecommendCache.put(cacheKey, songs)
                            return@run Result.success(songs)
                        }
                    }
                }

                getTopLists(forceRefresh = forceRefresh).fold(
                    onSuccess = { playlists ->
                        val firstPlaylistId = playlists
                            .firstOrNull { it.trackCount > 0 }
                            ?.id
                            ?: return@fold Result.failure(Exception("推荐歌单为空"))

                        getPlaylistDetail(firstPlaylistId, forceRefresh = forceRefresh).map { (_, songs) ->
                            songs.also {
                                if (it.isNotEmpty()) {
                                    dailyRecommendCache.put(cacheKey, it)
                                }
                            }
                        }
                    },
                    onFailure = { Result.failure(it) }
                )
            }
        }
    }


    suspend fun getTopLists(): Result<List<Playlist>> {
        return getTopLists(forceRefresh = false)
    }

    suspend fun getTopLists(forceRefresh: Boolean): Result<List<Playlist>> {
        val source = activeSourceValue()
        val cacheKey = "top_lists|$source"
        if (!forceRefresh) {
            topListsCache.get(cacheKey, PLAYLIST_TTL_MS)?.let { return Result.success(it) }
        }

        return withContext(Dispatchers.IO) {
            playlistListRequests.run(cacheKey) {
                if (!forceRefresh) {
                    topListsCache.get(cacheKey, PLAYLIST_TTL_MS)?.let { return@run Result.success(it) }
                }

                try {
                    val response = api.getTopLists(source = source)
                    if (response.isSuccessful) {
                        val playlists = parsePlaylistsFromEnvelope(response.body()?.string().orEmpty())
                        topListsCache.put(cacheKey, playlists)
                        Result.success(playlists)
                    } else {
                        Result.failure(Exception("获取榜单失败"))
                    }
                } catch (e: Exception) {
                    Result.failure(e)
                }
            }
        }
    }

    suspend fun getTopPlaylists(
        category: String? = "",
        limit: Int = 42,
        offset: Int = 0,
        device: String = "mobile"
    ): Result<List<Playlist>> {
        return getTopPlaylists(
            category = category,
            limit = limit,
            offset = offset,
            device = device,
            forceRefresh = false
        )
    }

    suspend fun getTopPlaylists(
        category: String?,
        limit: Int,
        offset: Int,
        device: String,
        forceRefresh: Boolean
    ): Result<List<Playlist>> {
        val normalizedCategory = category?.trim().orEmpty()
        val source = activeSourceValue()
        val cacheKey = "top_playlists|$source|$normalizedCategory|$limit|$offset|$device"
        if (!forceRefresh) {
            topPlaylistsCache.get(cacheKey, PLAYLIST_TTL_MS)?.let { return Result.success(it) }
        }

        return withContext(Dispatchers.IO) {
            playlistListRequests.run(cacheKey) {
                if (!forceRefresh) {
                    topPlaylistsCache.get(cacheKey, PLAYLIST_TTL_MS)?.let { return@run Result.success(it) }
                }

                try {
                    val response = api.getTopPlaylists(
                        source = source,
                        category = normalizedCategory.ifBlank { null },
                        page = (offset / limit.coerceAtLeast(1)) + 1,
                        pageSize = limit
                    )
                    if (response.isSuccessful) {
                        val playlists = parsePlaylistsFromEnvelope(response.body()?.string().orEmpty())
                        topPlaylistsCache.put(cacheKey, playlists)
                        Result.success(playlists)
                    } else {
                        Result.failure(Exception("获取歌单失败"))
                    }
                } catch (e: Exception) {
                    Result.failure(e)
                }
            }
        }
    }

    suspend fun getPlaylistCategories(
        device: String = "mobile"
    ): Result<PlaylistCategoryCatalog> {
        return getPlaylistCategories(device = device, forceRefresh = false)
    }

    suspend fun getPlaylistCategories(
        device: String,
        forceRefresh: Boolean
    ): Result<PlaylistCategoryCatalog> {
        val cacheKey = "playlist_categories_v2|$device"
        if (!forceRefresh) {
            playlistCategoryCache.get(cacheKey, CATEGORY_TTL_MS)?.let { return Result.success(it) }
        }

        val catalog = defaultPlaylistCategoryCatalog()
        playlistCategoryCache.put(cacheKey, catalog)
        return Result.success(catalog)
    }

    private fun defaultPlaylistCategoryCatalog(): PlaylistCategoryCatalog {
        return PlaylistCategoryCatalog(
            groups = listOf(
                PlaylistCategoryGroup(id = 0, name = "\u8bed\u79cd"),
                PlaylistCategoryGroup(id = 1, name = "\u98ce\u683c"),
                PlaylistCategoryGroup(id = 2, name = "\u573a\u666f"),
                PlaylistCategoryGroup(id = 3, name = "\u60c5\u7eea"),
                PlaylistCategoryGroup(id = 4, name = "\u4e3b\u9898")
            ),
            categories = listOf(
                PlaylistCategory(apiName = "\u534e\u8bed", name = "\u534e\u8bed", groupId = 0, groupName = "\u8bed\u79cd", hot = true),
                PlaylistCategory(apiName = "\u6b27\u7f8e", name = "\u6b27\u7f8e", groupId = 0, groupName = "\u8bed\u79cd"),
                PlaylistCategory(apiName = "\u65e5\u8bed", name = "\u65e5\u8bed", groupId = 0, groupName = "\u8bed\u79cd"),
                PlaylistCategory(apiName = "\u97e9\u8bed", name = "\u97e9\u8bed", groupId = 0, groupName = "\u8bed\u79cd"),
                PlaylistCategory(apiName = "\u7ca4\u8bed", name = "\u7ca4\u8bed", groupId = 0, groupName = "\u8bed\u79cd"),

                PlaylistCategory(apiName = "\u6d41\u884c", name = "\u6d41\u884c", groupId = 1, groupName = "\u98ce\u683c", hot = true),
                PlaylistCategory(apiName = "\u6447\u6eda", name = "\u6447\u6eda", groupId = 1, groupName = "\u98ce\u683c"),
                PlaylistCategory(apiName = "\u6c11\u8c23", name = "\u6c11\u8c23", groupId = 1, groupName = "\u98ce\u683c"),
                PlaylistCategory(apiName = "\u7535\u5b50", name = "\u7535\u5b50", groupId = 1, groupName = "\u98ce\u683c"),
                PlaylistCategory(apiName = "\u8bf4\u5531", name = "\u8bf4\u5531", groupId = 1, groupName = "\u98ce\u683c"),
                PlaylistCategory(apiName = "\u8f7b\u97f3\u4e50", name = "\u8f7b\u97f3\u4e50", groupId = 1, groupName = "\u98ce\u683c"),
                PlaylistCategory(apiName = "\u7235\u58eb", name = "\u7235\u58eb", groupId = 1, groupName = "\u98ce\u683c"),

                PlaylistCategory(apiName = "\u6e05\u6668", name = "\u6e05\u6668", groupId = 2, groupName = "\u573a\u666f", hot = true),
                PlaylistCategory(apiName = "\u591c\u665a", name = "\u591c\u665a", groupId = 2, groupName = "\u573a\u666f"),
                PlaylistCategory(apiName = "\u5b66\u4e60", name = "\u5b66\u4e60", groupId = 2, groupName = "\u573a\u666f"),
                PlaylistCategory(apiName = "\u5de5\u4f5c", name = "\u5de5\u4f5c", groupId = 2, groupName = "\u573a\u666f"),
                PlaylistCategory(apiName = "\u8fd0\u52a8", name = "\u8fd0\u52a8", groupId = 2, groupName = "\u573a\u666f"),
                PlaylistCategory(apiName = "\u9a7e\u8f66", name = "\u9a7e\u8f66", groupId = 2, groupName = "\u573a\u666f"),
                PlaylistCategory(apiName = "\u65c5\u884c", name = "\u65c5\u884c", groupId = 2, groupName = "\u573a\u666f"),

                PlaylistCategory(apiName = "\u6cbb\u6108", name = "\u6cbb\u6108", groupId = 3, groupName = "\u60c5\u7eea", hot = true),
                PlaylistCategory(apiName = "\u6000\u65e7", name = "\u6000\u65e7", groupId = 3, groupName = "\u60c5\u7eea"),
                PlaylistCategory(apiName = "\u5b89\u9759", name = "\u5b89\u9759", groupId = 3, groupName = "\u60c5\u7eea"),
                PlaylistCategory(apiName = "\u6d6a\u6f2b", name = "\u6d6a\u6f2b", groupId = 3, groupName = "\u60c5\u7eea"),
                PlaylistCategory(apiName = "\u4f24\u611f", name = "\u4f24\u611f", groupId = 3, groupName = "\u60c5\u7eea"),
                PlaylistCategory(apiName = "\u5feb\u4e50", name = "\u5feb\u4e50", groupId = 3, groupName = "\u60c5\u7eea"),

                PlaylistCategory(apiName = "\u5f71\u89c6\u539f\u58f0", name = "\u5f71\u89c6\u539f\u58f0", groupId = 4, groupName = "\u4e3b\u9898", hot = true),
                PlaylistCategory(apiName = "ACG", name = "ACG", groupId = 4, groupName = "\u4e3b\u9898"),
                PlaylistCategory(apiName = "\u6821\u56ed", name = "\u6821\u56ed", groupId = 4, groupName = "\u4e3b\u9898"),
                PlaylistCategory(apiName = "\u6e38\u620f", name = "\u6e38\u620f", groupId = 4, groupName = "\u4e3b\u9898"),
                PlaylistCategory(apiName = "\u7ffb\u5531", name = "\u7ffb\u5531", groupId = 4, groupName = "\u4e3b\u9898"),
                PlaylistCategory(apiName = "\u7f51\u7edc\u6b4c\u66f2", name = "\u7f51\u7edc\u6b4c\u66f2", groupId = 4, groupName = "\u4e3b\u9898"),
                PlaylistCategory(apiName = "\u53e4\u98ce", name = "\u53e4\u98ce", groupId = 4, groupName = "\u4e3b\u9898")
            )
        )
    }
    suspend fun getWeeklyHotNewSongs(
        limit: Int = 10,
        device: String = "mobile"
    ): Result<List<Song>> {
        return getWeeklyHotNewSongs(limit = limit, device = device, forceRefresh = false)
    }

    suspend fun getWeeklyHotNewSongs(
        limit: Int,
        device: String,
        forceRefresh: Boolean
    ): Result<List<Song>> {
        val source = activeSourceValue()
        val cacheKey = "weekly_hot|$source|$limit|$device"
        if (!forceRefresh) {
            weeklyHotCache.get(cacheKey, DISCOVER_TTL_MS)?.let { return Result.success(it) }
        }

        return withContext(Dispatchers.IO) {
            songListRequests.run(cacheKey) {
                if (!forceRefresh) {
                    weeklyHotCache.get(cacheKey, DISCOVER_TTL_MS)?.let { return@run Result.success(it) }
                }

                try {
                    val response = api.getWeeklyHotNewSongs(source = source, pageSize = limit)
                    if (!response.isSuccessful) {
                        return@run Result.failure(Exception("获取新歌失败"))
                    }
                    val songs = parseSongsFromEnvelope(response.body()?.string().orEmpty())
                    weeklyHotCache.put(cacheKey, songs)
                    Result.success(songs)
                } catch (e: Exception) {
                    Result.failure(e)
                }
            }
        }
    }
    suspend fun getPlaylistDetail(id: String): Result<Pair<Playlist, List<Song>>> {
        return getPlaylistDetail(id, forceRefresh = false)
    }

    suspend fun getPlaylistDetail(id: String, forceRefresh: Boolean): Result<Pair<Playlist, List<Song>>> {
        val normalizedId = id.trim()
        if (normalizedId.isBlank()) {
            return Result.failure(IllegalArgumentException("歌单 ID 为空"))
        }

        val source = activeSourceValue()
        val cacheKey = "$source|$normalizedId"
        if (!forceRefresh) {
            playlistDetailCache.get(cacheKey, PLAYLIST_TTL_MS)?.let { return Result.success(it) }
        }

        return withContext(Dispatchers.IO) {
            playlistDetailRequests.run(cacheKey) {
                if (!forceRefresh) {
                    playlistDetailCache.get(cacheKey, PLAYLIST_TTL_MS)?.let { return@run Result.success(it) }
                }

                try {
                    // QQ and Kuwo rankings use toplist/detail; regular collections
                    // use playlist/detail. Try the ranking shape first for Kuwo,
                    // whose chart IDs otherwise look like ordinary playlist IDs.
                    var detail: Pair<Playlist, List<Song>>? = null
                    if (source == MusicSourcePreferences.Source.KUWO.storageValue) {
                        val rankingResponse = api.getTopListDetail(source = source, id = normalizedId)
                        if (rankingResponse.isSuccessful) {
                            detail = parsePlaylistDetailFromEnvelope(
                                rankingResponse.body()?.string().orEmpty(),
                                fallbackId = normalizedId,
                                fallbackSource = source
                            )?.takeIf { it.second.isNotEmpty() }
                        }
                    }

                    val playlistResponse = if (detail == null && source != MusicSourcePreferences.Source.KUWO.storageValue) {
                        api.getPlaylistDetail(source = source, id = normalizedId)
                    } else null
                    if (detail == null && playlistResponse?.isSuccessful == true) {
                        detail = parsePlaylistDetailFromEnvelope(
                            playlistResponse.body()?.string().orEmpty(),
                            fallbackId = normalizedId,
                            fallbackSource = source
                        )
                    }

                    if (detail == null && source == MusicSourcePreferences.Source.QQ.storageValue) {
                        val rankingResponse = api.getTopListDetail(source = source, id = normalizedId)
                        if (rankingResponse.isSuccessful) {
                            detail = parsePlaylistDetailFromEnvelope(
                                rankingResponse.body()?.string().orEmpty(),
                                fallbackId = normalizedId,
                                fallbackSource = source
                            )
                        }
                    }
                    detail ?: return@run Result.failure(Exception("获取歌单详情失败"))
                    Result.success(detail.also { playlistDetailCache.put(cacheKey, it) })
                } catch (e: Exception) {
                    Result.failure(e)
                }
            }
        }
    }
    suspend fun searchSongs(keywords: String, limit: Int = 30, offset: Int = 0): Result<List<Song>> {
        val source = activeSourceValue()
        val cacheKey = "search_${source}_${keywords}_${limit}_${offset}"

        searchCache.get(cacheKey, SEARCH_TTL_MS)?.let { return Result.success(it) }

        return searchRequests.run(cacheKey) {
            withContext(Dispatchers.IO) {
                try {
                    val safeLimit = limit.coerceAtLeast(1)
                    val response = api.searchSongs(
                        source = source,
                        keyword = keywords,
                        page = (offset / safeLimit) + 1,
                        pageSize = safeLimit
                    )
                    if (response.isSuccessful) {
                        val songs = parseSongsFromEnvelope(response.body()?.string().orEmpty())
                        searchCache.put(cacheKey, songs)
                        Result.success(songs)
                    } else {
                        Result.failure(Exception("搜索歌曲失败"))
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Result.failure(e)
                }
            }
        }
    }
    suspend fun getSongUrl(id: String): Result<String> {
        return getSongUrl(id, source = activeSourceValue(), forceRefresh = false)
    }

    suspend fun getSongUrl(id: String, forceRefresh: Boolean): Result<String> {
        return getSongUrl(id, source = activeSourceValue(), forceRefresh = forceRefresh)
    }

    suspend fun getSongUrl(id: String, source: String, forceRefresh: Boolean = false): Result<String> {
        val normalizedId = id.trim()
        if (normalizedId.isBlank()) {
            return Result.failure(IllegalArgumentException("歌曲 ID 为空"))
        }

        val normalizedSource = normalizeSource(source)
        val preferredLevel = AudioQualityPreferences.getPlaybackLevel()
        val cacheKey = "$normalizedSource|$normalizedId|${preferredLevel.storageValue}"
        val requestKey = "song_url|$cacheKey"
        val orderedLevels = AudioQualityPreferences.orderedLevels(preferredLevel)

        if (!forceRefresh) {
            songUrlCache.get(cacheKey, URL_TTL_MS)?.let { return Result.success(it) }
        }

        return withContext(Dispatchers.IO) {
          stringRequests.run(requestKey) {
            if (!forceRefresh) {
                songUrlCache.get(cacheKey, URL_TTL_MS)?.let { return@run Result.success(it) }
            }

            try {
                var lastFailure: Exception? = null

                for (level in orderedLevels) {
                    var response = api.getSongUrl(
                        authorization = authorizationHeader(),
                        source = normalizedSource,
                        id = normalizedId,
                        level = level.toWebsiteQuality()
                    )
                    if (response.code() == 401) {
                        val refreshed = sessionManagerOrNull()?.forceRefresh(SupabaseClient.authApi)
                        if (!refreshed.isNullOrBlank()) {
                            response = api.getSongUrl(
                                authorization = "Bearer $refreshed",
                                source = normalizedSource,
                                id = normalizedId,
                                level = level.toWebsiteQuality()
                            )
                        }
                    }
                    val raw = response.body()?.string() ?: response.errorBody()?.string() ?: ""
                    val url = parseBackendSongUrl(raw)
                    if (response.isSuccessful && !url.isNullOrBlank()) {
                        songUrlCache.put(cacheKey, url)
                        return@run Result.success(url)
                    }

                    val code = response.code()
                    val snippet = raw.trim().replace(WHITESPACE_REGEX, " ").take(160)
                    val detail = listOf(
                        "level=${level.storageValue}",
                        "HTTP $code",
                        snippet.ifBlank { "empty response" }
                    ).filterNotNull().joinToString(", ")
                    lastFailure = Exception("song url backend failed ($detail)")
                }

                Result.failure(lastFailure ?: Exception("getSongUrl failed"))
            } catch (e: Exception) {
                Result.failure(e)
            }
          }
        }
    }

    suspend fun getLyrics(id: String): Result<String> {
        return getLyrics(id, source = activeSourceValue(), forceRefresh = false)
    }

    suspend fun getLyrics(id: String, forceRefresh: Boolean): Result<String> {
        return getLyrics(id, source = activeSourceValue(), forceRefresh = forceRefresh)
    }

    suspend fun getLyrics(id: String, source: String, forceRefresh: Boolean = false): Result<String> {
        val normalizedId = id.trim()
        if (normalizedId.isBlank()) {
            return Result.failure(IllegalArgumentException("歌曲 ID 为空"))
        }

        val normalizedSource = normalizeSource(source)
        val cacheKey = "$normalizedSource|$normalizedId"
        if (!forceRefresh) {
            lyricsCache.get(cacheKey, LYRICS_TTL_MS)?.let { return Result.success(it) }
        }

        return withContext(Dispatchers.IO) {
          stringRequests.run("lyrics|$cacheKey") {
            if (!forceRefresh) {
                lyricsCache.get(cacheKey, LYRICS_TTL_MS)?.let { return@run Result.success(it) }
            }

            try {
                val response = runCatching {
                    api.getLyric(
                        source = normalizedSource,
                        id = normalizedId,
                        timestamp = if (forceRefresh) System.currentTimeMillis() else null
                    )
                }.getOrNull()
                if (response != null && response.isSuccessful) {
                    val merged = parseLyricsFromEnvelope(response.body()?.string().orEmpty())
                    if (merged.isNotBlank()) {
                        lyricsCache.put(cacheKey, merged)
                        return@run Result.success(merged)
                    }
                }

                return@run Result.failure(Exception("获取歌词失败"))
            } catch (e: Exception) {
                Result.failure(e)
            }
          }
        }
    }

    suspend fun prepareSong(song: Song): Result<Song> = coroutineScope {
        try {
            val urlDeferred = async { getSongUrl(song.id, source = song.source) }
            val lyricsDeferred = async { getLyrics(song.id, source = song.source) }

            val urlResult = urlDeferred.await()
            if (urlResult.isFailure) {
                return@coroutineScope Result.failure(urlResult.exceptionOrNull() ?: Exception("获取歌曲播放地址失败"))
            }

            val preparedSong = song.copy(
                url = urlResult.getOrNull(),
                lyric = lyricsDeferred.await().getOrNull()
            )
            Result.success(preparedSong)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun searchArtists(keywords: String, limit: Int = 30): Result<List<com.music.player.data.model.SearchArtist>> =
        searchCatalog(keywords, type = "artist", limit = limit, parser = ::parseArtistsFromEnvelope)

    suspend fun searchPlaylists(keywords: String, limit: Int = 30): Result<List<Playlist>> =
        searchCatalog(keywords, type = "playlist", limit = limit, parser = ::parsePlaylistsFromSearchEnvelope)

    private suspend fun <T> searchCatalog(
        keywords: String,
        type: String,
        limit: Int,
        parser: (String, String) -> List<T>
    ): Result<List<T>> = withContext(Dispatchers.IO) {
        try {
            val response = api.searchSongs(
                source = activeSourceValue(),
                keyword = keywords,
                type = type,
                page = 1,
                pageSize = limit.coerceAtLeast(1)
            )
            if (response.isSuccessful) {
                Result.success(parser(response.body()?.string().orEmpty(), activeSourceValue()))
            } else {
                Result.failure(Exception("搜索${type}失败"))
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun checkSource(source: MusicSourcePreferences.Source): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val response = api.searchSongs(
                source = source.storageValue,
                keyword = "周杰伦",
                page = 1,
                pageSize = 1
            )
            if (!response.isSuccessful) throw Exception("HTTP ${response.code()}")
            val songs = parseSongsFromEnvelope(response.body()?.string().orEmpty())
            if (songs.isEmpty()) throw Exception("音源未返回可用歌曲")
            getSongUrl(
                id = songs.first().id,
                source = source.storageValue,
                forceRefresh = true
            ).getOrThrow()
            Unit
        }
    }

    private fun activeSourceValue(): String = MusicSourcePreferences.activeSource().storageValue

    private fun normalizeSource(source: String): String =
        MusicSourcePreferences.Source.entries
            .firstOrNull { it.storageValue == source }
            ?.storageValue
            ?: activeSourceValue()
}

private val WHITESPACE_REGEX = Regex("\\s+")

private fun SongData.toSong() = Song(
    id = id.toString(),
    name = name,
    artists = (artists ?: ar).orEmpty().map { Artist(it.id.toString(), it.name) },
    album = Album(
        id = al?.id?.toString().orEmpty(),
        name = al?.name.orEmpty(),
        picUrl = al?.picUrl.orEmpty()
    ),
    duration = dt
)

private fun com.music.player.data.api.PlaylistData.toPlaylist() = Playlist(
    id = id.toString(),
    name = name,
    coverImgUrl = coverImgUrl.orEmpty(),
    description = description.orEmpty(),
    trackCount = trackCount,
    playCount = playCount
)

private fun parseSongsFromEnvelope(raw: String): List<Song> {
    val data = parseEnvelopeData(raw) ?: return emptyList()
    val list = data.obj("list")?.takeIf { it.isJsonArray }
        ?: data.obj("songs")?.takeIf { it.isJsonArray }
        ?: return emptyList()
    return list.asJsonArray.mapNotNull { it.toWebsiteSong() }
}

private fun parsePlaylistsFromEnvelope(raw: String): List<Playlist> {
    val data = parseEnvelopeData(raw) ?: return emptyList()
    val list = data.obj("list")?.takeIf { it.isJsonArray } ?: return emptyList()
    return list.asJsonArray.mapNotNull { item ->
        val obj = item.asJsonObjectOrNull() ?: return@mapNotNull null
        val id = obj.str("id")
        val name = obj.str("name")
        if (id.isBlank() || name.isBlank()) return@mapNotNull null
        Playlist(
            id = id,
            name = name,
            coverImgUrl = obj.str("coverUrl"),
            description = obj.str("description"),
            trackCount = obj.int("trackCount"),
            playCount = obj.long("playCount"),
            source = obj.str("source").ifBlank { "netease" }
        )
    }
}

private fun AudioQualityPreferences.Level.toWebsiteQuality(): String {
    return when (this) {
        AudioQualityPreferences.Level.STANDARD -> "128k"
        AudioQualityPreferences.Level.EXHIGH -> "320k"
        AudioQualityPreferences.Level.LOSSLESS -> "flac"
        AudioQualityPreferences.Level.HIRES,
        AudioQualityPreferences.Level.JYMASTER,
        AudioQualityPreferences.Level.SKY,
        AudioQualityPreferences.Level.JYEFFECT -> "flac24bit"
    }
}

private fun parsePlaylistDetailFromEnvelope(
    raw: String,
    fallbackId: String,
    fallbackSource: String
): Pair<Playlist, List<Song>>? {
    val data = parseEnvelopeData(raw) ?: return null
    val playlist = Playlist(
        id = data.str("id").ifBlank { fallbackId },
        name = data.str("name").ifBlank { "歌单" },
        coverImgUrl = data.str("coverUrl"),
        description = data.str("description"),
        trackCount = data.int("total"),
        playCount = data.long("playCount"),
        source = data.str("source").ifBlank { fallbackSource }
    )
    return playlist to parseSongsFromData(data)
}

private fun parseSongsFromData(data: com.google.gson.JsonObject): List<Song> {
    val list = data.obj("list")?.takeIf { it.isJsonArray } ?: return emptyList()
    return list.asJsonArray.mapNotNull { it.toWebsiteSong() }
}

private fun parseLyricsFromEnvelope(raw: String): String {
    val data = parseEnvelopeData(raw) ?: return ""
    val primary = data.str("lineLyrics")
        .ifBlank { data.str("lyric") }
        .ifBlank { data.obj("lrc")?.asJsonObjectOrNull()?.str("lyric").orEmpty() }
    val translated = data.str("karaokeLyrics")
        .ifBlank { data.str("tlyric") }
        .ifBlank { data.obj("tlyric")?.asJsonObjectOrNull()?.str("lyric").orEmpty() }
    return mergeLyrics(primary, translated)
}

private fun parseEnvelopeData(raw: String): com.google.gson.JsonObject? {
    if (raw.isBlank()) return null
    val root = runCatching { JsonParser.parseString(raw).asJsonObject }.getOrNull() ?: return null
    if (root.int("code", default = -1) != 0) return null
    return root.obj("data")?.asJsonObjectOrNull()
}

private fun JsonElement.toWebsiteSong(): Song? {
    val root = asJsonObjectOrNull() ?: return null
    val obj = root.obj("song")?.asJsonObjectOrNull() ?: root
    val id = obj.str("id").ifBlank { root.str("id") }
    val name = obj.str("name").ifBlank { root.str("name") }
    if (id.isBlank() || name.isBlank()) return null
    val artistArray = obj.obj("artists")?.takeIf { it.isJsonArray }
        ?: obj.obj("ar")?.takeIf { it.isJsonArray }
        ?: root.obj("artists")?.takeIf { it.isJsonArray }
        ?: root.obj("ar")?.takeIf { it.isJsonArray }
    val artistName = obj.str("artist").ifBlank { root.str("artist") }
    val artists = artistArray
        ?.asJsonArray
        ?.mapNotNull { artistElement ->
            val artistObj = artistElement.asJsonObjectOrNull() ?: return@mapNotNull null
            val artistDisplayName = artistObj.str("name")
            if (artistDisplayName.isBlank()) return@mapNotNull null
            Artist(artistObj.str("id"), artistDisplayName)
        }
        ?.ifEmpty { null }
        ?: artistName.split(",", " / ")
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .ifEmpty { listOf("未知歌手") }
            .map { Artist("", it) }
    val albumObj = obj.obj("album")?.asJsonObjectOrNull()
        ?: obj.obj("al")?.asJsonObjectOrNull()
        ?: root.obj("album")?.asJsonObjectOrNull()
        ?: root.obj("al")?.asJsonObjectOrNull()
    return Song(
        id = id,
        name = name,
        artists = artists,
        album = Album(
            id = obj.str("albumId")
                .ifBlank { root.str("albumId") }
                .ifBlank { albumObj?.str("id").orEmpty() },
            name = obj.str("album")
                .ifBlank { root.str("album") }
                .ifBlank { albumObj?.str("name").orEmpty() },
            picUrl = obj.str("coverUrl")
                .ifBlank { obj.str("picUrl") }
                .ifBlank { root.str("coverUrl") }
                .ifBlank { root.str("picUrl") }
                .ifBlank { albumObj?.str("picUrl").orEmpty() }
                .ifBlank { albumObj?.str("coverUrl").orEmpty() }
        ),
        duration = obj.long("durationMs").takeIf { it > 0 }
            ?: root.long("durationMs").takeIf { it > 0 }
            ?: (obj.long("durationSec").takeIf { it > 0 } ?: root.long("durationSec")) * 1000L,
        source = obj.str("source").ifBlank { "netease" }
    )
}

private fun parseBackendSongUrl(raw: String): String? {
    extractDirectUrl(raw)?.let { return it }

    val json = extractJsonPayload(raw) ?: return null
    val element = runCatching { JsonParser.parseString(json) }.getOrNull() ?: return null
    return extractUrlFromElement(element)
}

private fun extractDirectUrl(raw: String): String? {
    val normalized = raw.trim().trim('"', '\'')
    if (normalized.isEmpty()) return null

    return normalized
        .lineSequence()
        .map { it.trim() }
        .firstNotNullOfOrNull(::sanitizeHttpUrl)
}

private fun extractUrlFromElement(element: JsonElement?, depth: Int = 0): String? {
    if (element == null || element.isJsonNull || depth > 6) return null

    if (element.isJsonPrimitive) {
        return runCatching { element.asString }
            .getOrNull()
            ?.let(::sanitizeHttpUrl)
    }

    if (element.isJsonArray) {
        element.asJsonArray.forEach { child ->
            extractUrlFromElement(child, depth + 1)?.let { return it }
        }
        return null
    }

    if (!element.isJsonObject) return null

    val root = element.asJsonObject
    listOf("playUrl", "url", "data", "result", "song", "songs", "list").forEach { key ->
        extractUrlFromElement(root.get(key), depth + 1)?.let { return it }
    }

    root.entrySet().forEach { (_, value) ->
        extractUrlFromElement(value, depth + 1)?.let { return it }
    }

    return null
}

private fun sanitizeHttpUrl(candidate: String?): String? {
    val value = candidate
        ?.trim()
        ?.trim('"', '\'')
        ?.replace("\\/", "/")
        ?.trimEnd(',', ';')
        ?: return null

    return value.takeIf { it.startsWith("http://") || it.startsWith("https://") }
}

private fun extractJsonPayload(raw: String): String? {
    val trimmed = raw.trim()
    if (trimmed.isEmpty()) return null
    if (trimmed.startsWith("{") || trimmed.startsWith("[")) return trimmed

    val left = trimmed.indexOf('(')
    val right = trimmed.lastIndexOf(')')
    if (left < 0 || right <= left) return null

    val candidate = trimmed.substring(left + 1, right).trim().trimEnd(';').trim()
    return candidate.takeIf { it.startsWith("{") || it.startsWith("[") }
}

private fun mergeLyrics(lrc: String, tlyric: String): String {
    val primary = sanitizeLyricText(repairPotentialMojibake(lrc).trim())
    val translated = sanitizeLyricText(repairPotentialMojibake(tlyric).trim())

    if (primary.isNotBlank() && translated.isNotBlank() && primary != translated) {
        return "$primary\n\n$translated"
    }

    return primary.ifBlank { translated }
}

private fun sanitizeLyricText(value: String): String {
    return value
        .replace("\uFEFF", "")
        .replace("\r\n", "\n")
        .replace("\r", "\n")
        .lineSequence()
        .map { it.trimEnd() }
        .filterNot { line ->
            line.isBlank() ||
                line.equals("null", ignoreCase = true) ||
                line.equals("undefined", ignoreCase = true)
        }
        .joinToString("\n")
        .trim()
}

private fun repairPotentialMojibake(value: String): String {
    if (value.isBlank()) return value
    val normalized = value.trim()
    if (!looksLikeMojibake(normalized)) return normalized

    val latin1Fixed = runCatching {
        String(normalized.toByteArray(StandardCharsets.ISO_8859_1), StandardCharsets.UTF_8)
    }.getOrNull()
    val win1252Fixed = runCatching {
        String(normalized.toByteArray(Charsets.UTF_8), Charsets.UTF_8)
    }.getOrNull()

    return sequenceOf(normalized, latin1Fixed, win1252Fixed)
        .filterNotNull()
        .maxByOrNull(::readabilityScore)
        .orEmpty()
}

private fun looksLikeMojibake(value: String): Boolean {
    return value.contains("Ã") ||
        value.contains("â") ||
        value.contains("æ") ||
        value.contains("å") ||
        value.contains("ä") ||
        value.contains("ï")
}

private fun readabilityScore(value: String): Int {
    var score = 0
    value.forEach { ch ->
        when {
            ch in '\u4E00'..'\u9FFF' -> score += 3
            ch.isLetterOrDigit() -> score += 1
        }
        if (ch == 'Ã' || ch == 'â' || ch == '�') {
            score -= 3
        }
    }
    return score
}

private fun JsonElement.asJsonObjectOrNull(): com.google.gson.JsonObject? =
    takeIf { it.isJsonObject }?.asJsonObject

private fun com.google.gson.JsonObject.obj(name: String): JsonElement? =
    get(name)?.takeUnless { it.isJsonNull }

private fun com.google.gson.JsonObject.str(name: String): String =
    obj(name)?.let { runCatching { it.asString }.getOrNull() }.orEmpty().decodeHtmlEntities().trim()

private fun String.decodeHtmlEntities(): String {
    if (indexOf('&') < 0) return this
    return replace("&nbsp;", " ")
        .replace("&#160;", " ")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&#39;", "'")
        .replace(Regex("&#(\\d+);")) { match ->
            match.groupValues[1].toIntOrNull()?.let { codePoint ->
                runCatching { String(Character.toChars(codePoint)) }.getOrNull()
            } ?: match.value
        }
        .replace(Regex("&#x([0-9a-fA-F]+);")) { match ->
            match.groupValues[1].toIntOrNull(16)?.let { codePoint ->
                runCatching { String(Character.toChars(codePoint)) }.getOrNull()
            } ?: match.value
        }
}

internal fun parsePlaylistsFromSearchEnvelope(raw: String, fallbackSource: String): List<Playlist> {
    val data = parseEnvelopeData(raw) ?: return emptyList()
    val list = data.obj("playlists")?.takeIf { it.isJsonArray && it.asJsonArray.size() > 0 }
        ?: data.obj("list")?.takeIf { it.isJsonArray }
        ?: return emptyList()
    return list.asJsonArray.mapNotNull { item ->
        val obj = item.asJsonObjectOrNull() ?: return@mapNotNull null
        val id = obj.str("id")
        val name = obj.str("name")
        if (id.isBlank() || name.isBlank()) return@mapNotNull null
        Playlist(
            id = id,
            name = name,
            coverImgUrl = obj.str("coverUrl").ifBlank { obj.str("picUrl") }.ifBlank { obj.str("coverImgUrl") },
            description = obj.str("description"),
            trackCount = obj.int("trackCount").takeIf { it > 0 } ?: obj.int("trackNumber"),
            playCount = obj.long("playCount"),
            source = obj.str("source").ifBlank { fallbackSource }
        )
    }
}

internal fun parseArtistsFromEnvelope(raw: String, fallbackSource: String): List<com.music.player.data.model.SearchArtist> {
    val data = parseEnvelopeData(raw) ?: return emptyList()
    val list = data.obj("artists")?.takeIf { it.isJsonArray && it.asJsonArray.size() > 0 }
        ?: data.obj("list")?.takeIf { it.isJsonArray }
        ?: return emptyList()
    return list.asJsonArray.mapNotNull { item ->
        val obj = item.asJsonObjectOrNull() ?: return@mapNotNull null
        val id = obj.str("id")
        val name = obj.str("name")
        if (id.isBlank() || name.isBlank()) return@mapNotNull null
        com.music.player.data.model.SearchArtist(
            id = id,
            name = name,
            avatarUrl = obj.str("avatarUrl").ifBlank { obj.str("picUrl") }.ifBlank { obj.str("coverUrl") },
            songCount = obj.int("songCount").takeIf { it > 0 }
                ?: obj.int("musicSize").takeIf { it > 0 }
                ?: obj.int("trackCount"),
            source = obj.str("source").ifBlank { fallbackSource }
        )
    }
}

private fun com.google.gson.JsonObject.int(name: String, default: Int = 0): Int =
    obj(name)?.let { runCatching { it.asInt }.getOrNull() } ?: default

private fun com.google.gson.JsonObject.long(name: String, default: Long = 0L): Long =
    obj(name)?.let { runCatching { it.asLong }.getOrNull() } ?: default
