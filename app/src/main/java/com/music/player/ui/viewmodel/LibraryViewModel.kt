package com.music.player.ui.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.viewModelScope
import com.music.player.data.model.Song
import com.music.player.data.model.UserPlaylist
import com.music.player.data.repository.MusicLibraryBootstrap
import com.music.player.data.repository.SupabaseMusicRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Library state with industry-standard caching:
 * - Cold start: hydrate from disk snapshot on a background thread → instant UI
 * - Then: silent network refresh (stale-while-revalidate)
 * - Mutations: optimistic UI + debounced full-snapshot disk write (single writer)
 */
class LibraryViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = SupabaseMusicRepository(application.applicationContext)
    private val prefs = application.getSharedPreferences("library_prefs", Context.MODE_PRIVATE)

    private val pinnedFavoritesOrder = mutableListOf<String>().apply {
        addAll(loadPinnedFavorites())
    }

    private val pinnedHistoryOrder = mutableListOf<String>().apply {
        addAll(loadPinnedHistory())
    }

    private var prefetchJob: Job? = null
    private var persistJob: Job? = null
    private var lastPrefetchAtMs: Long = 0L
    private var diskHydrated: Boolean = false
    private var diskSavedAtMs: Long = 0L

    private val _favorites = MutableLiveData<List<Song>>(emptyList())
    val favorites: LiveData<List<Song>> = _favorites

    private val _favoriteIds = MutableLiveData<Set<String>>(emptySet())
    val favoriteIds: LiveData<Set<String>> = _favoriteIds

    private val _history = MutableLiveData<List<Song>>(emptyList())
    val history: LiveData<List<Song>> = _history

    private val _latestHistorySong = MutableLiveData<Song?>()
    val latestHistorySong: LiveData<Song?> = _latestHistorySong

    private val _playlists = MutableLiveData<List<UserPlaylist>>(emptyList())
    val playlists: LiveData<List<UserPlaylist>> = _playlists

    private val _playlistSongs = MutableLiveData<List<Song>>(emptyList())
    val playlistSongs: LiveData<List<Song>> = _playlistSongs

    private val _isLoading = MutableLiveData(false)
    val isLoading: LiveData<Boolean> = _isLoading

    /** True after disk or network has delivered at least one library payload. */
    private val _isHydrated = MutableLiveData(false)
    val isHydrated: LiveData<Boolean> = _isHydrated

    private val _message = MutableLiveData<String?>()
    val message: LiveData<String?> = _message

    init {
        // Stale-while-revalidate: paint disk snapshot ASAP, then network.
        hydrateFromDiskThenRefresh()
    }

    fun isPinnedFavorite(songId: String): Boolean = pinnedFavoritesOrder.contains(songId)

    fun isPinnedHistory(songId: String): Boolean = pinnedHistoryOrder.contains(songId)

    fun togglePinFavorite(songId: String) {
        if (songId.isBlank()) return
        if (pinnedFavoritesOrder.contains(songId)) {
            pinnedFavoritesOrder.removeAll { it == songId }
            _message.value = "已取消置顶收藏"
        } else {
            pinnedFavoritesOrder.removeAll { it == songId }
            pinnedFavoritesOrder.add(0, songId)
            _message.value = "已置顶收藏"
        }
        persistPinnedFavorites(pinnedFavoritesOrder)
        _favorites.value = applyPinnedFavoritesOrder(_favorites.value.orEmpty())
        persistSnapshotAsync()
    }

    fun togglePinHistory(songId: String) {
        if (songId.isBlank()) return
        if (pinnedHistoryOrder.contains(songId)) {
            pinnedHistoryOrder.removeAll { it == songId }
            _message.value = "已取消置顶历史"
        } else {
            pinnedHistoryOrder.removeAll { it == songId }
            pinnedHistoryOrder.add(0, songId)
            _message.value = "已置顶历史"
        }
        persistPinnedHistory(pinnedHistoryOrder)
        _history.value = applyPinnedHistoryOrder(_history.value.orEmpty())
        persistSnapshotAsync()
    }

    private fun hydrateFromDiskThenRefresh() {
        viewModelScope.launch {
            val snapshot = withContext(Dispatchers.IO) {
                repository.loadDiskLibrarySnapshot()
            }
            if (snapshot != null) {
                applyBootstrap(snapshot, fromDisk = true)
                diskHydrated = true
                diskSavedAtMs = snapshot.savedAtMs
            }
            val ageMs = if (diskSavedAtMs > 0L) {
                System.currentTimeMillis() - diskSavedAtMs
            } else {
                Long.MAX_VALUE
            }
            // Fresh disk: paint only; soft network refresh is skipped until cooldown / pull.
            if (diskHydrated && ageMs in 0 until DISK_FRESH_MS) {
                lastPrefetchAtMs = System.currentTimeMillis()
                return@launch
            }
            prefetch(forceRefresh = false, showLoading = !diskHydrated)
        }
    }

    /**
     * @param forceRefresh skip memory TTL and hit network
     * @param showLoading only show global loading when we have nothing to paint
     */
    fun prefetch(forceRefresh: Boolean = false, showLoading: Boolean = true) {
        val now = System.currentTimeMillis()
        val hasSnapshot = _favorites.value.orEmpty().isNotEmpty() ||
            _history.value.orEmpty().isNotEmpty() ||
            _playlists.value.orEmpty().isNotEmpty()
        if (!forceRefresh) {
            if (prefetchJob?.isActive == true) return
            if (hasSnapshot && now - lastPrefetchAtMs < PREFETCH_COOLDOWN_MS) return
        }

        prefetchJob = viewModelScope.launch {
            val shouldShowLoading = showLoading && !hasSnapshot
            if (shouldShowLoading) _isLoading.value = true
            lastPrefetchAtMs = System.currentTimeMillis()
            try {
                repository.fetchLibraryBootstrap(forceRefresh = forceRefresh)
                    .onSuccess { payload ->
                        applyBootstrap(payload, fromDisk = false)
                    }
                    .onFailure { error ->
                        // Keep disk UI; only toast when we had nothing.
                        if (!hasSnapshot) {
                            _message.value = error.message ?: "获取音乐库失败"
                        }
                    }
            } finally {
                if (shouldShowLoading) _isLoading.value = false
            }
        }
    }

    private fun applyBootstrap(payload: MusicLibraryBootstrap, fromDisk: Boolean) {
        _favorites.value = applyPinnedFavoritesOrder(payload.favorites)
        _favoriteIds.value = payload.favorites.mapTo(mutableSetOf()) { it.id }
        _latestHistorySong.value = payload.history.firstOrNull()
        _history.value = applyPinnedHistoryOrder(payload.history)
        _playlists.value = payload.playlists
        _isHydrated.value = true
        if (fromDisk) {
            diskSavedAtMs = payload.savedAtMs
        } else {
            // Sole disk writer path for network results (debounced).
            persistSnapshotAsync()
        }
    }

    fun refreshFavorites(silent: Boolean = false, forceRefresh: Boolean = true) {
        viewModelScope.launch {
            val showLoading = !silent && _favorites.value.orEmpty().isEmpty()
            if (showLoading) _isLoading.value = true
            repository.listFavorites(forceRefresh = forceRefresh)
                .onSuccess { songs ->
                    _favorites.value = applyPinnedFavoritesOrder(songs)
                    _favoriteIds.value = songs.mapTo(mutableSetOf()) { it.id }
                    persistSnapshotAsync()
                    if (!silent) _message.value = "收藏已同步"
                }
                .onFailure {
                    if (!silent) _message.value = it.message ?: "获取收藏失败"
                }
            if (showLoading) _isLoading.value = false
        }
    }

    fun setFavorite(song: Song, favorite: Boolean) {
        // Optimistic update — heart toggles immediately (NetEase / Spotify style).
        val previousFavorites = _favorites.value.orEmpty()
        val previousIds = _favoriteIds.value.orEmpty()

        val optimisticIds = previousIds.toMutableSet().apply {
            if (favorite) add(song.id) else remove(song.id)
        }
        val optimisticList = if (favorite) {
            if (previousFavorites.any { it.id == song.id }) previousFavorites
            else listOf(song) + previousFavorites
        } else {
            previousFavorites.filterNot { it.id == song.id }
        }
        if (!favorite) {
            pinnedFavoritesOrder.removeAll { it == song.id }
            persistPinnedFavorites(pinnedFavoritesOrder)
        }
        _favoriteIds.value = optimisticIds
        _favorites.value = applyPinnedFavoritesOrder(optimisticList)
        persistSnapshotAsync()

        viewModelScope.launch {
            repository.setFavorite(song, favorite)
                .onSuccess {
                    _message.value = if (favorite) "已收藏" else "已取消收藏"
                }
                .onFailure { error ->
                    // Roll back on failure.
                    _favoriteIds.value = previousIds
                    _favorites.value = previousFavorites
                    persistSnapshotAsync()
                    val raw = error.message.orEmpty()
                    _message.value = when {
                        raw.contains("请先登录") || raw.contains("Not signed in", ignoreCase = true) ->
                            "请先登录后再使用收藏"
                        raw.isNotBlank() -> raw
                        favorite -> "收藏失败"
                        else -> "取消收藏失败"
                    }
                }
        }
    }

    fun addToHistory(song: Song) {
        // Optimistic: surface on profile / history list immediately.
        val current = _history.value.orEmpty()
        val next = listOf(song) + current.filterNot { it.id == song.id }
        _history.value = applyPinnedHistoryOrder(next.take(100))
        _latestHistorySong.value = song
        persistSnapshotAsync()

        viewModelScope.launch {
            repository.addPlayHistory(song).onFailure { /* local state already updated */ }
        }
    }

    fun refreshHistory(silent: Boolean = false, forceRefresh: Boolean = true) {
        viewModelScope.launch {
            val showLoading = !silent && _history.value.orEmpty().isEmpty()
            if (showLoading) _isLoading.value = true
            repository.listPlayHistory(forceRefresh = forceRefresh)
                .onSuccess { songs ->
                    _latestHistorySong.value = songs.firstOrNull()
                    _history.value = applyPinnedHistoryOrder(songs)
                    persistSnapshotAsync()
                }
                .onFailure {
                    if (!silent) _message.value = it.message ?: "获取播放历史失败"
                }
            if (showLoading) _isLoading.value = false
        }
    }

    fun deleteHistoryItem(songId: String) {
        val trimmed = songId.trim()
        if (trimmed.isBlank()) return

        val previous = _history.value.orEmpty()
        _history.value = previous.filterNot { it.id == trimmed }
        pinnedHistoryOrder.removeAll { it == trimmed }
        persistPinnedHistory(pinnedHistoryOrder)
        if (_latestHistorySong.value?.id == trimmed) {
            _latestHistorySong.value = _history.value.orEmpty().firstOrNull()
        }
        persistSnapshotAsync()

        viewModelScope.launch {
            repository.deletePlayHistoryItem(trimmed)
                .onSuccess { _message.value = "已删除播放记录" }
                .onFailure { t ->
                    _message.value = t.message ?: "删除播放记录失败"
                    _history.value = previous
                    persistSnapshotAsync()
                }
        }
    }

    fun clearHistory() {
        val previous = _history.value.orEmpty()
        val previousPins = pinnedHistoryOrder.toList()
        _history.value = emptyList()
        _latestHistorySong.value = null
        pinnedHistoryOrder.clear()
        persistPinnedHistory(pinnedHistoryOrder)
        persistSnapshotAsync()
        viewModelScope.launch {
            repository.clearPlayHistory()
                .onSuccess { _message.value = "已清空播放历史" }
                .onFailure {
                    _history.value = previous
                    _latestHistorySong.value = previous.firstOrNull()
                    pinnedHistoryOrder.clear()
                    pinnedHistoryOrder.addAll(previousPins)
                    persistPinnedHistory(pinnedHistoryOrder)
                    persistSnapshotAsync()
                    _message.value = it.message ?: "清空播放历史失败"
                }
        }
    }

    fun refreshPlaylists(silent: Boolean = false, forceRefresh: Boolean = true) {
        viewModelScope.launch {
            val showLoading = !silent && _playlists.value.orEmpty().isEmpty()
            if (showLoading) _isLoading.value = true
            repository.listUserPlaylists(forceRefresh = forceRefresh)
                .onSuccess { playlists ->
                    _playlists.value = playlists
                    persistSnapshotAsync()
                    if (!silent) _message.value = "歌单已同步"
                }
                .onFailure {
                    if (!silent) _message.value = it.message ?: "获取歌单失败"
                }
            if (showLoading) _isLoading.value = false
        }
    }

    fun createPlaylist(name: String, description: String?) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.createPlaylist(name, description)
                .onSuccess { playlist ->
                    _playlists.value = listOf(playlist) + _playlists.value.orEmpty()
                    persistSnapshotAsync()
                    _message.value = "歌单已保存"
                }
                .onFailure { _message.value = it.message ?: "保存歌单失败" }
            _isLoading.value = false
        }
    }

    fun deletePlaylist(playlistId: String) {
        val previous = _playlists.value.orEmpty()
        _playlists.value = previous.filterNot { it.id == playlistId }
        if (_playlistSongs.value != null) {
            // If viewing this playlist, clear songs optimistically.
        }
        persistSnapshotAsync()
        viewModelScope.launch {
            repository.deletePlaylist(playlistId)
                .onSuccess {
                    _playlistSongs.value = emptyList()
                    _message.value = "歌单已删除"
                }
                .onFailure {
                    _playlists.value = previous
                    persistSnapshotAsync()
                    _message.value = it.message ?: "删除歌单失败"
                }
        }
    }

    fun loadPlaylistSongs(playlistId: String, forceRefresh: Boolean = false) {
        viewModelScope.launch {
            val showLoading = _playlistSongs.value.orEmpty().isEmpty()
            if (showLoading) _isLoading.value = true
            repository.listPlaylistSongs(playlistId, forceRefresh = forceRefresh)
                .onSuccess { _playlistSongs.value = it }
                .onFailure { _message.value = it.message ?: "获取歌单歌曲失败" }
            if (showLoading) _isLoading.value = false
        }
    }

    fun addSongToPlaylist(playlistId: String, song: Song) {
        viewModelScope.launch {
            repository.addSongToPlaylist(playlistId, song)
                .onSuccess {
                    _playlists.value = _playlists.value.orEmpty().map { playlist ->
                        if (playlist.id == playlistId) {
                            playlist.copy(trackCount = playlist.trackCount + 1)
                        } else {
                            playlist
                        }
                    }
                    persistSnapshotAsync()
                    _message.value = "已添加到歌单"
                }
                .onFailure { _message.value = it.message ?: "添加到歌单失败" }
        }
    }

    fun removeSongFromPlaylist(playlistId: String, songId: String) {
        val previousSongs = _playlistSongs.value.orEmpty()
        _playlistSongs.value = previousSongs.filterNot { it.id == songId }
        viewModelScope.launch {
            repository.removeSongFromPlaylist(playlistId, songId)
                .onSuccess {
                    _playlists.value = _playlists.value.orEmpty().map { playlist ->
                        if (playlist.id == playlistId) {
                            playlist.copy(trackCount = (playlist.trackCount - 1).coerceAtLeast(0))
                        } else {
                            playlist
                        }
                    }
                    persistSnapshotAsync()
                    _message.value = "已从歌单移除"
                }
                .onFailure {
                    _playlistSongs.value = previousSongs
                    _message.value = it.message ?: "从歌单移除失败"
                }
        }
    }

    fun consumeMessage() {
        _message.value = null
    }

    private fun persistSnapshotAsync() {
        val favorites = _favorites.value.orEmpty()
        val history = _history.value.orEmpty()
        val playlists = _playlists.value.orEmpty()
        persistJob?.cancel()
        persistJob = viewModelScope.launch(Dispatchers.IO) {
            delay(PERSIST_DEBOUNCE_MS)
            repository.persistLibrarySnapshot(favorites, history, playlists)
            diskSavedAtMs = System.currentTimeMillis()
        }
    }

    private fun applyPinnedFavoritesOrder(songs: List<Song>): List<Song> {
        if (songs.isEmpty()) return songs

        val pinned = pinnedFavoritesOrder.toList()
        if (pinned.isEmpty()) return songs

        val byId = songs.associateBy { it.id }
        val pinnedSongs = pinned.mapNotNull { byId[it] }
        val pinnedSet = pinnedSongs.mapTo(hashSetOf()) { it.id }
        val rest = songs.filterNot { pinnedSet.contains(it.id) }
        return pinnedSongs + rest
    }

    private fun applyPinnedHistoryOrder(songs: List<Song>): List<Song> {
        if (songs.isEmpty()) return songs

        val pinned = pinnedHistoryOrder.toList()
        if (pinned.isEmpty()) return songs

        val byId = songs.associateBy { it.id }
        val pinnedSongs = pinned.mapNotNull { byId[it] }
        val pinnedSet = pinnedSongs.mapTo(hashSetOf()) { it.id }
        val rest = songs.filterNot { pinnedSet.contains(it.id) }
        return pinnedSongs + rest
    }

    private fun loadPinnedFavorites(): List<String> {
        val raw = prefs.getString(KEY_PINNED_FAVORITES, null)?.trim().orEmpty()
        if (raw.isBlank()) return emptyList()
        return raw.split(',').map { it.trim() }.filter { it.isNotBlank() }.distinct()
    }

    private fun persistPinnedFavorites(order: List<String>) {
        val cleaned = order.map { it.trim() }.filter { it.isNotBlank() }.distinct()
        prefs.edit().putString(KEY_PINNED_FAVORITES, cleaned.joinToString(",")).apply()
    }

    private fun loadPinnedHistory(): List<String> {
        val raw = prefs.getString(KEY_PINNED_HISTORY, null)?.trim().orEmpty()
        if (raw.isBlank()) return emptyList()
        return raw.split(',').map { it.trim() }.filter { it.isNotBlank() }.distinct()
    }

    private fun persistPinnedHistory(order: List<String>) {
        val cleaned = order.map { it.trim() }.filter { it.isNotBlank() }.distinct()
        prefs.edit().putString(KEY_PINNED_HISTORY, cleaned.joinToString(",")).apply()
    }

    private companion object {
        private const val KEY_PINNED_FAVORITES = "pinned_favorites_order"
        private const val KEY_PINNED_HISTORY = "pinned_history_order"
        private const val PREFETCH_COOLDOWN_MS = 20 * 1000L
        /** Skip soft network bootstrap when disk snapshot is fresher than this. */
        private const val DISK_FRESH_MS = 12 * 60 * 1000L
        private const val PERSIST_DEBOUNCE_MS = 350L
    }
}
