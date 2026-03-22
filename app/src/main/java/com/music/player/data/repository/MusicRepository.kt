package com.music.player.data.repository

import com.google.gson.JsonElement
import com.google.gson.JsonParser
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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

class MusicRepository {

    private val api = RetrofitClient.musicApi
    private val gdStudioApi = RetrofitClient.gdStudioApi
    private val chkSzApi = RetrofitClient.chkSzApi
    private val lyricsApi = RetrofitClient.lyricsApi

    private companion object {
        private const val GDSTUDIO_BITRATE_FAST = 128
        private const val GDSTUDIO_BITRATE_FALLBACK = 320
        private const val DISCOVER_TTL_MS = 3 * 60 * 1000L
        private const val PLAYLIST_TTL_MS = 10 * 60 * 1000L
        private const val CATEGORY_TTL_MS = 30 * 60 * 1000L
        private const val LYRICS_TTL_MS = 24 * 60 * 60 * 1000L
        private const val URL_TTL_MS = 20 * 60 * 1000L

        private val dailyRecommendCache = TimedMemoryCache<String, List<Song>>()
        private val topListsCache = TimedMemoryCache<String, List<Playlist>>()
        private val topPlaylistsCache = TimedMemoryCache<String, List<Playlist>>()
        private val playlistCategoryCache = TimedMemoryCache<String, PlaylistCategoryCatalog>()
        private val weeklyHotCache = TimedMemoryCache<String, List<Song>>()
        private val playlistDetailCache = TimedMemoryCache<String, Pair<Playlist, List<Song>>>()
        private val lyricsCache = TimedMemoryCache<String, String>()
        private val songUrlCache = TimedMemoryCache<String, String>()

        private val songListRequests = RequestCoalescer<String, Result<List<Song>>>()
        private val playlistListRequests = RequestCoalescer<String, Result<List<Playlist>>>()
        private val categoryRequests = RequestCoalescer<String, Result<PlaylistCategoryCatalog>>()
        private val playlistDetailRequests = RequestCoalescer<String, Result<Pair<Playlist, List<Song>>>>()
        private val stringRequests = RequestCoalescer<String, Result<String>>()
    }

    suspend fun getDailyRecommend(): Result<List<Song>> {
        return getDailyRecommend(forceRefresh = false)
    }

