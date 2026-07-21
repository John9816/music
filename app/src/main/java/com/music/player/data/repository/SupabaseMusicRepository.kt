package com.music.player.data.repository

import android.content.Context
import com.music.player.data.auth.AuthSessionManager
import com.music.player.data.auth.TokenRefreshResult
import com.music.player.data.auth.MusicFavoriteRequest
import com.music.player.data.auth.PlaylistCreateRequest
import com.music.player.data.auth.PlaylistImportRequest
import com.music.player.data.auth.PlaylistItemRequest
import com.music.player.data.auth.SupabaseClient
import com.music.player.data.common.RequestCoalescer
import com.music.player.data.common.TimedMemoryCache
import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.Song
import com.music.player.data.model.UserPlaylist
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.withContext
import okhttp3.ResponseBody
import org.json.JSONArray
import org.json.JSONObject
import retrofit2.Response

data class MusicLibraryBootstrap(
    val favorites: List<Song>,
    val history: List<Song>,
    val playlists: List<UserPlaylist>
)

class SupabaseMusicRepository(context: Context) {

    private val sessionManager = AuthSessionManager(context.applicationContext)
    private val authApi = SupabaseClient.authApi
    private val api = SupabaseClient.musicApi

    private companion object {
        private const val FAVORITES_TTL_MS = 30 * 1000L
        private const val HISTORY_TTL_MS = 20 * 1000L
        private const val PLAYLISTS_TTL_MS = 30 * 1000L
        private const val PLAYLIST_SONGS_TTL_MS = 30 * 1000L

        private val favoritesCache = TimedMemoryCache<String, List<Song>>()
        private val historyCache = TimedMemoryCache<String, List<Song>>()
        private val playlistsCache = TimedMemoryCache<String, List<UserPlaylist>>()
        private val playlistSongsCache = TimedMemoryCache<String, List<Song>>()

        private val favoriteRequests = RequestCoalescer<String, Result<List<Song>>>()
        private val historyRequests = RequestCoalescer<String, Result<List<Song>>>()
        private val playlistRequests = RequestCoalescer<String, Result<List<UserPlaylist>>>()
        private val playlistSongsRequests = RequestCoalescer<String, Result<List<Song>>>()
        private val bootstrapRequests = RequestCoalescer<String, Result<MusicLibraryBootstrap>>()

        private val historyRecordIds = mutableMapOf<String, Map<String, Long>>()
        private val playlistItemIds = mutableMapOf<String, Map<String, Long>>()
    }

    private suspend fun requireSession(): Pair<String, String> {
        val hadStoredSession = sessionManager.isLoggedIn()
        var token = sessionManager.getValidAccessToken(authApi) ?: run {
            if (!hadStoredSession) sessionManager.invalidateSession()
            throw IllegalStateException("Not signed in")
        }
        sessionManager.syncUserIdFromAccessToken(token)?.let { return token to it }

        var response = authApi.getUser("Bearer $token")
        if (response.code() == 401) {
            when (val refresh = sessionManager.forceRefresh(authApi)) {
                is TokenRefreshResult.Success -> {
                    token = refresh.accessToken
                    sessionManager.syncUserIdFromAccessToken(token)?.let { return token to it }
                    response = authApi.getUser("Bearer $token")
                    if (response.code() == 401) sessionManager.invalidateSession()
                }
                TokenRefreshResult.InvalidSession -> Unit
                TokenRefreshResult.MissingRefreshToken -> sessionManager.invalidateSession()
                TokenRefreshResult.TransientFailure -> Unit
            }
        }

        val userId = parseUserId(response.body()?.string().orEmpty()) ?: throw IllegalStateException("Failed to load user info")
        sessionManager.cacheUserId(userId)
        return token to userId
    }

    /**
     * 获取会话，失败时转为 [Result.failure] 而非抛出，避免异常绕过 Result 包装直接崩溃。
     * 协程取消（[CancellationException]）必须原样传播，不能吞掉。
     */
    private suspend fun sessionOrFailure(): Result<Pair<String, String>> {
        return try {
            Result.success(requireSession())
        } catch (ce: CancellationException) {
            throw ce
        } catch (t: Throwable) {
            Result.failure(t)
        }
    }

    private fun parseUserId(raw: String): String? {
        if (raw.isBlank()) return null
        return runCatching {
            JSONObject(raw)
                .optJSONObject("data")
                ?.optString("id")
                ?.takeIf { it.isNotBlank() }
        }.getOrNull()
    }

