package com.music.player.playback

import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import com.music.player.data.model.Song
import com.music.player.data.repository.MusicRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

object PlaybackCoordinator {

    private const val TAG = "PlaybackCoordinator"
    private const val MAX_HISTORY = 100
    private const val EXTRA_SONG_ID = "song_id"
    private const val MAX_URL_CACHE_SIZE = 200

    private val repository = MusicRepository()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val navigationHistory = ArrayDeque<Song>()
    private var prepareJob: Job? = null
    private var lyricsJob: Job? = null
    private var prepareToken: Long = 0L
    private var lastStartElapsedMs: Long = 0L

    private val songUrlCache = object : LinkedHashMap<String, String>(MAX_URL_CACHE_SIZE, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>): Boolean {
            return size > MAX_URL_CACHE_SIZE
        }
    }

    private val _currentSong = MutableStateFlow<Song?>(null)
    val currentSong: StateFlow<Song?> = _currentSong.asStateFlow()

    private val _queue = MutableStateFlow<List<Song>>(emptyList())
    val queue: StateFlow<List<Song>> = _queue.asStateFlow()

    private val _canSkipPrevious = MutableStateFlow(false)
    val canSkipPrevious: StateFlow<Boolean> = _canSkipPrevious.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableSharedFlow<String>(extraBufferCapacity = 1)
    val error = _error.asSharedFlow()

    private val _playerAttached = MutableStateFlow(false)
    val playerAttached: StateFlow<Boolean> = _playerAttached.asStateFlow()

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var player: Player? = null

    @Volatile
    private var pendingPreparedSong: Song? = null

    fun init(context: Context) {
        if (appContext != null) return
        appContext = context.applicationContext
        PlaybackService.start(appContext!!)
    }

    fun attachPlayer(context: Context, player: Player) {
        appContext = context.applicationContext
        this.player = player
        _playerAttached.value = true

        // Apply recommended attributes even if caller didn't.
        if (player is androidx.media3.exoplayer.ExoPlayer) {
            val attributes = AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                .build()
            player.setAudioAttributes(attributes, true)
            player.setHandleAudioBecomingNoisy(true)
        }

        pendingPreparedSong?.let {
            pendingPreparedSong = null
            playPreparedSong(it)
        }
    }

    fun playerOrNull(): Player? = player

    fun hasNext(): Boolean = _queue.value.isNotEmpty()

    fun hasPrevious(): Boolean = navigationHistory.isNotEmpty()

    fun playSong(song: Song) {
        startPlayback(song, recordHistory = true)
    }

    fun playFromList(songs: List<Song>, song: Song) {
        val index = songs.indexOfFirst { it.id == song.id }
        if (index < 0) {
            playSong(song)
            return
        }

        cancelPrepare()
        navigationHistory.clear()
        songs.take(index).forEach { navigationHistory.addLast(it) }
        _canSkipPrevious.value = navigationHistory.isNotEmpty()

        val upcoming = songs.drop(index + 1)
            .filterNot { it.id == song.id }
            .distinctBy { it.id }
        _queue.value = upcoming

        startPlayback(song, recordHistory = false)
    }

    fun enqueue(song: Song) {
        val updated = _queue.value.orEmpty()
            .filterNot { it.id == song.id } + song
        _queue.value = updated
    }

    fun enqueueNext(song: Song) {
        val updated = listOf(song) + _queue.value.orEmpty()
            .filterNot { it.id == song.id }
        _queue.value = updated
    }

    fun skipNext(): Boolean {
        val queueSnapshot = _queue.value.orEmpty()
        val next = queueSnapshot.firstOrNull() ?: return false
        _queue.value = queueSnapshot.drop(1)
        startPlayback(next, recordHistory = true)
        return true
    }

    fun skipPrevious(): Boolean {
        if (navigationHistory.isEmpty()) return false
        val previous = navigationHistory.removeLast()
        val current = _currentSong.value
        if (current != null) {
            enqueueNext(current)
        }
        _canSkipPrevious.value = navigationHistory.isNotEmpty()
        startPlayback(previous, recordHistory = false)
        return true
    }

    fun playFromQueue(songId: String) {
        val queueSnapshot = _queue.value.orEmpty()
        val song = queueSnapshot.firstOrNull { it.id == songId } ?: return
        _queue.value = queueSnapshot.filterNot { it.id == songId }
        startPlayback(song, recordHistory = true)
    }

    fun removeFromQueue(songId: String) {
        _queue.value = _queue.value.orEmpty().filterNot { it.id == songId }
    }

    fun clearQueue() {
        _queue.value = emptyList()
    }

    fun clearNowPlaying() {
        cancelPrepare()
        _currentSong.value = null
    }

    fun resetPlayback() {
        cancelPrepare()
        navigationHistory.clear()
        _canSkipPrevious.value = false
        _queue.value = emptyList()
        _currentSong.value = null
        _isLoading.value = false
        player?.stop()
        player?.clearMediaItems()
    }

    fun onPlaybackEndedAutoAdvance() {
        skipNext()
    }

    private fun startPlayback(song: Song, recordHistory: Boolean) {
        val current = _currentSong.value
        if (recordHistory && current != null && current.id != song.id) {
            navigationHistory.addLast(current)
            if (navigationHistory.size > MAX_HISTORY) {
                navigationHistory.removeFirst()
            }
            _canSkipPrevious.value = true
        }

        prepareJob?.cancel()
        lyricsJob?.cancel()

        val token = ++prepareToken
        lastStartElapsedMs = SystemClock.elapsedRealtime()
        prepareJob = scope.launch {
            _isLoading.value = true
            try {
                ensureServiceRunning()

                val urlStart = SystemClock.elapsedRealtime()
                val urlResult = withContext(Dispatchers.IO) { resolveSongUrl(song) }
                val urlCost = SystemClock.elapsedRealtime() - urlStart
                val fastUrl = urlResult.getOrNull()?.trim().orEmpty()
                if (urlResult.isSuccess && fastUrl.isNotBlank()) {
                    if (prepareToken != token) return@launch

                    val prepared = song.copy(url = fastUrl)
                    _currentSong.value = prepared
                    Log.d(TAG, "resolved url in ${urlCost}ms (fast path), songId=${song.id}")
                    playPreparedSong(prepared)

                    prefetchNextUrl(token)
                    fetchLyricsInBackground(prepared, token)
                } else {
                    // Fallback to legacy prepare path (may include additional server-side requirements).
                    Log.d(TAG, "url fast path failed in ${urlCost}ms, fallback prepareSong(), songId=${song.id}")
                    repository.prepareSong(song)
                        .onSuccess { prepared ->
                            if (prepareToken == token) {
                                prepared.url?.trim()?.takeIf { it.isNotBlank() }?.let { putCachedUrl(prepared.id, it) }
                                _currentSong.value = prepared
                                playPreparedSong(prepared)
                            }
                        }
                        .onFailure { throwable ->
                            if (throwable !is CancellationException && prepareToken == token) {
                                _error.tryEmit(throwable.message ?: "鎾斁澶辫触")
                            }
                        }
                }
            } finally {
                if (prepareToken == token) {
                    _isLoading.value = false
                }
            }
        }
    }

    private suspend fun resolveSongUrl(song: Song): Result<String> {
        val existing = song.url?.trim().orEmpty()
        if (existing.isNotBlank()) return Result.success(existing)

        val cached = getCachedUrl(song.id)
        if (cached != null) return Result.success(cached)

        val fetched = repository.getSongUrl(song.id)
        fetched.getOrNull()?.trim()?.takeIf { it.isNotBlank() }?.let { putCachedUrl(song.id, it) }
        return fetched
    }

    private fun fetchLyricsInBackground(prepared: Song, token: Long) {
        lyricsJob?.cancel()
        lyricsJob = scope.launch {
            val lyric = withContext(Dispatchers.IO) { repository.getLyrics(prepared.id).getOrNull() }
                ?.trim()
                .orEmpty()
            if (lyric.isBlank()) return@launch
            if (prepareToken != token) return@launch

            val current = _currentSong.value ?: return@launch
            if (current.id != prepared.id) return@launch
            _currentSong.value = current.copy(lyric = lyric)
        }
    }

    private fun prefetchNextUrl(token: Long) {
        val next = _queue.value.firstOrNull() ?: return
        if (getCachedUrl(next.id) != null) return
        scope.launch {
            if (prepareToken != token) return@launch
            withContext(Dispatchers.IO) { resolveSongUrl(next) }
        }
    }

    @Synchronized
    private fun getCachedUrl(songId: String): String? = songUrlCache[songId]

    @Synchronized
    private fun putCachedUrl(songId: String, url: String) {
        songUrlCache[songId] = url
    }

    private fun playPreparedSong(song: Song) {
        val mediaUrl = song.url?.trim().orEmpty()
        if (mediaUrl.isBlank()) {
            _error.tryEmit("鎾斁鍦板潃涓虹┖")
            return
        }

        val activePlayer = player
        if (activePlayer == null) {
            pendingPreparedSong = song
            return
        }

        val sinceTap = (SystemClock.elapsedRealtime() - lastStartElapsedMs).coerceAtLeast(0L)
        Log.d(TAG, "playPreparedSong after ${sinceTap}ms, songId=${song.id}")

        val title = song.name
        val artist = song.artists.joinToString(", ") { it.name }
        val artwork = song.album.picUrl.trim().takeIf { it.isNotBlank() }?.let { Uri.parse(it) }

        val metadata = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
            .setArtworkUri(artwork)
            .build()

        val extras = Bundle().apply {
            putString(EXTRA_SONG_ID, song.id)
        }

        val mediaItem = MediaItem.Builder()
            .setMediaId(song.id)
            .setUri(Uri.parse(mediaUrl))
            .setMediaMetadata(metadata)
            .setTag(extras)
            .build()

        activePlayer.setMediaItem(mediaItem)
        activePlayer.prepare()
        activePlayer.play()
    }

    private fun ensureServiceRunning() {
        val context = appContext ?: return
        PlaybackService.start(context)
    }

    private fun cancelPrepare() {
        prepareJob?.cancel()
        prepareJob = null
        lyricsJob?.cancel()
        lyricsJob = null
        prepareToken += 1
    }
}
