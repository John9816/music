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
    val playlists: List<UserPlaylist>,
    /** Wall-clock when the disk snapshot was last written; 0 if from RAM/network only. */
    val savedAtMs: Long = 0L
)

class SupabaseMusicRepository(context: Context) {

    private val appContext = context.applicationContext
    private val sessionManager = AuthSessionManager(appContext)
    private val authApi = SupabaseClient.authApi
    private val api = SupabaseClient.musicApi
    private val diskCache = LibraryDiskCache(appContext)

    fun cachedUserId(): String? = sessionManager.getCachedUserId()

    /** Synchronous disk read for cold-start UI (call off main if needed). */
    fun loadDiskLibrarySnapshot(): MusicLibraryBootstrap? {
        val userId = sessionManager.getCachedUserId() ?: return null
        val snap = diskCache.load(userId) ?: return null
        val bootstrap = snap.toBootstrap()
        // Seed in-memory caches so subsequent list* calls hit RAM first.
        favoritesCache.put("favorites|$userId", bootstrap.favorites)
        historyCache.put("history|$userId|100", bootstrap.history)
        playlistsCache.put("playlists|$userId", bootstrap.playlists)
        return bootstrap
    }

    fun persistLibrarySnapshot(
        favorites: List<Song>,
        history: List<Song>,
        playlists: List<UserPlaylist>
    ) {
        val userId = sessionManager.getCachedUserId() ?: return
        synchronized(diskWriteLock) {
            diskCache.save(userId, LibraryDiskCache.Snapshot.from(favorites, history, playlists))
        }
        favoritesCache.put("favorites|$userId", favorites)
        historyCache.put("history|$userId|100", history)
        playlistsCache.put("playlists|$userId", playlists)
    }

    fun updateMemoryFavorites(userId: String, favorites: List<Song>) {
        favoritesCache.put("favorites|$userId", favorites)
    }

    fun updateMemoryHistory(userId: String, history: List<Song>) {
        historyCache.put("history|$userId|100", history)
    }

    fun updateMemoryPlaylists(userId: String, playlists: List<UserPlaylist>) {
        playlistsCache.put("playlists|$userId", playlists)
    }

    /**
     * Drop this user's disk library snapshot and all process-wide library RAM caches.
     * Call on explicit logout after capturing [userId] and clearing the session so
     * in-flight [persistLibrarySnapshot] calls no-op.
     */
    fun clearLocalLibraryForUser(userId: String?) {
        val id = userId?.trim().orEmpty()
        if (id.isNotEmpty()) {
            synchronized(diskWriteLock) {
                diskCache.clear(id)
            }
        }
        favoritesCache.clear()
        historyCache.clear()
        playlistsCache.clear()
        playlistSongsCache.clear()
        historyRecordIds.clear()
        // Playlist item ids are keyed by playlist id only — wipe on logout.
        playlistItemIds.clear()
    }

    private companion object {
        private const val MSG_NOT_SIGNED_IN = "请先登录后再使用收藏"
        // Soft memory TTL: disk is durable; RAM is for hot re-entry within a session.
        private const val FAVORITES_TTL_MS = 5 * 60 * 1000L
        private const val HISTORY_TTL_MS = 3 * 60 * 1000L
        private const val PLAYLISTS_TTL_MS = 5 * 60 * 1000L
        private const val PLAYLIST_SONGS_TTL_MS = 2 * 60 * 1000L

        private val favoritesCache = TimedMemoryCache<String, List<Song>>(maxSize = 8)
        private val historyCache = TimedMemoryCache<String, List<Song>>(maxSize = 8)
        private val playlistsCache = TimedMemoryCache<String, List<UserPlaylist>>(maxSize = 8)
        private val playlistSongsCache = TimedMemoryCache<String, List<Song>>()

        private val favoriteRequests = RequestCoalescer<String, Result<List<Song>>>()
        private val historyRequests = RequestCoalescer<String, Result<List<Song>>>()
        private val playlistRequests = RequestCoalescer<String, Result<List<UserPlaylist>>>()
        private val playlistSongsRequests = RequestCoalescer<String, Result<List<Song>>>()
        private val bootstrapRequests = RequestCoalescer<String, Result<MusicLibraryBootstrap>>()

        private val historyRecordIds = mutableMapOf<String, Map<String, Long>>()
        private val playlistItemIds = mutableMapOf<String, Map<String, Long>>()

        /** Serializes partial disk snapshot RMW so concurrent field updates cannot clobber siblings. */
        private val diskWriteLock = Any()
    }