    private suspend fun executeAuthorized(
        token: String,
        request: suspend (String) -> Response<ResponseBody>
    ): Response<ResponseBody> {
        val first = request("Bearer $token")
        if (first.code() != 401) return first
        return when (val refresh = sessionManager.forceRefresh(authApi)) {
            is TokenRefreshResult.Success -> request("Bearer ${refresh.accessToken}").also { retry ->
                if (retry.code() == 401) sessionManager.invalidateSession()
            }
            TokenRefreshResult.InvalidSession -> first
            TokenRefreshResult.MissingRefreshToken -> {
                sessionManager.invalidateSession()
                first
            }
            TokenRefreshResult.TransientFailure -> first
        }
    }

    suspend fun fetchLibraryBootstrap(forceRefresh: Boolean = false): Result<MusicLibraryBootstrap> =
        withContext(Dispatchers.IO) {
            val (_, userId) = sessionOrFailure()
                .getOrElse { return@withContext Result.failure(it) }
            val favoritesKey = "favorites|$userId"
            val historyKey = "history|$userId|100"
            val playlistsKey = "playlists|$userId"

            if (!forceRefresh) {
                val favorites = favoritesCache.get(favoritesKey, FAVORITES_TTL_MS)
                val history = historyCache.get(historyKey, HISTORY_TTL_MS)
                val playlists = playlistsCache.get(playlistsKey, PLAYLISTS_TTL_MS)
                if (favorites != null && history != null && playlists != null) {
                    return@withContext Result.success(MusicLibraryBootstrap(favorites, history, playlists))
                }
            }

            bootstrapRequests.run("bootstrap|$userId") {
                supervisorScope {
                    val favoritesDeferred = async { listFavorites(forceRefresh = forceRefresh) }
                    val historyDeferred = async { listPlayHistory(forceRefresh = forceRefresh) }
                    val playlistsDeferred = async { listUserPlaylists(forceRefresh = forceRefresh) }

                    runCatching {
                        MusicLibraryBootstrap(
                            favorites = favoritesDeferred.await().getOrThrow(),
                            history = historyDeferred.await().getOrThrow(),
                            playlists = playlistsDeferred.await().getOrThrow()
                        )
                    }
                }
            }
        }

    suspend fun listFavorites(forceRefresh: Boolean = false): Result<List<Song>> = withContext(Dispatchers.IO) {
        val (token, userId) = sessionOrFailure()
            .getOrElse { return@withContext Result.failure(it) }
        val cacheKey = "favorites|$userId"
        if (!forceRefresh) {
            favoritesCache.get(cacheKey, FAVORITES_TTL_MS)?.let { return@withContext Result.success(it) }
        }

        favoriteRequests.run(cacheKey) {
            if (!forceRefresh) {
                favoritesCache.get(cacheKey, FAVORITES_TTL_MS)?.let { return@run Result.success(it) }
            }

            runCatching {
                val response = executeAuthorized(token) { api.listFavorites(token = it, page = 0, size = 100) }
                val items = parsePageItems(response, "Failed to load favorites")
                items.map { it.toSong() }
            }.onSuccess { favoritesCache.put(cacheKey, it) }
        }
    }

