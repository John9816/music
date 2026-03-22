package com.music.player.ui.viewmodel

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.music.player.data.model.NewestAlbum
import com.music.player.data.model.Playlist
import com.music.player.data.model.PlaylistCategory
import com.music.player.data.model.Song
import com.music.player.data.repository.AlbumRepository
import com.music.player.data.repository.MusicRepository
import com.music.player.playback.PlaybackCoordinator
import com.music.player.playback.PlaybackCoordinator.PlaylistViewMode
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.supervisorScope

class MusicViewModel : ViewModel() {

    private val repository = MusicRepository()
    private val albumRepository = AlbumRepository()

    private val _dailyRecommend = MutableLiveData<List<Song>>()
    val dailyRecommend: LiveData<List<Song>> = _dailyRecommend

    private val _topLists = MutableLiveData<List<Playlist>>()
    val topLists: LiveData<List<Playlist>> = _topLists

    private val _topPlaylists = MutableLiveData<List<Playlist>>()
    val topPlaylists: LiveData<List<Playlist>> = _topPlaylists

    private val _playlistCategories = MutableLiveData<List<PlaylistCategory>>(listOf(PlaylistCategory.All))
    val playlistCategories: LiveData<List<PlaylistCategory>> = _playlistCategories

    private val _languagePlaylists = MutableLiveData<List<Playlist>>(emptyList())
    val languagePlaylists: LiveData<List<Playlist>> = _languagePlaylists

    private val _stylePlaylists = MutableLiveData<List<Playlist>>(emptyList())
    val stylePlaylists: LiveData<List<Playlist>> = _stylePlaylists

    private val _scenePlaylists = MutableLiveData<List<Playlist>>(emptyList())
    val scenePlaylists: LiveData<List<Playlist>> = _scenePlaylists

    private val _emotionPlaylists = MutableLiveData<List<Playlist>>(emptyList())
    val emotionPlaylists: LiveData<List<Playlist>> = _emotionPlaylists

    private val _themePlaylists = MutableLiveData<List<Playlist>>(emptyList())
    val themePlaylists: LiveData<List<Playlist>> = _themePlaylists

    private val _languageLoading = MutableLiveData(false)
    val languageLoading: LiveData<Boolean> = _languageLoading

    private val _styleLoading = MutableLiveData(false)
    val styleLoading: LiveData<Boolean> = _styleLoading

    private val _sceneLoading = MutableLiveData(false)
    val sceneLoading: LiveData<Boolean> = _sceneLoading

    private val _emotionLoading = MutableLiveData(false)
    val emotionLoading: LiveData<Boolean> = _emotionLoading

    private val _themeLoading = MutableLiveData(false)
    val themeLoading: LiveData<Boolean> = _themeLoading

    private val _playlistSongs = MutableLiveData<List<Song>>()
    val playlistSongs: LiveData<List<Song>> = _playlistSongs

    private val _weeklyHotSongs = MutableLiveData<List<Song>>()
    val weeklyHotSongs: LiveData<List<Song>> = _weeklyHotSongs

    private val _weeklyHotLoading = MutableLiveData(false)
    val weeklyHotLoading: LiveData<Boolean> = _weeklyHotLoading

    private val _newestAlbums = MutableLiveData<List<NewestAlbum>>(emptyList())
    val newestAlbums: LiveData<List<NewestAlbum>> = _newestAlbums

    private val _searchResults = MutableLiveData<List<Song>>()
    val searchResults: LiveData<List<Song>> = _searchResults

    private val _currentPlaylist = MutableLiveData<Playlist?>()
    val currentPlaylist: LiveData<Playlist?> = _currentPlaylist

    private val _currentSong = MutableLiveData<Song?>()
    val currentSong: LiveData<Song?> = _currentSong

    private val _queue = MutableLiveData<List<Song>>(emptyList())
    val queue: LiveData<List<Song>> = _queue

    private val _recentlyPlayed = MutableLiveData<List<Song>>(emptyList())
    val recentlyPlayed: LiveData<List<Song>> = _recentlyPlayed

    private val _playlistViewMode = MutableLiveData(PlaylistViewMode.RECENT)
    val playlistViewMode: LiveData<PlaylistViewMode> = _playlistViewMode

    private val _canSkipPrevious = MutableLiveData(false)
    val canSkipPrevious: LiveData<Boolean> = _canSkipPrevious

    private val _isLoading = MutableLiveData(false)
    val isLoading: LiveData<Boolean> = _isLoading

    private val _error = MutableLiveData<String>()
    val error: LiveData<String> = _error

    init {
        viewModelScope.launch { PlaybackCoordinator.currentSong.collect { _currentSong.value = it } }
        viewModelScope.launch { PlaybackCoordinator.queue.collect { _queue.value = it } }
        viewModelScope.launch { PlaybackCoordinator.recentlyPlayed.collect { _recentlyPlayed.value = it } }
        viewModelScope.launch { PlaybackCoordinator.playlistViewMode.collect { _playlistViewMode.value = it } }
        viewModelScope.launch { PlaybackCoordinator.canSkipPrevious.collect { _canSkipPrevious.value = it } }
        viewModelScope.launch { PlaybackCoordinator.isLoading.collect { _isLoading.value = it } }
        viewModelScope.launch { PlaybackCoordinator.error.collect { _error.value = it } }
    }

