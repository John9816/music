package com.music.player.data.repository

import com.music.player.data.api.RetrofitClient
import com.music.player.data.api.SongData
import com.google.gson.JsonParser
import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.Playlist
import com.music.player.data.model.PlaylistCategory
import com.music.player.data.model.PlaylistCategoryCatalog
import com.music.player.data.model.PlaylistCategoryGroup
import com.music.player.data.model.Song
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.withContext

class MusicRepository {

    private val api = RetrofitClient.musicApi
    private val gdStudioApi = RetrofitClient.gdStudioApi
    private val lyricsApi = RetrofitClient.lyricsApi

    private companion object {
        private const val GDSTUDIO_BITRATE = 320
    }

    suspend fun getDailyRecommend(): Result<List<Song>> {
        val direct = runCatching { api.getDailyRecommend() }
        if (direct.isSuccess) {
            val response = direct.getOrThrow()
            if (response.isSuccessful && response.body()?.code == 200) {
                val songs = response.body()?.data?.dailySongs?.map { it.toSong() }.orEmpty()
                if (songs.isNotEmpty()) {
                    return Result.success(songs)
                }
            }
        }

        return try {
            val response = api.getTopLists()
            if (!response.isSuccessful || response.body()?.code != 200) {                return Result.failure(Exception("获取歌单详情失败"))            }

            val firstPlaylistId = response.body()
                ?.list
                ?.firstOrNull { it.trackCount > 0 }
                ?.id
                ?.toString()
                ?: return Result.failure(Exception("姣忔棩鎺ㄨ崘姝屽崟涓虹┖"))

            getPlaylistDetail(firstPlaylistId).map { it.second }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getTopLists(): Result<List<Playlist>> {
        return try {
            val response = api.getTopLists()
            if (response.isSuccessful && response.body()?.code == 200) {
                val playlists = response.body()?.list?.map { it.toPlaylist() } ?: emptyList()
                Result.success(playlists)
            } else {
                Result.failure(Exception("搜索歌曲失败"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getTopPlaylists(
        category: String? = "",
        limit: Int = 42,
        offset: Int = 0,
        device: String = "mobile"
    ): Result<List<Playlist>> {
        return try {
            val response = api.getTopPlaylists(
                category = category,
                limit = limit,
                offset = offset,
                timestamp = System.currentTimeMillis(),
                device = device
            )
            if (response.isSuccessful && response.body()?.code == 200) {
                val playlists = response.body()?.playlists?.map { it.toPlaylist() } ?: emptyList()
                Result.success(playlists)
            } else {
                Result.failure(Exception("搜索歌曲失败"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getPlaylistCategories(device: String = "mobile"): Result<PlaylistCategoryCatalog> {
        return try {
            val response = api.getPlaylistCatlist(
                timestamp = System.currentTimeMillis(),
                device = device
            )

            if (!response.isSuccessful || response.body()?.code != 200) {                return Result.failure(Exception("获取歌单详情失败"))            }

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

            Result.success(
                PlaylistCategoryCatalog(
                    groups = groups,
                    categories = sorted
                )
            )
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getWeeklyHotNewSongs(limit: Int = 10, device: String = "mobile"): Result<List<Song>> {
        return try {
            val response = api.getWeeklyHotNewSongs(
                limit = limit,
                timestamp = System.currentTimeMillis(),
                device = device
            )
            if (!response.isSuccessful || response.body()?.code != 200) {                return Result.failure(Exception("获取歌单详情失败"))            }

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

            Result.success(songs)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getPlaylistDetail(id: String): Result<Pair<Playlist, List<Song>>> {
        return try {
            val response = api.getPlaylistDetail(id)
            if (!response.isSuccessful || response.body()?.code != 200) {                return Result.failure(Exception("获取歌单详情失败"))           }
            val data = response.body()?.playlist ?: return Result.failure(Exception("歌单数据为空"))
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
                return Result.success(playlist to directSongs)
            }

            val trackIds = data.trackIds?.map { it.id.toString() }.orEmpty()
            if (trackIds.isEmpty()) {
                return Result.success(playlist to emptyList())
            }

            val songs = trackIds.chunked(500).flatMap { ids ->
                val detailResponse = api.getSongDetail(ids.joinToString(","))
                if (detailResponse.isSuccessful && detailResponse.body()?.code == 200) {
                    detailResponse.body()?.songs?.map { it.toSong() }.orEmpty()
                } else {
                    emptyList()
                }
            }

            Result.success(playlist to songs)
        } catch (e: Exception) {
            Result.failure(e)
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
        return try {
            val response = gdStudioApi.getSongUrl(id = id, bitRate = GDSTUDIO_BITRATE)
            val raw = response.body()?.string() ?: response.errorBody()?.string() ?: ""
            val url = parseGdStudioUrl(raw)
            if (response.isSuccessful && !url.isNullOrBlank()) return Result.success(url)

            val code = response.code()
            val snippet = raw.trim().replace(Regex("\\s+"), " ").take(160)
            val fallback = snippet.ifBlank { "empty response" }
            val message = "getSongUrl failed (HTTP $code): $fallback"
            Result.failure(Exception(message))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getLyrics(id: String): Result<String> {
        return try {
            val timestamp = System.currentTimeMillis()

            val alger = runCatching { api.getLyric(id = id, timestamp = timestamp) }.getOrNull()
            if (alger != null && alger.isSuccessful) {
                val body = alger.body()
                if (body?.code == 200) {
                    val lrc = body.lrc?.lyric.orEmpty().trim()
                    val tlyric = body.tlyric?.lyric.orEmpty().trim()
                    val merged = mergeLyrics(lrc, tlyric)
                    if (merged.isNotBlank()) {
                        return Result.success(merged)
                    }
                }
            }

            val fallback = lyricsApi.getLyrics(id)
            val lyric = fallback.body()?.data?.lyric.orEmpty()
            if (fallback.isSuccessful && fallback.body()?.code == 200) {
                Result.success(lyric)
            } else {
                Result.failure(Exception("搜索歌曲失败"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun prepareSong(song: Song): Result<Song> = coroutineScope {
        try {
            val urlDeferred = async { getSongUrl(song.id) }
            val lyricsDeferred = async { getLyrics(song.id) }

            val urlResult = urlDeferred.await()
            if (urlResult.isFailure) {
                return@coroutineScope Result.failure(urlResult.exceptionOrNull() ?: Exception("鑾峰彇鎾斁鍦板潃澶辫触"))
            }

            val preparedSong = song.copy(url = urlResult.getOrNull(), lyric = lyricsDeferred.await().getOrNull())
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
    val json = extractJsonPayload(raw) ?: return null
    val element = runCatching { JsonParser.parseString(json) }.getOrNull() ?: return null
    if (!element.isJsonObject) return null

    val root = element.asJsonObject
    val direct = root.get("url")?.takeIf { !it.isJsonNull }?.asString?.trim()
    if (!direct.isNullOrBlank()) return direct

    val dataObj = root.get("data")?.takeIf { it.isJsonObject }?.asJsonObject
    val nested = dataObj?.get("url")?.takeIf { !it.isJsonNull }?.asString?.trim()
    return nested?.takeIf { it.isNotBlank() }
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
