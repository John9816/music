package com.music.player.ui.viewmodel

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.music.player.data.model.Playlist
import com.music.player.data.repository.MusicRepository
import kotlinx.coroutines.launch

class PlaylistCategoryAllViewModel : ViewModel() {

    private val repository = MusicRepository()

    private val _playlists = MutableLiveData<List<Playlist>>(emptyList())
    val playlists: LiveData<List<Playlist>> = _playlists

    private val _isLoading = MutableLiveData(false)
    val isLoading: LiveData<Boolean> = _isLoading

    private val _error = MutableLiveData<String?>()
    val error: LiveData<String?> = _error

    private var category: String = ""
    private var offset: Int = 0
    private var canLoadMore: Boolean = true
    private var requestInFlight: Boolean = false

    fun resetAndLoad(category: String, limit: Int = 42, autoPrefetchNextPage: Boolean = true) {
        this.category = category
        offset = 0
        canLoadMore = true
        _playlists.value = emptyList()
        loadMore(limit = limit, autoPrefetchNextPage = autoPrefetchNextPage)
    }

    fun loadMore(limit: Int = 42, autoPrefetchNextPage: Boolean = false) {
        if (requestInFlight) return
        if (!canLoadMore) return

        viewModelScope.launch {
            requestInFlight = true
            _isLoading.value = true
            try {
                repository.getTopPlaylists(category = category, limit = limit, offset = offset)
                    .onSuccess { page ->
                        val current = _playlists.value.orEmpty()
                        val merged = LinkedHashMap<String, Playlist>(current.size + page.size)
                        current.forEach { merged[it.id] = it }
                        page.forEach { merged[it.id] = it }
                        _playlists.value = merged.values.toList()

                        offset += limit
                        canLoadMore = page.size >= limit
                        if (autoPrefetchNextPage && canLoadMore) {
                            _isLoading.value = false
                            requestInFlight = false
                            loadMore(limit = limit, autoPrefetchNextPage = false)
                            return@launch
                        }
                    }
                    .onFailure { _error.value = it.message ?: "获取歌单失败" }
            } finally {
                _isLoading.value = false
                requestInFlight = false
            }
        }
    }
}