    fun prefetchDiscover(limit: Int = 10, forceRefresh: Boolean = false) {
        viewModelScope.launch {
            _isLoading.value = true
            _weeklyHotLoading.value = true
            try {
                supervisorScope {
                    val dailyDeferred = async { repository.getDailyRecommend(forceRefresh = forceRefresh) }
                    val weeklyDeferred = async {
                        repository.getWeeklyHotNewSongs(
                            limit = limit,
                            device = "mobile",
                            forceRefresh = forceRefresh
                        )
                    }
                    val newestDeferred = async { albumRepository.getNewestAlbums(forceRefresh = forceRefresh) }

                    dailyDeferred.await()
                        .onSuccess { _dailyRecommend.value = it }
                        .onFailure { _error.value = it.message ?: "获取每日推荐失败" }

                    weeklyDeferred.await()
                        .onSuccess { _weeklyHotSongs.value = it }
                        .onFailure { _error.value = it.message ?: "获取本周热门失败" }

                    newestDeferred.await()
                        .onSuccess { _newestAlbums.value = it }
                        .onFailure { _error.value = it.message ?: "获取最新专辑失败" }
                }
            } finally {
                _isLoading.value = false
                _weeklyHotLoading.value = false
            }
        }
    }

    fun loadDailyRecommend(forceRefresh: Boolean = false) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.getDailyRecommend(forceRefresh = forceRefresh)
                .onSuccess { _dailyRecommend.value = it }
                .onFailure { _error.value = it.message ?: "获取每日推荐失败" }
            _isLoading.value = false
        }
    }

    fun loadWeeklyHotSongs(limit: Int = 10, forceRefresh: Boolean = false) {
        viewModelScope.launch {
            _weeklyHotLoading.value = true
            repository.getWeeklyHotNewSongs(
                limit = limit,
                device = "mobile",
                forceRefresh = forceRefresh
            )
                .onSuccess { _weeklyHotSongs.value = it }
                .onFailure { _error.value = it.message ?: "获取本周热门失败" }
            _weeklyHotLoading.value = false
        }
    }

    fun loadNewestAlbums(forceRefresh: Boolean = false) {
        viewModelScope.launch {
            albumRepository.getNewestAlbums(forceRefresh = forceRefresh)
                .onSuccess { _newestAlbums.value = it }
                .onFailure { _error.value = it.message ?: "获取最新专辑失败" }
        }
    }

    fun loadTopLists(forceRefresh: Boolean = false) {
        viewModelScope.launch {
            repository.getTopLists(forceRefresh = forceRefresh)
                .onSuccess { _topLists.value = it }
                .onFailure { _error.value = it.message ?: "获取榜单失败" }
        }
    }

    fun loadTopPlaylists(
        category: String? = "",
        limit: Int = 42,
        offset: Int = 0,
        forceRefresh: Boolean = false
    ) {
        viewModelScope.launch {
            repository.getTopPlaylists(
                category = category,
                limit = limit,
                offset = offset,
                device = "mobile",
                forceRefresh = forceRefresh
            )
                .onSuccess { _topPlaylists.value = it }
                .onFailure { _error.value = it.message ?: "获取歌单失败" }
        }
    }

    fun loadPlaylistCategories(device: String = "mobile", forceRefresh: Boolean = false) {
        viewModelScope.launch {
            repository.getPlaylistCategories(device = device, forceRefresh = forceRefresh)
                .onSuccess { catalog ->
                    _playlistCategories.value = listOf(PlaylistCategory.All) + catalog.categories
                }
                .onFailure { _error.value = it.message ?: "获取歌单分类失败" }
        }
    }

    fun loadSectionPlaylists(
        categoriesByGroupId: Map<Int, String>,
        limit: Int = 12,
        forceRefresh: Boolean = false
    ) {
        viewModelScope.launch {
            try {
                setAllGroupLoading(true)
                supervisorScope {
                    val tasks = categoriesByGroupId
                        .filterValues { it.isNotBlank() }
                        .map { (groupId, category) ->
                            async {
                                groupId to repository.getTopPlaylists(
                                    category = category,
                                    limit = limit,
                                    offset = 0,
                                    device = "mobile",
                                    forceRefresh = forceRefresh
                                )
                            }
                        }

                    tasks.forEach { deferred ->
                        val (groupId, result) = deferred.await()
                        result
                            .onSuccess { playlists ->
                                when (groupId) {
                                    0 -> _languagePlaylists.value = playlists
                                    1 -> _stylePlaylists.value = playlists
                                    2 -> _scenePlaylists.value = playlists
                                    3 -> _emotionPlaylists.value = playlists
                                    4 -> _themePlaylists.value = playlists
                                }
                            }
                            .onFailure { _error.value = it.message ?: "获取歌单失败" }
                    }
                }
            } finally {
                setAllGroupLoading(false)
            }
        }
    }

    fun loadPlaylistDetail(playlist: Playlist, forceRefresh: Boolean = false) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.getPlaylistDetail(playlist.id, forceRefresh = forceRefresh)
                .onSuccess { (loadedPlaylist, songs) ->
                    _currentPlaylist.value = loadedPlaylist
                    _playlistSongs.value = songs
                }
                .onFailure { _error.value = it.message ?: "获取歌单详情失败" }
            _isLoading.value = false
        }
    }

    fun loadPlaylistDetailById(playlistId: String, forceRefresh: Boolean = false) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.getPlaylistDetail(playlistId, forceRefresh = forceRefresh)
                .onSuccess { (loadedPlaylist, songs) ->
                    _currentPlaylist.value = loadedPlaylist
                    _playlistSongs.value = songs
                }
                .onFailure { _error.value = it.message ?: "获取歌单详情失败" }
            _isLoading.value = false
        }
    }

    fun loadGroupPlaylists(
        groupId: Int,
        category: String,
        limit: Int = 12,
        forceRefresh: Boolean = false
    ) {
        val cat = category.trim()
        if (cat.isBlank()) return

        viewModelScope.launch {
            setGroupLoading(groupId, true)
            try {
                repository.getTopPlaylists(
                    category = cat,
                    limit = limit,
                    offset = 0,
                    device = "mobile",
                    forceRefresh = forceRefresh
                )
                    .onSuccess { playlists ->
                        when (groupId) {
                            0 -> _languagePlaylists.value = playlists
                            1 -> _stylePlaylists.value = playlists
                            2 -> _scenePlaylists.value = playlists
                            3 -> _emotionPlaylists.value = playlists
                            4 -> _themePlaylists.value = playlists
                        }
                    }
                    .onFailure { _error.value = it.message ?: "获取歌单失败" }
            } finally {
                setGroupLoading(groupId, false)
            }
        }
    }

    private fun setAllGroupLoading(loading: Boolean) {
        _languageLoading.value = loading
        _styleLoading.value = loading
        _sceneLoading.value = loading
        _emotionLoading.value = loading
        _themeLoading.value = loading
    }

    private fun setGroupLoading(groupId: Int, loading: Boolean) {
        when (groupId) {
            0 -> _languageLoading.value = loading
            1 -> _styleLoading.value = loading
            2 -> _sceneLoading.value = loading
            3 -> _emotionLoading.value = loading
            4 -> _themeLoading.value = loading
        }
    }

    fun searchSongs(keywords: String) {
        viewModelScope.launch {
            _isLoading.value = true
            repository.searchSongs(keywords)
                .onSuccess { _searchResults.value = it }
                .onFailure { _error.value = it.message ?: "搜索歌曲失败" }
            _isLoading.value = false
        }
    }

    fun playSong(song: Song) = PlaybackCoordinator.playSong(song)

    fun playStandaloneSong(song: Song) = PlaybackCoordinator.playStandaloneSong(song)

    fun restorePreviewSong(song: Song) = PlaybackCoordinator.restorePreviewSong(song)

    fun playFromList(songs: List<Song>, song: Song) = PlaybackCoordinator.playFromList(songs, song)

    fun enqueue(song: Song) = PlaybackCoordinator.enqueue(song)

    fun enqueueNext(song: Song) = PlaybackCoordinator.enqueueNext(song)

    fun resolveSongUrl(song: Song, onResult: (Result<String>) -> Unit) {
        viewModelScope.launch {
            val cachedUrl = song.url?.trim().orEmpty()
            if (cachedUrl.isNotBlank()) {
                onResult(Result.success(cachedUrl))
                return@launch
            }
            onResult(repository.getSongUrl(song.id))
        }
    }

    fun reloadCurrentSongForAudioQualityChange() {
        PlaybackCoordinator.reloadCurrentSongForAudioQualityChange()
    }

    fun skipNext(): Boolean = PlaybackCoordinator.skipNext()

    fun skipPrevious(): Boolean = PlaybackCoordinator.skipPrevious()

    fun playFromQueue(songId: String) = PlaybackCoordinator.playFromQueue(songId)

    fun playFromRecent(songId: String) = PlaybackCoordinator.playFromRecent(songId)

    fun removeFromQueue(songId: String) = PlaybackCoordinator.removeFromQueue(songId)

    fun removeFromRecentlyPlayed(songId: String) = PlaybackCoordinator.removeFromRecentlyPlayed(songId)

    fun clearQueue() = PlaybackCoordinator.clearQueue()

    fun clearNowPlaying() = PlaybackCoordinator.clearNowPlaying()

    fun resetPlayback() = PlaybackCoordinator.resetPlayback()
}