    private suspend fun requireSession(): Pair<String, String> {
        val hadStoredSession = sessionManager.isLoggedIn()
        var token = sessionManager.getValidAccessToken(authApi) ?: run {
            if (!hadStoredSession) sessionManager.invalidateSession()
            throw IllegalStateException(MSG_NOT_SIGNED_IN)
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
                            playlists = playlistsDeferred.await().getOrThrow(),
                            savedAtMs = 0L
                        )
                    }
                    // Disk write is owned by LibraryViewModel.persistLibrarySnapshot (debounced).
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
                fetchAllPages(
                    pageSize = LibraryPageParser.DEFAULT_PAGE_SIZE,
                    fallbackMessage = "Failed to load favorites"
                ) { page, size ->
                    executeAuthorized(token) { api.listFavorites(token = it, page = page, size = size) }
                }.map { it.toSong() }
            }.onSuccess { list ->
                favoritesCache.put(cacheKey, list)
            }
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
            // Memory only — ViewModel owns debounced full-snapshot disk writes.
            val current = knownFavorites(userId)
            if (current != null) {
                val next = if (isFavorite) {
                    if (current.any { it.id == song.id }) current else listOf(song) + current
                } else {
                    current.filterNot { it.id == song.id }
                }
                favoritesCache.put("favorites|$userId", next)
            } else if (isFavorite) {
                favoritesCache.put("favorites|$userId", listOf(song))
            } else {
                favoritesCache.remove("favorites|$userId")
            }
        }
    }

    private fun knownFavorites(userId: String): List<Song>? {
        val key = "favorites|$userId"
        favoritesCache.get(key, FAVORITES_TTL_MS)?.let { return it }
        favoritesCache.getStale(key)?.let { return it }
        return diskCache.load(userId)?.toBootstrap()?.favorites
    }

    private fun knownHistory(userId: String): List<Song>? {
        val key = "history|$userId|100"
        historyCache.get(key, HISTORY_TTL_MS)?.let { return it }
        historyCache.getStale(key)?.let { return it }
        return diskCache.load(userId)?.toBootstrap()?.history
    }

    private fun knownPlaylists(userId: String): List<UserPlaylist>? {
        val key = "playlists|$userId"
        playlistsCache.get(key, PLAYLISTS_TTL_MS)?.let { return it }
        playlistsCache.getStale(key)?.let { return it }
        return diskCache.load(userId)?.toBootstrap()?.playlists
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
                    val pageSize = LibraryPageParser.DEFAULT_PAGE_SIZE
                    val capped = limit.coerceAtLeast(1)
                    // When caller asks for a small window, one page is enough; bootstrap uses large limits.
                    val objects = if (capped <= pageSize) {
                        val response = executeAuthorized(token) {
                            api.listPlayHistory(token = it, page = 0, size = capped.coerceAtMost(pageSize))
                        }
                        parsePageItems(response, "Failed to load play history")
                    } else {
                        fetchAllPages(
                            pageSize = pageSize,
                            fallbackMessage = "Failed to load play history",
                            maxItems = capped
                        ) { page, size ->
                            executeAuthorized(token) {
                                api.listPlayHistory(token = it, page = page, size = size)
                            }
                        }
                    }
                    historyRecordIds["history_ids|$userId"] = objects.toRecordIdMap()
                    objects.map { it.toSong() }.take(capped)
                }.onSuccess { list ->
                    historyCache.put(cacheKey, list)
                }
            }
        }

    @Suppress("UNUSED_PARAMETER")
    suspend fun addPlayHistory(song: Song): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (_, userId) = requireSession()
            val key = "history|$userId|100"
            val current = knownHistory(userId).orEmpty()
            val next = (listOf(song) + current.filterNot { it.id == song.id }).take(100)
            historyCache.put(key, next)
            // Disk via ViewModel; backend records history on /api/v1/music/play.
        }
    }

    suspend fun clearPlayHistory(): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val items = fetchAllPages(
                pageSize = LibraryPageParser.DEFAULT_PAGE_SIZE,
                fallbackMessage = "Failed to load play history"
            ) { page, size ->
                executeAuthorized(token) { api.listPlayHistory(it, page = page, size = size) }
            }
            items.mapNotNull { it.optLongOrNull("id") }
                .forEach { id ->
                    val deleteResponse = executeAuthorized(token) { api.deletePlayHistoryItem(it, id) }
                    ensureSuccessful(deleteResponse, "Failed to clear play history")
                }
            historyRecordIds.remove("history_ids|$userId")
            historyCache.put("history|$userId|100", emptyList())
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
            val key = "history|$userId|100"
            val baseline = knownHistory(userId)
            if (baseline != null) {
                historyCache.put(key, baseline.filterNot { it.id == trimmed })
            } else {
                historyCache.remove(key)
            }
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
                    fetchAllPages(
                        pageSize = LibraryPageParser.DEFAULT_PAGE_SIZE,
                        fallbackMessage = "Failed to load playlists"
                    ) { page, size ->
                        executeAuthorized(token) {
                            api.listUserPlaylists(token = it, page = page, size = size)
                        }
                    }.map { it.toUserPlaylist() }
                }.onSuccess { list ->
                    playlistsCache.put(cacheKey, list)
                }
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
            val created = data.toUserPlaylist()
            val key = "playlists|$userId"
            val current = knownPlaylists(userId)
            playlistsCache.put(
                key,
                if (current != null) {
                    listOf(created) + current.filterNot { it.id == created.id }
                } else {
                    listOf(created)
                }
            )
            created
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
            val key = "playlists|$userId"
            val current = knownPlaylists(userId)
            if (current != null) {
                playlistsCache.put(key, current.filterNot { it.id == playlistId })
            } else {
                playlistsCache.remove(key)
            }
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
                    val objects = fetchAllPlaylistTrackPages(token, id)
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

    private suspend fun fetchAllPages(
        pageSize: Int,
        fallbackMessage: String,
        maxItems: Int = Int.MAX_VALUE,
        fetch: suspend (page: Int, size: Int) -> Response<ResponseBody>
    ): List<JSONObject> {
        val all = ArrayList<JSONObject>()
        var page = 0
        while (page < LibraryPageParser.MAX_PAGES && all.size < maxItems) {
            val response = fetch(page, pageSize)
            val data = parseDataObject(response, fallbackMessage)
            val items = data.optJSONArray("items") ?: JSONArray()
            val pageObjects = items.toObjectList()
            if (pageObjects.isEmpty()) break
            val remaining = maxItems - all.size
            if (pageObjects.size <= remaining) {
                all.addAll(pageObjects)
            } else {
                all.addAll(pageObjects.take(remaining))
                break
            }
            val meta = pageMetaFromData(data)
            if (!LibraryPageParser.shouldFetchNextPage(
                    page = page,
                    pageSize = pageSize,
                    pageItemCount = pageObjects.size,
                    totalElements = meta.first,
                    totalPages = meta.second
                )
            ) {
                break
            }
            page++
        }
        return all
    }

    /** Playlist detail nests tracks under data.items.items (page object). */
    private suspend fun fetchAllPlaylistTrackPages(
        token: String,
        playlistId: Long
    ): List<JSONObject> {
        val all = ArrayList<JSONObject>()
        val pageSize = LibraryPageParser.DEFAULT_PAGE_SIZE
        var page = 0
        while (page < LibraryPageParser.MAX_PAGES) {
            val response = executeAuthorized(token) {
                api.playlistDetail(it, id = playlistId, page = page, size = pageSize)
            }
            val data = parseDataObject(response, "Failed to load playlist songs")
            val itemPage = data.optJSONObject("items") ?: JSONObject()
            val items = itemPage.optJSONArray("items") ?: JSONArray()
            val pageObjects = items.toObjectList()
            if (pageObjects.isEmpty()) break
            all.addAll(pageObjects)
            val meta = pageMetaFromData(itemPage).let { nested ->
                if (nested.first != null || nested.second != null) nested
                else pageMetaFromData(data)
            }
            if (!LibraryPageParser.shouldFetchNextPage(
                    page = page,
                    pageSize = pageSize,
                    pageItemCount = pageObjects.size,
                    totalElements = meta.first,
                    totalPages = meta.second
                )
            ) {
                break
            }
            page++
        }
        return all
    }

    private fun pageMetaFromData(data: JSONObject): Pair<Int?, Int?> {
        val keys = mapOf(
            "totalElements" to data.opt("totalElements"),
            "total" to data.opt("total"),
            "totalCount" to data.opt("totalCount"),
            "count" to data.opt("count"),
            "totalPages" to data.opt("totalPages"),
            "pages" to data.opt("pages"),
            "pageCount" to data.opt("pageCount")
        )
        return LibraryPageParser.readTotalElements(keys) to LibraryPageParser.readTotalPages(keys)
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