    suspend fun setFavorite(song: Song, isFavorite: Boolean): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            if (isFavorite) {
                val response = executeAuthorized(token) { api.saveFavorite(it, song.toFavoriteRequest()) }
                ensureMutationSuccessful(response, "Failed to save favorite")
            } else {
                val response = executeAuthorized(token) {
                    api.deleteFavorite(it, source = song.source, songId = song.id)
                }
                if (!response.isSuccessful && response.code() != 404) {
                    throw IllegalStateException(errorMessage(response, "Failed to delete favorite"))
                }
            }
            favoritesCache.remove("favorites|$userId")
        }
    }

    suspend fun listPlayHistory(limit: Int = 100, forceRefresh: Boolean = false): Result<List<Song>> =
        withContext(Dispatchers.IO) {
            val (token, userId) = sessionOrFailure()
                .getOrElse { return@withContext Result.failure(it) }
            val cacheKey = "history|$userId|$limit"
            if (!forceRefresh) {
                historyCache.get(cacheKey, HISTORY_TTL_MS)?.let { return@withContext Result.success(it) }
            }

            historyRequests.run(cacheKey) {
                if (!forceRefresh) {
                    historyCache.get(cacheKey, HISTORY_TTL_MS)?.let { return@run Result.success(it) }
                }

                runCatching {
                    val response = executeAuthorized(token) {
                        api.listPlayHistory(token = it, page = 0, size = limit.coerceAtMost(100))
                    }
                    val items = parsePageItems(response, "Failed to load play history")
                    historyRecordIds["history_ids|$userId"] = items.toRecordIdMap()
                    items.map { it.toSong() }
                }.onSuccess { historyCache.put(cacheKey, it) }
            }
        }

    @Suppress("UNUSED_PARAMETER")
    suspend fun addPlayHistory(song: Song): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (_, userId) = requireSession()
            historyCache.remove("history|$userId|100")
            // The website backend records history when /api/v1/music/play is called with Authorization.
        }
    }

    suspend fun clearPlayHistory(): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val response = executeAuthorized(token) { api.listPlayHistory(it, page = 0, size = 100) }
            val items = parsePageItems(response, "Failed to load play history")
            items.mapNotNull { it.optLongOrNull("id") }
                .forEach { id ->
                    val deleteResponse = executeAuthorized(token) { api.deletePlayHistoryItem(it, id) }
                    ensureSuccessful(deleteResponse, "Failed to clear play history")
                }
            historyRecordIds.remove("history_ids|$userId")
            historyCache.remove("history|$userId|100")
        }
    }

    suspend fun deletePlayHistoryItem(songId: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val trimmed = songId.trim()
            if (trimmed.isBlank()) throw IllegalArgumentException("Invalid song ID")

            val (token, userId) = requireSession()
            val cacheKey = "history_ids|$userId"
            var recordId = historyRecordIds[cacheKey]?.get(trimmed)
            if (recordId == null) {
                val response = executeAuthorized(token) { api.listPlayHistory(it, page = 0, size = 100) }
                val items = parsePageItems(response, "Failed to load play history")
                val ids = items.toRecordIdMap()
                historyRecordIds[cacheKey] = ids
                recordId = ids[trimmed]
            }
            if (recordId == null) throw IllegalStateException("History item not found")

            val response = executeAuthorized(token) { api.deletePlayHistoryItem(it, recordId) }
            if (!response.isSuccessful && response.code() != 404) {
                throw IllegalStateException(errorMessage(response, "Failed to delete history item"))
            }
            historyCache.remove("history|$userId|100")
        }
    }

    suspend fun listUserPlaylists(forceRefresh: Boolean = false): Result<List<UserPlaylist>> =
        withContext(Dispatchers.IO) {
            val (token, userId) = sessionOrFailure()
                .getOrElse { return@withContext Result.failure(it) }
            val cacheKey = "playlists|$userId"
            if (!forceRefresh) {
                playlistsCache.get(cacheKey, PLAYLISTS_TTL_MS)?.let { return@withContext Result.success(it) }
            }

            playlistRequests.run(cacheKey) {
                if (!forceRefresh) {
                    playlistsCache.get(cacheKey, PLAYLISTS_TTL_MS)?.let { return@run Result.success(it) }
                }

                runCatching {
                    val response = executeAuthorized(token) {
                        api.listUserPlaylists(token = it, page = 0, size = 100)
                    }
                    parsePageItems(response, "Failed to load playlists").map { it.toUserPlaylist() }
                }.onSuccess { playlistsCache.put(cacheKey, it) }
            }
        }

    suspend fun createPlaylist(name: String, description: String?): Result<UserPlaylist> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val title = name.trim()
            if (title.isBlank()) throw IllegalArgumentException("Playlist name is required")
            val response = if (title.startsWith("http://", ignoreCase = true) || title.startsWith("https://", ignoreCase = true)) {
                executeAuthorized(token) { api.importPlaylist(it, PlaylistImportRequest(url = title)) }
            } else {
                executeAuthorized(token) { bearer ->
                    api.createPlaylist(
                        bearer,
                        PlaylistCreateRequest(
                            name = title,
                            description = description?.trim()?.takeIf { it.isNotBlank() }
                        )
                    )
                }
            }
            val data = parseDataObject(response, "Failed to import playlist")
            playlistsCache.remove("playlists|$userId")
            data.toUserPlaylist()
        }
    }

    suspend fun deletePlaylist(playlistId: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val id = playlistId.toLongOrNull() ?: throw IllegalArgumentException("Invalid playlist ID")
            val response = executeAuthorized(token) { api.deletePlaylist(it, id) }
            if (!response.isSuccessful && response.code() != 404) {
                throw IllegalStateException(errorMessage(response, "Failed to delete playlist"))
            }
            playlistsCache.remove("playlists|$userId")
            playlistSongsCache.remove("playlist_songs|$playlistId")
            playlistItemIds.remove("playlist_items|$playlistId")
            Unit
        }
    }

    suspend fun listPlaylistSongs(playlistId: String, forceRefresh: Boolean = false): Result<List<Song>> =
        withContext(Dispatchers.IO) {
            val (token, _) = sessionOrFailure()
                .getOrElse { return@withContext Result.failure(it) }
            val normalizedId = playlistId.trim()
            val cacheKey = "playlist_songs|$normalizedId"
            if (!forceRefresh) {
                playlistSongsCache.get(cacheKey, PLAYLIST_SONGS_TTL_MS)?.let {
                    return@withContext Result.success(it)
                }
            }

            playlistSongsRequests.run(cacheKey) {
                if (!forceRefresh) {
                    playlistSongsCache.get(cacheKey, PLAYLIST_SONGS_TTL_MS)?.let { return@run Result.success(it) }
                }

                runCatching {
                    val id = normalizedId.toLongOrNull() ?: throw IllegalArgumentException("Invalid playlist ID")
                    val response = executeAuthorized(token) {
                        api.playlistDetail(it, id = id, page = 0, size = 100)
                    }
                    val data = parseDataObject(response, "Failed to load playlist songs")
                    val itemPage = data.optJSONObject("items") ?: JSONObject()
                    val items = itemPage.optJSONArray("items") ?: JSONArray()
                    val objects = items.toObjectList()
                    playlistItemIds["playlist_items|$normalizedId"] = objects.toRecordIdMap()
                    objects.map { it.toSong() }
                }.onSuccess { playlistSongsCache.put(cacheKey, it) }
            }
        }

    suspend fun addSongToPlaylist(playlistId: String, song: Song): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val playlistLongId = playlistId.toLongOrNull() ?: throw IllegalArgumentException("Invalid playlist ID")
            val response = executeAuthorized(token) {
                api.addPlaylistItem(it, playlistLongId, song.toPlaylistItemRequest())
            }
            ensureMutationSuccessful(response, "Failed to add song to playlist")
            playlistsCache.remove("playlists|$userId")
            playlistSongsCache.remove("playlist_songs|$playlistId")
            playlistItemIds.remove("playlist_items|$playlistId")
            Unit
        }
    }

    suspend fun removeSongFromPlaylist(playlistId: String, songId: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val playlistLongId = playlistId.toLongOrNull() ?: throw IllegalArgumentException("Invalid playlist ID")
            val itemCacheKey = "playlist_items|$playlistId"
            var itemId = playlistItemIds[itemCacheKey]?.get(songId.trim())
            if (itemId == null) {
                listPlaylistSongs(playlistId, forceRefresh = true).getOrThrow()
                itemId = playlistItemIds[itemCacheKey]?.get(songId.trim())
            }
            if (itemId == null) throw IllegalStateException("Playlist item not found")

            val response = executeAuthorized(token) { api.deletePlaylistItem(it, playlistLongId, itemId) }
            if (!response.isSuccessful && response.code() != 404) {
                throw IllegalStateException(errorMessage(response, "Failed to remove song from playlist"))
            }
            playlistsCache.remove("playlists|$userId")
            playlistSongsCache.remove("playlist_songs|$playlistId")
            playlistItemIds.remove(itemCacheKey)
            Unit
        }
    }

    private fun parsePageItems(response: Response<ResponseBody>, fallbackMessage: String): List<JSONObject> {
        val data = parseDataObject(response, fallbackMessage)
        val items = data.optJSONArray("items") ?: JSONArray()
        return items.toObjectList()
    }

    private fun parseDataObject(response: Response<ResponseBody>, fallbackMessage: String): JSONObject {
        ensureSuccessful(response, fallbackMessage)
        val raw = response.body()?.string().orEmpty()
        val root = JSONObject(raw)
        val code = root.optInt("code", 0)
        if (code != 0) {
            throw IllegalStateException(root.optString("message").ifBlank { fallbackMessage })
        }
        return root.optJSONObject("data") ?: JSONObject()
    }

    private fun ensureSuccessful(response: Response<ResponseBody>, fallbackMessage: String) {
        if (!response.isSuccessful) {
            throw IllegalStateException(errorMessage(response, fallbackMessage))
        }
    }

    private fun ensureMutationSuccessful(response: Response<ResponseBody>, fallbackMessage: String) {
        ensureSuccessful(response, fallbackMessage)
        val raw = response.body()?.string().orEmpty()
        if (raw.isBlank()) return
        runCatching {
            val root = JSONObject(raw)
            if (root.optInt("code", 0) != 0) {
                throw IllegalStateException(root.optString("message").ifBlank { fallbackMessage })
            }
        }.getOrElse { error ->
            if (error is IllegalStateException) throw error
        }
    }

    private fun errorMessage(response: Response<ResponseBody>, fallbackMessage: String): String {
        val raw = response.errorBody()?.string().orEmpty()
        if (raw.isBlank()) return "$fallbackMessage (${response.code()})"
        return runCatching {
            JSONObject(raw).optString("message").ifBlank { "$fallbackMessage (${response.code()})" }
        }.getOrDefault("$fallbackMessage (${response.code()})")
    }

    private fun JSONArray.toObjectList(): List<JSONObject> {
        val list = ArrayList<JSONObject>(length())
        for (i in 0 until length()) {
            optJSONObject(i)?.let { list.add(it) }
        }
        return list
    }

    private fun List<JSONObject>.toRecordIdMap(): Map<String, Long> =
        mapNotNull { item ->
            val songId = item.optString("songId").takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val id = item.optLongOrNull("id") ?: return@mapNotNull null
            songId to id
        }.toMap()

    private fun JSONObject.toSong(): Song {
        val source = optString("source").ifBlank { "netease" }
        val songId = optString("songId").ifBlank { optString("id") }
        val artist = optString("artist").ifBlank { "Unknown" }
        val durationMs = optLongOrNull("durationMs")
            ?: optIntOrNull("durationSec")?.let { it * 1000L }
            ?: 0L
        return Song(
            id = songId,
            name = optString("name").ifBlank { "(unknown)" },
            artists = listOf(Artist(id = "", name = artist)),
            album = Album(
                id = "",
                name = optString("album"),
                picUrl = optString("coverUrl")
            ),
            duration = durationMs,
            source = source
        )
    }

    private fun JSONObject.toUserPlaylist(): UserPlaylist {
        return UserPlaylist(
            id = optString("id"),
            name = optString("name").ifBlank { "Imported Playlist" },
            description = optString("description").takeIf { it.isNotBlank() },
            coverUrl = optString("coverUrl").takeIf { it.isNotBlank() },
            source = optString("source").takeIf { it.isNotBlank() },
            sourceId = optString("sourceId").takeIf { it.isNotBlank() },
            sourceUrl = optString("sourceUrl").takeIf { it.isNotBlank() },
            creatorName = optString("creatorName").takeIf { it.isNotBlank() },
            trackCount = optInt("trackCount", 0).coerceAtLeast(0),
            isPublic = false,
            createdAt = optString("createdAt").takeIf { it.isNotBlank() },
            updatedAt = optString("updatedAt").takeIf { it.isNotBlank() }
        )
    }

    private fun Song.toPlaylistItemRequest(): PlaylistItemRequest {
        val artistName = artists.joinToString(", ") { it.name }.ifBlank { "Unknown" }
        return PlaylistItemRequest(
            source = source,
            songId = id,
            name = name,
            artist = artistName,
            album = album.name.takeIf { it.isNotBlank() },
            coverUrl = album.picUrl.takeIf { it.isNotBlank() },
            durationSec = duration.toDurationSec()
        )
    }

    private fun Song.toFavoriteRequest(): MusicFavoriteRequest {
        val artistName = artists.joinToString(", ") { it.name }.ifBlank { "Unknown" }
        return MusicFavoriteRequest(
            source = source,
            songId = id,
            name = name,
            artist = artistName,
            album = album.name.takeIf { it.isNotBlank() },
            coverUrl = album.picUrl.takeIf { it.isNotBlank() },
            durationSec = duration.toDurationSec()
        )
    }

    private fun JSONObject.optLongOrNull(name: String): Long? {
        if (!has(name) || isNull(name)) return null
        return runCatching { optLong(name) }.getOrNull()?.takeIf { it > 0L }
    }

    private fun JSONObject.optIntOrNull(name: String): Int? {
        if (!has(name) || isNull(name)) return null
        return runCatching { optInt(name) }.getOrNull()?.takeIf { it > 0 }
    }

    private fun Long.toDurationSec(): Int? {
        if (this <= 0L) return null
        val seconds = (this / 1000L).coerceAtLeast(1L)
        return if (seconds > Int.MAX_VALUE.toLong()) Int.MAX_VALUE else seconds.toInt()
    }
}
