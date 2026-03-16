package com.music.player.ui.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.viewModelScope
import com.music.player.data.model.Song
import com.music.player.data.model.UserPlaylist
import com.music.player.data.repository.SupabaseMusicRepository
import kotlinx.coroutines.launch

class LibraryViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = SupabaseMusicRepository(application.applicationContext)

    private val _favorites = MutableLiveData<List<Song>>(emptyList())
    val favorites: LiveData<List<Song>> = _favorites

    private val _favoriteIds = MutableLiveData<Set<String>>(emptySet())
    val favoriteIds: LiveData<Set<String>> = _favoriteIds

    private val _history = MutableLiveData<List<Song>>(emptyList())
    val history: LiveData<List<Song>> = _history

    private val _playlists = MutableLiveData<List<UserPlaylist>>(emptyList())
    val playlists: LiveData<List<UserPlaylist>> = _playlists

    private val _playlistSongs = MutableLiveData<List<Song>>(emptyList())
    val playlistSongs: LiveData<List<Song>> = _playlistSongs

    private val _isLoading = MutableLiveData(false)
    val isLoading: LiveData<Boolean> = _isLoading

    private val _message = MutableLiveData<String?>()
    val message: LiveData<String?> = _message

    fun prefetch() {
        refreshFavorites(silent = true)
    }

    fun refreshFavorites(silent: Boolean = false) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.listFavorites()
                .onSuccess { songs ->
                    _favorites.value = songs
                    _favoriteIds.value = songs.mapTo(mutableSetOf()) { it.id }
                    if (!silent) _message.value = "已同步云端收藏"
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
                    _favorites.value = if (favorite) {
                        if (current.any { it.id == song.id }) current else listOf(song) + current
                    } else {
                        current.filterNot { it.id == song.id }
                    }
                }
                .onFailure { _message.value = it.message ?: if (favorite) "收藏失败" else "取消收藏失败" }
            _isLoading.value = false
        }
    }

    fun addToHistory(song: Song) {
        viewModelScope.launch {
            repository.addPlayHistory(song).onFailure { }
        }
    }

    fun refreshHistory() {
        viewModelScope.launch {
            _isLoading.value = true
            repository.listPlayHistory()
                .onSuccess { _history.value = it }
                .onFailure { _message.value = it.message ?: "获取播放历史失败" }
            _isLoading.value = false
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

    fun refreshPlaylists(silent: Boolean = false) {
        // “获取我的歌单”接口已移除：保持本地会话内状态。
        if (!silent) _message.value = "已停用云端歌单同步"
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

    fun loadPlaylistSongs(playlistId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.listPlaylistSongs(playlistId)
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
}
