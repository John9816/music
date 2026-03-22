package com.music.player.ui.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.viewModelScope
import com.music.player.data.model.Song
import com.music.player.data.model.UserPlaylist
import com.music.player.data.repository.SupabaseMusicRepository
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.supervisorScope

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
    private var lastPrefetchAtMs: Long = 0L

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

    private val _message = MutableLiveData<String?>()
    val message: LiveData<String?> = _message

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
    }

    fun prefetch(forceRefresh: Boolean = false) {
        val now = System.currentTimeMillis()
        val hasSnapshot = _favorites.value.orEmpty().isNotEmpty() || _history.value.orEmpty().isNotEmpty()
        if (!forceRefresh) {
            if (prefetchJob?.isActive == true) return
            if (hasSnapshot && now - lastPrefetchAtMs < PREFETCH_COOLDOWN_MS) return
        }

        prefetchJob = viewModelScope.launch {
            _isLoading.value = true
            lastPrefetchAtMs = System.currentTimeMillis()
            try {
                supervisorScope {
                    val bootstrapDeferred = async { repository.fetchLibraryBootstrap(forceRefresh = forceRefresh) }

                    bootstrapDeferred.await()
                        .onSuccess { payload ->
                            _favorites.value = applyPinnedFavoritesOrder(payload.favorites)
                            _favoriteIds.value = payload.favorites.mapTo(mutableSetOf()) { it.id }
                            _latestHistorySong.value = payload.history.firstOrNull()
                            _history.value = applyPinnedHistoryOrder(payload.history)
                            _playlists.value = payload.playlists
                        }
                        .onFailure { _message.value = it.message ?: "获取音乐库失败" }
                }
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun refreshFavorites(silent: Boolean = false, forceRefresh: Boolean = true) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.listFavorites(forceRefresh = forceRefresh)
                .onSuccess { songs ->
                    _favorites.value = applyPinnedFavoritesOrder(songs)
                    _favoriteIds.value = songs.mapTo(mutableSetOf()) { it.id }
                    if (!silent) _message.value = "收藏已同步"
                }
                .onFailure { _message.value = it.message ?: "获取收藏失败" }
            _isLoading.value = false
        }
    }

    fun setFavorite(song: Song, favorite: Boolean) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.setFavorite(song, favorite)
                .onSuccess {
                    val ids = _favoriteIds.value.orEmpty().toMutableSet()
                    if (favorite) ids.add(song.id) else ids.remove(song.id)
                    _favoriteIds.value = ids

                    val current = _favorites.value.orEmpty()
                    val updated = if (favorite) {
                        if (current.any { it.id == song.id }) current else listOf(song) + current
                    } else {
                        current.filterNot { it.id == song.id }
                    }

                    if (!favorite) {
                        pinnedFavoritesOrder.removeAll { it == song.id }
                        persistPinnedFavorites(pinnedFavoritesOrder)
                    }

                    _favorites.value = applyPinnedFavoritesOrder(updated)
                }
                .onFailure {
                    _message.value = it.message ?: if (favorite) "收藏失败" else "取消收藏失败"
                }
            _isLoading.value = false
        }
    }

    fun addToHistory(song: Song) {
        viewModelScope.launch {
            repository.addPlayHistory(song).onFailure { }
        }
    }

    fun refreshHistory(silent: Boolean = false, forceRefresh: Boolean = true) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.listPlayHistory(forceRefresh = forceRefresh)
                .onSuccess { songs ->
                    _latestHistorySong.value = songs.firstOrNull()
                    _history.value = applyPinnedHistoryOrder(songs)
                    if (!silent) _message.value = "播放历史已同步"
                }
                .onFailure { _message.value = it.message ?: "获取播放历史失败" }
            _isLoading.value = false
        }
    }

    fun deleteHistoryItem(songId: String) {
        val trimmed = songId.trim()
        if (trimmed.isBlank()) return

        val current = _history.value.orEmpty()
        _history.value = current.filterNot { it.id == trimmed }
        pinnedHistoryOrder.removeAll { it == trimmed }
        persistPinnedHistory(pinnedHistoryOrder)

        viewModelScope.launch {
            repository.deletePlayHistoryItem(trimmed)
                .onSuccess { _message.value = "已删除播放记录" }
                .onFailure { t ->
                    _message.value = t.message ?: "删除播放记录失败"
                    refreshHistory(forceRefresh = true)
                }
        }
    }

    fun clearHistory() {
        viewModelScope.launch {
            _isLoading.value = true
            repository.clearPlayHistory()
                .onSuccess {
                    _history.value = emptyList()
                    _message.value = "已清空播放历史"
                }
                .onFailure { _message.value = it.message ?: "清空播放历史失败" }
            _isLoading.value = false
        }
    }

    fun refreshPlaylists(silent: Boolean = false, forceRefresh: Boolean = true) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.listUserPlaylists(forceRefresh = forceRefresh)
                .onSuccess { playlists ->
                    _playlists.value = playlists
                    if (!silent) _message.value = "歌单已同步"
                }
                .onFailure { _message.value = it.message ?: "获取歌单失败" }
            _isLoading.value = false
        }
    }

    fun createPlaylist(name: String, description: String?) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.createPlaylist(name, description)
                .onSuccess { playlist ->
                    _playlists.value = listOf(playlist) + _playlists.value.orEmpty()
                    _message.value = "歌单已创建"
                }
                .onFailure { _message.value = it.message ?: "创建歌单失败" }
            _isLoading.value = false
        }
    }

    fun deletePlaylist(playlistId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.deletePlaylist(playlistId)
                .onSuccess {
                    _playlists.value = _playlists.value.orEmpty().filterNot { it.id == playlistId }
                    _playlistSongs.value = emptyList()
                    _message.value = "歌单已删除"
                }
                .onFailure { _message.value = it.message ?: "删除歌单失败" }
            _isLoading.value = false
        }
    }

    fun loadPlaylistSongs(playlistId: String, forceRefresh: Boolean = true) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.listPlaylistSongs(playlistId, forceRefresh = forceRefresh)
                .onSuccess { _playlistSongs.value = it }
                .onFailure { _message.value = it.message ?: "获取歌单歌曲失败" }
            _isLoading.value = false
        }
    }

    fun addSongToPlaylist(playlistId: String, song: Song) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.addSongToPlaylist(playlistId, song)
                .onSuccess { _message.value = "已添加到歌单" }
                .onFailure { _message.value = it.message ?: "添加到歌单失败" }
            _isLoading.value = false
        }
    }

    fun removeSongFromPlaylist(playlistId: String, songId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.removeSongFromPlaylist(playlistId, songId)
                .onSuccess {
                    _playlistSongs.value = _playlistSongs.value.orEmpty().filterNot { it.id == songId }
                    _message.value = "已从歌单移除"
                }
                .onFailure { _message.value = it.message ?: "从歌单移除失败" }
            _isLoading.value = false
        }
    }

    fun consumeMessage() {
        _message.value = null
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
        private const val PREFETCH_COOLDOWN_MS = 15 * 1000L
    }
}