    suspend fun getDailyRecommend(forceRefresh: Boolean): Result<List<Song>> {
        val cacheKey = "daily_recommend"

        if (!forceRefresh) {
            dailyRecommendCache.get(cacheKey, DISCOVER_TTL_MS)?.let { return Result.success(it) }
        }

        return songListRequests.run(cacheKey) {
            if (!forceRefresh) {
                dailyRecommendCache.get(cacheKey, DISCOVER_TTL_MS)?.let { return@run Result.success(it) }
            }

            val direct = runCatching { api.getDailyRecommend() }
            if (direct.isSuccess) {
                val response = direct.getOrThrow()
                if (response.isSuccessful && response.body()?.code == 200) {
                    val songs = response.body()?.data?.dailySongs?.map { it.toSong() }.orEmpty()
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

    suspend fun getTopLists(): Result<List<Playlist>> {
        return getTopLists(forceRefresh = false)
    }

    suspend fun getTopLists(forceRefresh: Boolean): Result<List<Playlist>> {
        val cacheKey = "top_lists"
        if (!forceRefresh) {
            topListsCache.get(cacheKey, PLAYLIST_TTL_MS)?.let { return Result.success(it) }
        }

        return playlistListRequests.run(cacheKey) {
            if (!forceRefresh) {
                topListsCache.get(cacheKey, PLAYLIST_TTL_MS)?.let { return@run Result.success(it) }
            }

            try {
                val response = api.getTopLists()
                if (response.isSuccessful && response.body()?.code == 200) {
                    val playlists = response.body()?.list?.map { it.toPlaylist() } ?: emptyList()
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
        val cacheKey = "top_playlists|$normalizedCategory|$limit|$offset|$device"
        if (!forceRefresh) {
            topPlaylistsCache.get(cacheKey, PLAYLIST_TTL_MS)?.let { return Result.success(it) }
        }

        return playlistListRequests.run(cacheKey) {
            if (!forceRefresh) {
                topPlaylistsCache.get(cacheKey, PLAYLIST_TTL_MS)?.let { return@run Result.success(it) }
            }

            try {
                val response = api.getTopPlaylists(
                    category = normalizedCategory.ifBlank { null },
                    limit = limit,
                    offset = offset,
                    timestamp = if (forceRefresh) System.currentTimeMillis() else null,
                    device = device
                )
                if (response.isSuccessful && response.body()?.code == 200) {
                    val playlists = response.body()?.playlists?.map { it.toPlaylist() } ?: emptyList()
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

    suspend fun getPlaylistCategories(
        device: String = "mobile"
    ): Result<PlaylistCategoryCatalog> {
        return getPlaylistCategories(device = device, forceRefresh = false)
    }

    suspend fun getPlaylistCategories(
        device: String,
        forceRefresh: Boolean
    ): Result<PlaylistCategoryCatalog> {
        val cacheKey = "playlist_categories|$device"
        if (!forceRefresh) {
            playlistCategoryCache.get(cacheKey, CATEGORY_TTL_MS)?.let { return Result.success(it) }
        }

        return categoryRequests.run(cacheKey) {
            if (!forceRefresh) {
                playlistCategoryCache.get(cacheKey, CATEGORY_TTL_MS)?.let { return@run Result.success(it) }
            }

            try {
                val response = api.getPlaylistCatlist(
                    timestamp = if (forceRefresh) System.currentTimeMillis() else null,
                    device = device
                )

                if (!response.isSuccessful || response.body()?.code != 200) {
                    return@run Result.failure(Exception("获取歌单分类失败"))
                }

                val body = response.body()
                val groupNames = body?.categories.orEmpty()
                val subCategories = body?.sub.orEmpty()

                val groups = groupNames
                    .mapNotNull { (id, name) ->
                        val gid = id.toIntOrNull() ?: return@mapNotNull null
                        PlaylistCategoryGroup(id = gid, name = name.trim())
                    }
                    .sortedBy { it.id }

                val items = subCategories.mapNotNull { entry ->
                    val name = entry.name?.trim().orEmpty()
                    if (name.isBlank()) return@mapNotNull null

                    val groupId = entry.category
                    val groupName = groupId?.let { id -> groupNames[id.toString()] }?.trim().orEmpty()
                    PlaylistCategory(
                        apiName = name,
                        name = name,
                        groupId = groupId,
                        groupName = groupName.ifBlank { null },
                        hot = entry.hot == true
                    )
                }

                val sorted = items
                    .distinctBy { it.apiName }
                    .sortedWith(
                        compareBy<PlaylistCategory> { it.groupId ?: Int.MAX_VALUE }
                            .thenByDescending { it.hot }
                            .thenBy { it.name }
                    )

                val catalog = PlaylistCategoryCatalog(
                    groups = groups,
                    categories = sorted
                )
                playlistCategoryCache.put(cacheKey, catalog)
                Result.success(catalog)
            } catch (e: Exception) {
                Result.failure(e)
            }
        }
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
        val cacheKey = "weekly_hot|$limit|$device"
        if (!forceRefresh) {
            weeklyHotCache.get(cacheKey, DISCOVER_TTL_MS)?.let { return Result.success(it) }
        }

        return songListRequests.run(cacheKey) {
            if (!forceRefresh) {
                weeklyHotCache.get(cacheKey, DISCOVER_TTL_MS)?.let { return@run Result.success(it) }
            }

            try {
                val response = api.getWeeklyHotNewSongs(
                    limit = limit,
                    timestamp = if (forceRefresh) System.currentTimeMillis() else null,
                    device = device
                )
                if (!response.isSuccessful || response.body()?.code != 200) {
                    return@run Result.failure(Exception("获取本周热门失败"))
                }

                val songs = response.body()
                    ?.result
                    .orEmpty()
                    .mapNotNull { item ->
                        val data = item.song ?: return@mapNotNull null
                        val song = data.toSong()
                        val fallbackCover = item.picUrl?.trim().orEmpty()
                        if (song.album.picUrl.isBlank() && fallbackCover.isNotBlank()) {
                            song.copy(album = song.album.copy(picUrl = fallbackCover))
                        } else {
                            song
                        }
                    }

                weeklyHotCache.put(cacheKey, songs)
                Result.success(songs)
            } catch (e: Exception) {
                Result.failure(e)
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

        if (!forceRefresh) {
            playlistDetailCache.get(normalizedId, PLAYLIST_TTL_MS)?.let { return Result.success(it) }
        }

        return playlistDetailRequests.run(normalizedId) {
            if (!forceRefresh) {
                playlistDetailCache.get(normalizedId, PLAYLIST_TTL_MS)?.let { return@run Result.success(it) }
            }

            try {
                val response = api.getPlaylistDetail(normalizedId)
                if (!response.isSuccessful || response.body()?.code != 200) {
                    return@run Result.failure(Exception("获取歌单详情失败"))
                }

                val data = response.body()?.playlist ?: return@run Result.failure(Exception("歌单数据为空"))
                val playlist = Playlist(
                    id = data.id.toString(),
                    name = data.name,
                    coverImgUrl = data.coverImgUrl.orEmpty(),
                    description = data.description.orEmpty(),
                    trackCount = data.trackCount,
                    playCount = data.playCount
                )

                val directSongs = data.tracks?.map { it.toSong() }.orEmpty()
                if (directSongs.isNotEmpty()) {
                    return@run Result.success((playlist to directSongs).also {
                        playlistDetailCache.put(normalizedId, it)
                    })
                }

                val trackIds = data.trackIds?.map { it.id.toString() }.orEmpty()
                if (trackIds.isEmpty()) {
                    return@run Result.success((playlist to emptyList<Song>()).also {
                        playlistDetailCache.put(normalizedId, it)
                    })
                }

                val songs = trackIds.chunked(500).flatMap { ids ->
                    val detailResponse = api.getSongDetail(ids.joinToString(","))
                    if (detailResponse.isSuccessful && detailResponse.body()?.code == 200) {
                        detailResponse.body()?.songs?.map { it.toSong() }.orEmpty()
                    } else {
                        emptyList()
                    }
                }

                Result.success((playlist to songs).also {
                    playlistDetailCache.put(normalizedId, it)
                })
            } catch (e: Exception) {
                Result.failure(e)
            }
        }
    }

    suspend fun searchSongs(keywords: String, limit: Int = 30, offset: Int = 0): Result<List<Song>> {
        return try {
            val response = api.searchSongs(keywords = keywords, limit = limit, offset = offset)
            if (response.isSuccessful && response.body()?.code == 200) {
                val songs = response.body()?.result?.songs?.map { it.toSong() } ?: emptyList()
                Result.success(songs)
            } else {
                Result.failure(Exception("搜索歌曲失败"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getSongUrl(id: String): Result<String> {
        return getSongUrl(id, forceRefresh = false)
    }

    suspend fun getSongUrl(id: String, forceRefresh: Boolean): Result<String> {
        val normalizedId = id.trim()
        if (normalizedId.isBlank()) {
            return Result.failure(IllegalArgumentException("歌曲 ID 为空"))
        }

        val preferredLevel = AudioQualityPreferences.getPreferredLevel()
        val cacheKey = "$normalizedId|${preferredLevel.storageValue}"
        val requestKey = "song_url|$cacheKey"
        val orderedLevels = AudioQualityPreferences.orderedLevels(preferredLevel)

        if (!forceRefresh) {
            songUrlCache.get(cacheKey, URL_TTL_MS)?.let { return Result.success(it) }
        }

        return stringRequests.run(requestKey) {
            if (!forceRefresh) {
                songUrlCache.get(cacheKey, URL_TTL_MS)?.let { return@run Result.success(it) }
            }

            try {
                var lastFailure: Exception? = null

                for (level in orderedLevels) {
                    val response = chkSzApi.getSongUrl(id = normalizedId, level = level.storageValue)
                    val body = response.body()
                    val url = sanitizeHttpUrl(body?.data?.url)
                    if (response.isSuccessful && body?.code == 200 && !url.isNullOrBlank()) {
                        songUrlCache.put(cacheKey, url)
                        return@run Result.success(url)
                    }

                    val code = response.code()
                    val msg = body?.msg?.trim().orEmpty()
                    val detail = listOf(
                        "level=${level.storageValue}",
                        "HTTP $code",
                        msg.takeIf { it.isNotBlank() }?.let { "msg=$it" },
                        body?.code?.let { "code=$it" }
                    ).filterNotNull().joinToString(", ")
                    lastFailure = Exception("chkSz primary failed ($detail)")
                }

                val bitrates = listOf(GDSTUDIO_BITRATE_FAST, GDSTUDIO_BITRATE_FALLBACK).distinct()
                for (bitrate in bitrates) {
                    val response = gdStudioApi.getSongUrl(id = normalizedId, bitRate = bitrate)
                    val raw = response.body()?.string() ?: response.errorBody()?.string() ?: ""
                    val url = parseGdStudioUrl(raw)
                    if (response.isSuccessful && !url.isNullOrBlank()) {
                        songUrlCache.put(cacheKey, url)
                        return@run Result.success(url)
                    }

                    val code = response.code()
                    val snippet = raw.trim().replace(Regex("\\s+"), " ").take(160)
                    val detail = snippet.ifBlank { "empty response" }
                    lastFailure = Exception("gdstudio fallback failed (bitrate=$bitrate, HTTP $code): $detail")
                }

                Result.failure(lastFailure ?: Exception("getSongUrl failed"))
            } catch (e: Exception) {
                Result.failure(e)
            }
        }
    }

    suspend fun getLyrics(id: String): Result<String> {
        return getLyrics(id, forceRefresh = false)
    }

    suspend fun getLyrics(id: String, forceRefresh: Boolean): Result<String> {
        val normalizedId = id.trim()
        if (normalizedId.isBlank()) {
            return Result.failure(IllegalArgumentException("歌曲 ID 为空"))
        }

        if (!forceRefresh) {
            lyricsCache.get(normalizedId, LYRICS_TTL_MS)?.let { return Result.success(it) }
        }

        return stringRequests.run("lyrics|$normalizedId") {
            if (!forceRefresh) {
                lyricsCache.get(normalizedId, LYRICS_TTL_MS)?.let { return@run Result.success(it) }
            }

            try {
                val alger = runCatching {
                    api.getLyric(
                        id = normalizedId,
                        timestamp = if (forceRefresh) System.currentTimeMillis() else null
                    )
                }.getOrNull()
                if (alger != null && alger.isSuccessful) {
                    val body = alger.body()
                    if (body?.code == 200) {
                        val lrc = body.lrc?.lyric.orEmpty().trim()
                        val tlyric = body.tlyric?.lyric.orEmpty().trim()
                        val merged = mergeLyrics(lrc, tlyric)
                        if (merged.isNotBlank()) {
                            lyricsCache.put(normalizedId, merged)
                            return@run Result.success(merged)
                        }
                    }
                }

                val fallback = lyricsApi.getLyrics(normalizedId)
                val lyric = fallback.body()?.data?.lyric.orEmpty().trim()
                if (fallback.isSuccessful && fallback.body()?.code == 200 && lyric.isNotBlank()) {
                    lyricsCache.put(normalizedId, lyric)
                    Result.success(lyric)
                } else {
                    Result.failure(Exception("获取歌词失败"))
                }
            } catch (e: Exception) {
                Result.failure(e)
            }
        }
    }

    suspend fun prepareSong(song: Song): Result<Song> = coroutineScope {
        try {
            val urlDeferred = async { getSongUrl(song.id) }
            val lyricsDeferred = async { getLyrics(song.id) }

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
}

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

private fun parseGdStudioUrl(raw: String): String? {
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
    listOf("url", "data", "result", "song", "songs", "list").forEach { key ->
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
    val primary = lrc.trim()
    val translated = tlyric.trim()

    if (primary.isNotBlank() && translated.isNotBlank() && primary != translated) {
        return "$primary\n\n$translated"
    }

    return primary.ifBlank { translated }
}
