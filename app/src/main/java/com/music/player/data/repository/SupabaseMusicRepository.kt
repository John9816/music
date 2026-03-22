package com.music.player.data.repository

import android.content.Context
import com.music.player.data.auth.AuthSessionManager
import com.music.player.data.auth.LegacyMusicFavoriteInsert
import com.music.player.data.auth.LegacyMusicPlayHistoryInsert
import com.music.player.data.auth.MusicFavoriteInsert
import com.music.player.data.auth.MusicLibraryBootstrapRequest
import com.music.player.data.auth.MusicPlaylistInsert
import com.music.player.data.auth.MusicPlaylistRow
import com.music.player.data.auth.MusicPlaylistSongInsert
import com.music.player.data.auth.MusicPlayHistoryInsert
import com.music.player.data.auth.SupabaseClient
import com.music.player.data.common.RequestCoalescer
import com.music.player.data.common.TimedMemoryCache
import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.Song
import com.music.player.data.model.UserPlaylist
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.LinkedHashMap
import java.util.Locale
import java.util.TimeZone

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
    }

    private suspend fun requireSession(): Pair<String, String> {
        var token = sessionManager.getValidAccessToken(authApi) ?: throw IllegalStateException("Not signed in")
        sessionManager.syncUserIdFromAccessToken(token)?.let { return token to it }

        var response = authApi.getUser("Bearer $token")
        if (response.code() == 401) {
            val refreshed = sessionManager.forceRefresh(authApi)
            if (refreshed != null) {
                token = refreshed
                sessionManager.syncUserIdFromAccessToken(token)?.let { return token to it }
                response = authApi.getUser("Bearer $refreshed")
            }
        }

        val userId = response.body()?.id ?: throw IllegalStateException("Failed to load user info")
        sessionManager.cacheUserId(userId)
        return token to userId
    }

    suspend fun fetchLibraryBootstrap(forceRefresh: Boolean = false): Result<MusicLibraryBootstrap> =
        withContext(Dispatchers.IO) {
            val (token, userId) = requireSession()
            val favoritesKey = "favorites|$userId"
            val historyKey = "history|$userId|100"
            val playlistsKey = "playlists|$userId"

            if (!forceRefresh) {
                val favorites = favoritesCache.get(favoritesKey, FAVORITES_TTL_MS)
                val history = historyCache.get(historyKey, HISTORY_TTL_MS)
                val playlists = playlistsCache.get(playlistsKey, PLAYLISTS_TTL_MS)
                if (favorites != null && history != null && playlists != null) {
                    return@withContext Result.success(
                        MusicLibraryBootstrap(
                            favorites = favorites,
                            history = history,
                            playlists = playlists
                        )
                    )
                }
            }

            bootstrapRequests.run("bootstrap|$userId") {
                if (!forceRefresh) {
                    val favorites = favoritesCache.get(favoritesKey, FAVORITES_TTL_MS)
                    val history = historyCache.get(historyKey, HISTORY_TTL_MS)
                    val playlists = playlistsCache.get(playlistsKey, PLAYLISTS_TTL_MS)
                    if (favorites != null && history != null && playlists != null) {
                        return@run Result.success(
                            MusicLibraryBootstrap(
                                favorites = favorites,
                                history = history,
                                playlists = playlists
                            )
                        )
                    }
                }

                runCatching {
                    val response = api.getLibraryBootstrap(
                        token = "Bearer $token",
                        body = MusicLibraryBootstrapRequest()
                    )
                    if (!response.isSuccessful) {
                        throw IllegalStateException("bootstrap rpc unavailable")
                    }

                    val body = response.body() ?: throw IllegalStateException("bootstrap empty")
                    val primaryFavorites = body.favorites.orEmpty().map { it.toSong() }
                    val primaryHistory = body.history.orEmpty().map { it.toSong() }
                    val playlists = body.playlists.orEmpty().map { it.toUserPlaylist() }

                    val favorites = if (primaryFavorites.isEmpty()) {
                        fetchMergedFavorites(token, userId)
                    } else {
                        primaryFavorites
                    }
                    val history = if (primaryHistory.isEmpty()) {
                        fetchMergedHistory(token, userId, limit = 100)
                    } else {
                        primaryHistory
                    }

                    favoritesCache.put(favoritesKey, favorites)
                    historyCache.put(historyKey, history)
                    playlistsCache.put(playlistsKey, playlists)

                    MusicLibraryBootstrap(
                        favorites = favorites,
                        history = history,
                        playlists = playlists
                    )
                }.recoverCatching {
                    supervisorScope {
                        val favoritesDeferred = async { listFavorites(forceRefresh = forceRefresh) }
                        val historyDeferred = async { listPlayHistory(forceRefresh = forceRefresh) }
                        val playlistsDeferred = async { listUserPlaylists(forceRefresh = forceRefresh) }

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
        val (token, userId) = requireSession()
        val cacheKey = "favorites|$userId"
        if (!forceRefresh) {
            favoritesCache.get(cacheKey, FAVORITES_TTL_MS)?.let { return@withContext Result.success(it) }
        }

        favoriteRequests.run(cacheKey) {
            if (!forceRefresh) {
                favoritesCache.get(cacheKey, FAVORITES_TTL_MS)?.let { return@run Result.success(it) }
            }

            runCatching { fetchMergedFavorites(token, userId) }
                .onSuccess { favoritesCache.put(cacheKey, it) }
        }
    }

    suspend fun setFavorite(song: Song, isFavorite: Boolean): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            if (isFavorite) {
                insertFavoriteCompat(token, userId, song)
            } else {
                deleteFavoriteCompat(token, userId, song.id)
            }

            favoritesCache.remove("favorites|$userId")
        }
    }

    suspend fun listPlayHistory(limit: Int = 100, forceRefresh: Boolean = false): Result<List<Song>> =
        withContext(Dispatchers.IO) {
            val (token, userId) = requireSession()
            val cacheKey = "history|$userId|$limit"
            if (!forceRefresh) {
                historyCache.get(cacheKey, HISTORY_TTL_MS)?.let { return@withContext Result.success(it) }
            }

            historyRequests.run(cacheKey) {
                if (!forceRefresh) {
                    historyCache.get(cacheKey, HISTORY_TTL_MS)?.let { return@run Result.success(it) }
                }

                runCatching { fetchMergedHistory(token, userId, limit) }
                    .onSuccess { historyCache.put(cacheKey, it) }
            }
        }

    suspend fun addPlayHistory(song: Song): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            insertPlayHistoryCompat(token, userId, song)
            historyCache.remove("history|$userId|100")
        }
    }

    suspend fun clearPlayHistory(): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            clearPlayHistoryCompat(token, userId)
            historyCache.remove("history|$userId|100")
        }
    }

    suspend fun deletePlayHistoryItem(songId: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val trimmed = songId.trim()
            if (trimmed.isBlank()) throw IllegalArgumentException("Invalid song ID")

            val (token, userId) = requireSession()
            deletePlayHistoryCompat(token, userId, trimmed)
            historyCache.remove("history|$userId|100")
        }
    }

    suspend fun listUserPlaylists(forceRefresh: Boolean = false): Result<List<UserPlaylist>> =
        withContext(Dispatchers.IO) {
            val (token, userId) = requireSession()
            val cacheKey = "playlists|$userId"
            if (!forceRefresh) {
                playlistsCache.get(cacheKey, PLAYLISTS_TTL_MS)?.let { return@withContext Result.success(it) }
            }

            playlistRequests.run(cacheKey) {
                if (!forceRefresh) {
                    playlistsCache.get(cacheKey, PLAYLISTS_TTL_MS)?.let { return@run Result.success(it) }
                }

                runCatching {
                    val response = api.listUserPlaylists(
                        token = "Bearer $token",
                        userId = "eq.$userId"
                    )
                    if (!response.isSuccessful) throw IllegalStateException("Failed to load playlists")
                    response.body().orEmpty().map { row -> row.toUserPlaylist() }
                }.onSuccess { playlistsCache.put(cacheKey, it) }
            }
        }

    suspend fun createPlaylist(name: String, description: String?): Result<UserPlaylist> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val response = api.insertPlaylist(
                token = "Bearer $token",
                playlist = MusicPlaylistInsert(
                    userId = userId,
                    name = name,
                    description = description?.takeIf { it.isNotBlank() },
                    coverUrl = null,
                    isPublic = false
                )
            )
            if (!response.isSuccessful) throw IllegalStateException("Failed to create playlist")
            val row = response.body()?.firstOrNull() ?: throw IllegalStateException("Failed to create playlist")

            playlistsCache.remove("playlists|$userId")
            row.toUserPlaylist()
        }
    }

    suspend fun deletePlaylist(playlistId: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val response = api.deletePlaylist("Bearer $token", playlistId = "eq.$playlistId")
            if (!response.isSuccessful) throw IllegalStateException("Failed to delete playlist")

            playlistsCache.remove("playlists|$userId")
            playlistSongsCache.remove("playlist_songs|$playlistId")
        }
    }

    suspend fun listPlaylistSongs(playlistId: String, forceRefresh: Boolean = false): Result<List<Song>> =
        withContext(Dispatchers.IO) {
            val (token, _) = requireSession()
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
                    val response = api.listPlaylistSongs("Bearer $token", playlistId = "eq.$normalizedId")
                    if (!response.isSuccessful) throw IllegalStateException("Failed to load playlist songs")
                    response.body().orEmpty().map { row ->
                        minimalSong(
                            songId = row.songId,
                            songName = row.songName,
                            artistName = row.artistName,
                            albumCover = row.albumCover
                        )
                    }
                }.onSuccess { playlistSongsCache.put(cacheKey, it) }
            }
        }

    suspend fun addSongToPlaylist(playlistId: String, song: Song): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val songId = song.id.toLongOrNull() ?: throw IllegalArgumentException("Invalid song ID")
            val artistName = song.artists.joinToString(", ") { it.name }.ifBlank { "Unknown" }
            val insert = MusicPlaylistSongInsert(
                playlistId = playlistId,
                songId = songId,
                songName = song.name,
                artistName = artistName,
                albumCover = song.album.picUrl.takeIf { it.isNotBlank() }
            )
            val response = api.insertPlaylistSong("Bearer $token", song = insert)
            if (!response.isSuccessful) throw IllegalStateException("Failed to add song to playlist")

            playlistsCache.remove("playlists|$userId")
            playlistSongsCache.remove("playlist_songs|$playlistId")
        }
    }

    suspend fun removeSongFromPlaylist(playlistId: String, songId: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val id = songId.toLongOrNull() ?: throw IllegalArgumentException("Invalid song ID")
            val response = api.deletePlaylistSong(
                token = "Bearer $token",
                playlistId = "eq.$playlistId",
                songId = "eq.$id"
            )
            if (!response.isSuccessful) throw IllegalStateException("Failed to remove song from playlist")

            playlistsCache.remove("playlists|$userId")
            playlistSongsCache.remove("playlist_songs|$playlistId")
        }
    }

    private suspend fun fetchMergedFavorites(token: String, userId: String): List<Song> {
        val primary = runCatching { fetchFavoritesFromPrimary(token, userId) }
        val legacy = runCatching { fetchFavoritesFromLegacy(token, userId) }
        return mergeSongSources(
            primary = primary.getOrNull().orEmpty(),
            legacy = legacy.getOrNull().orEmpty(),
            primaryFailure = primary.exceptionOrNull(),
            legacyFailure = legacy.exceptionOrNull(),
            failureMessage = "Failed to load favorites"
        )
    }

    private suspend fun fetchMergedHistory(token: String, userId: String, limit: Int): List<Song> {
        val primary = runCatching { fetchHistoryFromPrimary(token, userId, limit) }
        val legacy = runCatching { fetchHistoryFromLegacy(token, userId, limit) }
        return mergeSongSources(
            primary = primary.getOrNull().orEmpty(),
            legacy = legacy.getOrNull().orEmpty(),
            primaryFailure = primary.exceptionOrNull(),
            legacyFailure = legacy.exceptionOrNull(),
            failureMessage = "Failed to load play history"
        )
    }

    private suspend fun fetchFavoritesFromPrimary(token: String, userId: String): List<Song> {
        val response = api.listFavorites(
            token = "Bearer $token",
            userId = "eq.$userId"
        )
        if (!response.isSuccessful) throw IllegalStateException("Failed to load favorites")
        return response.body().orEmpty().map { row -> row.toSong() }
    }

    private suspend fun fetchFavoritesFromLegacy(token: String, userId: String): List<Song> {
        val response = api.listLegacyFavorites(
            token = "Bearer $token",
            userId = "eq.$userId"
        )
        if (!response.isSuccessful) throw IllegalStateException("Failed to load favorites")
        return response.body().orEmpty().map { row -> row.toSong() }
    }

    private suspend fun fetchHistoryFromPrimary(token: String, userId: String, limit: Int): List<Song> {
        val response = api.listPlayHistory(
            token = "Bearer $token",
            userId = "eq.$userId",
            limit = limit
        )
        if (!response.isSuccessful) throw IllegalStateException("Failed to load play history")
        return response.body().orEmpty().map { row -> row.toSong() }
    }

    private suspend fun fetchHistoryFromLegacy(token: String, userId: String, limit: Int): List<Song> {
        val response = api.listLegacyPlayHistory(
            token = "Bearer $token",
            userId = "eq.$userId",
            limit = limit
        )
        if (!response.isSuccessful) throw IllegalStateException("Failed to load play history")
        return response.body().orEmpty().map { row -> row.toSong() }
    }

    private suspend fun insertFavoriteCompat(token: String, userId: String, song: Song) {
        val artistName = song.artists.joinToString(", ") { it.name }.ifBlank { "Unknown" }
        val primaryAction: suspend () -> Unit = {
            val insert = MusicFavoriteInsert(
                userId = userId,
                songId = song.id,
                source = song.source,
                songName = song.name,
                artistName = artistName,
                albumName = song.album.name.takeIf { it.isNotBlank() },
                albumCover = song.album.picUrl.takeIf { it.isNotBlank() },
                duration = song.duration.toIntSafely()
            )
            val response = api.insertFavorite("Bearer $token", favorite = insert)
            if (!response.isSuccessful && response.code() != 409) {
                throw IllegalStateException("Failed to save favorite")
            }
        }
        val legacyAction: suspend () -> Unit = {
            val insert = LegacyMusicFavoriteInsert(
                userId = userId,
                songId = song.id,
                songName = song.name,
                artistName = artistName,
                albumCover = song.album.picUrl.takeIf { it.isNotBlank() }
            )
            val response = api.insertLegacyFavorite("Bearer $token", favorite = insert)
            if (!response.isSuccessful && response.code() != 409) {
                throw IllegalStateException("Failed to save favorite")
            }
        }

        runPrimaryWithLegacyFallback(primaryAction, legacyAction)
    }

    private suspend fun deleteFavoriteCompat(token: String, userId: String, songId: String) {
        val primaryAction: suspend () -> Unit = {
            val response = api.deleteFavorite(
                token = "Bearer $token",
                userId = "eq.$userId",
                songId = "eq.$songId"
            )
            if (!response.isSuccessful) throw IllegalStateException("Failed to delete favorite")
        }
        val legacyAction: suspend () -> Unit = {
            val response = api.deleteLegacyFavorite(
                token = "Bearer $token",
                userId = "eq.$userId",
                songId = "eq.$songId"
            )
            if (!response.isSuccessful) throw IllegalStateException("Failed to delete favorite")
        }

        runPrimaryWithLegacyFallback(primaryAction, legacyAction)
    }

    private suspend fun insertPlayHistoryCompat(token: String, userId: String, song: Song) {
        val artistName = song.artists.joinToString(", ") { it.name }.ifBlank { "Unknown" }
        val playedAt = isoUtcNow()
        val primaryAction: suspend () -> Unit = {
            val insert = MusicPlayHistoryInsert(
                userId = userId,
                songId = song.id,
                source = song.source,
                songName = song.name,
                artistName = artistName,
                albumName = song.album.name.takeIf { it.isNotBlank() },
                albumCover = song.album.picUrl.takeIf { it.isNotBlank() },
                duration = song.duration.toIntSafely(),
                playedAt = playedAt
            )
            val response = api.insertPlayHistory("Bearer $token", history = insert)
            if (!response.isSuccessful) throw IllegalStateException("Failed to save play history")
        }
        val legacyAction: suspend () -> Unit = {
            val insert = LegacyMusicPlayHistoryInsert(
                userId = userId,
                songId = song.id,
                songName = song.name,
                artistName = artistName,
                playedAt = playedAt
            )
            val response = api.insertLegacyPlayHistory("Bearer $token", history = insert)
            if (!response.isSuccessful) throw IllegalStateException("Failed to save play history")
        }

        runPrimaryWithLegacyFallback(primaryAction, legacyAction)
    }

    private suspend fun clearPlayHistoryCompat(token: String, userId: String) {
        val primaryAction: suspend () -> Unit = {
            val response = api.clearPlayHistory("Bearer $token", userId = "eq.$userId")
            if (!response.isSuccessful) throw IllegalStateException("Failed to clear play history")
        }
        val legacyAction: suspend () -> Unit = {
            val response = api.clearLegacyPlayHistory("Bearer $token", userId = "eq.$userId")
            if (!response.isSuccessful) throw IllegalStateException("Failed to clear play history")
        }

        runPrimaryWithLegacyFallback(primaryAction, legacyAction)
    }

    private suspend fun deletePlayHistoryCompat(token: String, userId: String, songId: String) {
        val primaryAction: suspend () -> Unit = {
            val response = api.deletePlayHistoryItem(
                token = "Bearer $token",
                userId = "eq.$userId",
                songId = "eq.$songId"
            )
            if (!response.isSuccessful) throw IllegalStateException("Failed to delete history item")
        }
        val legacyAction: suspend () -> Unit = {
            val response = api.deleteLegacyPlayHistoryItem(
                token = "Bearer $token",
                userId = "eq.$userId",
                songId = "eq.$songId"
            )
            if (!response.isSuccessful) throw IllegalStateException("Failed to delete history item")
        }

        runPrimaryWithLegacyFallback(primaryAction, legacyAction)
    }

    private suspend fun runPrimaryWithLegacyFallback(
        primaryAction: suspend () -> Unit,
        legacyAction: suspend () -> Unit
    ) {
        val primaryResult = runCatching { primaryAction() }
        if (primaryResult.isSuccess) {
            runCatching { legacyAction() }
            return
        }

        val legacyResult = runCatching { legacyAction() }
        if (legacyResult.isSuccess) return

        throw primaryResult.exceptionOrNull() ?: legacyResult.exceptionOrNull() ?: IllegalStateException()
    }

    private fun mergeSongSources(
        primary: List<Song>,
        legacy: List<Song>,
        primaryFailure: Throwable?,
        legacyFailure: Throwable?,
        failureMessage: String
    ): List<Song> {
        if (primaryFailure != null && legacyFailure != null) {
            throw IllegalStateException(failureMessage, primaryFailure)
        }

        if (primary.isEmpty() && legacy.isEmpty()) return emptyList()

        val merged = LinkedHashMap<String, Song>()
        (primary + legacy).forEach { song ->
            val key = song.id.trim().ifBlank {
                buildString {
                    append(song.name.trim())
                    append('|')
                    append(song.artists.joinToString(",") { it.name.trim() })
                }
            }
            merged.putIfAbsent(key, song)
        }
        return merged.values.toList()
    }

    private fun minimalSong(songId: Long, songName: String, artistName: String, albumCover: String?): Song {
        return Song(
            id = songId.toString(),
            name = songName,
            artists = listOf(Artist(id = "", name = artistName)),
            album = Album(id = "", name = "", picUrl = albumCover.orEmpty()),
            duration = 0L
        )
    }

    private fun com.music.player.data.auth.MusicFavoriteRow.toSong(): Song {
        val artist = artistName.orEmpty().ifBlank { "Unknown" }
        return Song(
            id = songId,
            name = songName.orEmpty().ifBlank { "(unknown)" },
            artists = listOf(Artist(id = "", name = artist)),
            album = Album(
                id = "",
                name = albumName.orEmpty(),
                picUrl = albumCover.orEmpty()
            ),
            duration = (duration ?: 0).toLong(),
            source = source ?: "netease"
        )
    }

    private fun com.music.player.data.auth.LegacyMusicFavoriteRow.toSong(): Song {
        val artist = artistName.orEmpty().ifBlank { "Unknown" }
        return Song(
            id = songId,
            name = songName.orEmpty().ifBlank { "(unknown)" },
            artists = listOf(Artist(id = "", name = artist)),
            album = Album(id = "", name = "", picUrl = albumCover.orEmpty()),
            duration = 0L,
            source = "netease"
        )
    }

    private fun com.music.player.data.auth.MusicPlayHistoryRow.toSong(): Song {
        val artist = artistName.orEmpty().ifBlank { "Unknown" }
        return Song(
            id = songId,
            name = songName.orEmpty().ifBlank { "(unknown)" },
            artists = listOf(Artist(id = "", name = artist)),
            album = Album(
                id = "",
                name = albumName.orEmpty(),
                picUrl = albumCover.orEmpty()
            ),
            duration = (duration ?: 0).toLong(),
            source = source ?: "netease"
        )
    }

    private fun com.music.player.data.auth.LegacyMusicPlayHistoryRow.toSong(): Song {
        val artist = artistName.orEmpty().ifBlank { "Unknown" }
        return Song(
            id = songId,
            name = songName.orEmpty().ifBlank { "(unknown)" },
            artists = listOf(Artist(id = "", name = artist)),
            album = Album(id = "", name = "", picUrl = ""),
            duration = 0L,
            source = "netease"
        )
    }

    private fun MusicPlaylistRow.toUserPlaylist(): UserPlaylist {
        return UserPlaylist(
            id = id,
            name = name,
            description = description,
            coverUrl = coverUrl,
            isPublic = isPublic,
            createdAt = createdAt,
            updatedAt = updatedAt
        )
    }

    private fun isoUtcNow(): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date())
    }

    private fun Long.toIntSafely(): Int? {
        if (this <= 0L) return null
        return if (this > Int.MAX_VALUE.toLong()) Int.MAX_VALUE else this.toInt()
    }
}
