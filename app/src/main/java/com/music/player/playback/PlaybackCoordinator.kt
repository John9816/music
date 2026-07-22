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
import androidx.media3.common.util.UnstableApi
import com.music.player.data.model.Song
import com.music.player.data.repository.MusicRepository
import com.music.player.data.settings.AudioQualityPreferences
import com.music.player.data.settings.AppSettings
import com.music.player.ui.util.ImageUrl
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
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

object PlaybackCoordinator {

    enum class PlaylistViewMode {
        RECENT,
        QUEUE
    }

    private const val TAG = "PlaybackCoordinator"
    private const val MAX_HISTORY = 100
    private const val EXTRA_SONG_ID = "song_id"
    private const val MAX_URL_CACHE_SIZE = 200
    private const val RECOVERY_WINDOW_MS = 45_000L
    private const val MAX_RECOVERY_ATTEMPTS = 1
    // Lyrics are independent of audio URL resolution and must start as soon as playback begins.
    private const val LYRICS_FETCH_DELAY_MS = 0L
    private const val NEXT_URL_PREFETCH_DELAY_MS = 15_000L
    private const val PERSIST_DEBOUNCE_MS = 400L
    private const val POSITION_PERSIST_INTERVAL_MS = 5_000L

    private val repository = MusicRepository()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val navigationHistory = ArrayDeque<Song>()
    private var prepareJob: Job? = null
    private var lyricsJob: Job? = null
    private var sleepTimerJob: Job? = null
    private var persistJob: Job? = null
    private var positionPersistJob: Job? = null
    private var prepareToken: Long = 0L
    private var lastStartElapsedMs: Long = 0L
    private var lastRecoverySongId: String? = null
    private var lastRecoveryAtMs: Long = 0L
    private var recoveryAttemptsForSong: Int = 0
    /** Position to seek after cold-start restore (stream URLs are re-fetched). */
    private var restoredPositionMs: Long = 0L
    private var restoredPlayWhenReady: Boolean = false
    private var sessionRestored: Boolean = false
    private var stateStore: PlaybackStateStore? = null

    private val songUrlCache = object : LinkedHashMap<String, String>(MAX_URL_CACHE_SIZE, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>): Boolean {
            return size > MAX_URL_CACHE_SIZE
        }
    }

    private val _currentSong = MutableStateFlow<Song?>(null)
    val currentSong: StateFlow<Song?> = _currentSong.asStateFlow()

    private val _queue = MutableStateFlow<List<Song>>(emptyList())
    val queue: StateFlow<List<Song>> = _queue.asStateFlow()

    private val _recentlyPlayed = MutableStateFlow<List<Song>>(emptyList())
    val recentlyPlayed: StateFlow<List<Song>> = _recentlyPlayed.asStateFlow()

    private val _playlistViewMode = MutableStateFlow(PlaylistViewMode.RECENT)
    val playlistViewMode: StateFlow<PlaylistViewMode> = _playlistViewMode.asStateFlow()

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

    @androidx.annotation.OptIn(markerClass = [UnstableApi::class])
    fun init(context: Context) {
        if (appContext != null) return
        appContext = context.applicationContext
        MusicRepository.setApplicationContext(appContext!!)
        stateStore = PlaybackStateStore(appContext!!)
        restoreSessionFromDisk()
        PlaybackService.start(appContext!!)
        restoreSleepTimer()
    }

    fun attachPlayer(context: Context, player: Player) {
        appContext = context.applicationContext
        MusicRepository.setApplicationContext(appContext!!)
        if (stateStore == null) {
            stateStore = PlaybackStateStore(appContext!!)
        }
        this.player = player
        _playerAttached.value = true
        restoreSleepTimer()

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
            playPreparedSong(it, restoredPositionMs, restoredPlayWhenReady)
            restoredPositionMs = 0L
            restoredPlayWhenReady = false
        } ?: resumeRestoredCurrentIfNeeded()

        startPositionPersistenceLoop()
    }

    /**
     * Detaches the current player. Called when the owning service is being destroyed and the
     * player is about to be released, so the coordinator stops referencing a released instance.
     */
    fun detachPlayer(player: Player) {
        // Only clear if the released player is still the one we hold; a newer service may have
        // already re-attached a fresh player.
        if (this.player === player) {
            persistSessionNow()
            stopPositionPersistenceLoop()
            this.player = null
            _playerAttached.value = false
        }
    }

    /** Call when the process is going away (e.g. service destroy) to flush progress. */
    fun persistSessionNow() {
        val store = stateStore ?: appContext?.let { PlaybackStateStore(it).also { s -> stateStore = s } }
            ?: return
        val current = _currentSong.value
        val position = player?.currentPosition?.coerceAtLeast(0L) ?: restoredPositionMs
        val playWhenReady = player?.playWhenReady ?: restoredPlayWhenReady
        if (current == null && _queue.value.isEmpty() && navigationHistory.isEmpty()) {
            store.clear()
            return
        }
        val snapshot = PlaybackStateStore.Snapshot(
            currentSong = current?.let(PlaybackStateStore.SongDto::from),
            positionMs = position.coerceAtLeast(0L),
            // Never auto-start audio after cold launch; user taps play. Still keep progress.
            playWhenReady = false,
            queue = _queue.value.map(PlaybackStateStore.SongDto::from),
            history = navigationHistory.toList().map(PlaybackStateStore.SongDto::from),
            viewMode = _playlistViewMode.value.name
        )
        // Capture last known position for the next attach even if we force playWhenReady=false.
        restoredPositionMs = snapshot.positionMs
        restoredPlayWhenReady = false
        store.save(snapshot)
    }

    private fun schedulePersistSession() {
        persistJob?.cancel()
        persistJob = scope.launch {
            delay(PERSIST_DEBOUNCE_MS)
            persistSessionNow()
        }
    }

    private fun startPositionPersistenceLoop() {
        stopPositionPersistenceLoop()
        positionPersistJob = scope.launch {
            while (true) {
                delay(POSITION_PERSIST_INTERVAL_MS)
                val p = player ?: continue
                if (p.isPlaying || p.playWhenReady) {
                    persistSessionNow()
                }
            }
        }
    }

    private fun stopPositionPersistenceLoop() {
        positionPersistJob?.cancel()
        positionPersistJob = null
    }

    private fun restoreSessionFromDisk() {
        if (sessionRestored) return
        sessionRestored = true
        runCatching {
            val snapshot = stateStore?.load() ?: return
            val current = snapshot.currentSong?.toSong()
            val queue = snapshot.queue.orEmpty().map { it.toSong() }
            val history = snapshot.history.orEmpty().map { it.toSong() }

            navigationHistory.clear()
            history.forEach { navigationHistory.addLast(it) }
            _canSkipPrevious.value = navigationHistory.isNotEmpty()
            syncRecentlyPlayed()
            _queue.value = queue
            _playlistViewMode.value = runCatching {
                PlaylistViewMode.valueOf(snapshot.viewMode.orEmpty())
            }.getOrDefault(
                if (queue.isNotEmpty()) PlaylistViewMode.QUEUE else PlaylistViewMode.RECENT
            )
            restoredPositionMs = snapshot.positionMs.coerceAtLeast(0L)
            restoredPlayWhenReady = false
            if (current != null && current.id.isNotBlank()) {
                _currentSong.value = current
                // UI-only restore on cold start. Do not auto network/prepare — user taps play.
                pendingPreparedSong = null
                Log.i(
                    TAG,
                    "restored session songId=${current.id} pos=${restoredPositionMs}ms queue=${queue.size}"
                )
            }
        }.onFailure {
            Log.e(TAG, "restoreSessionFromDisk failed, clearing store", it)
            stateStore?.clear()
            restoredPositionMs = 0L
            restoredPlayWhenReady = false
            pendingPreparedSong = null
        }
    }

    /**
     * After player attaches, only restore if we already have a fully prepared pending item.
     * Cold-start disk restore is UI-only; preparing the stream is deferred until the user taps play
     * so a bad URL / network failure cannot crash launch.
     */
    private fun resumeRestoredCurrentIfNeeded() {
        // Intentionally no-op for disk restore. Mini-player play button calls playSong() which
        // re-resolves the URL and seeks via restoredPositionMs when appropriate.
    }

    fun playerOrNull(): Player? = player

    fun hasNext(): Boolean = _queue.value.isNotEmpty()

    fun hasPrevious(): Boolean = navigationHistory.isNotEmpty()

    fun playSong(song: Song) {
        // Re-tapping the restored current song should keep progress; new songs start at 0.
        val sameAsCurrent = _currentSong.value?.id == song.id
        if (!sameAsCurrent) {
            restoredPositionMs = 0L
        }
        val resumeAt = if (sameAsCurrent) restoredPositionMs.coerceAtLeast(0L) else 0L
        startPlayback(
            song = song,
            recordHistory = !sameAsCurrent,
            startPositionMs = resumeAt,
            shouldAutoPlay = true
        )
    }

    fun reloadCurrentSongForAudioQualityChange() {
        val song = _currentSong.value ?: return
        val activePlayer = player
        val resumePositionMs = activePlayer?.currentPosition?.coerceAtLeast(0L) ?: 0L
        val shouldAutoPlay = activePlayer?.playWhenReady ?: true

        prepareJob?.cancel()
        lyricsJob?.cancel()

        val token = ++prepareToken
        lastStartElapsedMs = SystemClock.elapsedRealtime()
        prepareJob = scope.launch {
            _isLoading.value = true
            try {
                ensureServiceRunning()

                val refreshedSong = song.copy(url = null)
                val urlStart = SystemClock.elapsedRealtime()
                val urlResult = withContext(Dispatchers.IO) {
                    resolveSongUrl(refreshedSong, forceRefresh = true)
                }
                val urlCost = SystemClock.elapsedRealtime() - urlStart
                val refreshedUrl = urlResult.getOrNull()?.trim().orEmpty()

                if (prepareToken != token) return@launch

                if (urlResult.isSuccess && refreshedUrl.isNotBlank()) {
                    val previousSong = song
                    val prepared = song.copy(url = refreshedUrl)
                    _currentSong.value = prepared
                    Log.d(TAG, "reloaded url in ${urlCost}ms, songId=${song.id}")
                    playPreparedSongWithFallback(
                        previousSong = previousSong,
                        nextSong = prepared,
                        startPositionMs = resumePositionMs,
                        shouldAutoPlay = shouldAutoPlay,
                        token = token
                    )
                    schedulePostStartWork(prepared, token)
                } else {
                    _error.tryEmit(urlResult.exceptionOrNull()?.message ?: "切换音质失败")
                }
            } finally {
                if (prepareToken == token) {
                    _isLoading.value = false
                }
            }
        }
    }

    fun setSleepTimer(minutes: Long) {
        val context = appContext ?: return
        val endTime = AppSettings.setSleepTimer(context, minutes)
        scheduleSleepTimer(endTime)
    }

    fun cancelSleepTimer() {
        sleepTimerJob?.cancel()
        sleepTimerJob = null
        appContext?.let(AppSettings::clearSleepTimer)
    }

    private fun restoreSleepTimer() {
        val context = appContext ?: return
        val endTime = AppSettings.sleepTimerEndTime(context)
        if (endTime <= 0L) return
        scheduleSleepTimer(endTime)
    }

    private fun scheduleSleepTimer(endTimeMs: Long) {
        val context = appContext ?: return
        sleepTimerJob?.cancel()
        val remainingMs = endTimeMs - System.currentTimeMillis()
        if (remainingMs <= 0L) {
            player?.pause()
            AppSettings.clearSleepTimer(context)
            sleepTimerJob = null
            return
        }
        sleepTimerJob = scope.launch {
            delay(remainingMs)
            player?.pause()
            AppSettings.clearSleepTimer(context)
            sleepTimerJob = null
        }
    }

    fun playStandaloneSong(song: Song) {
        restoredPositionMs = 0L
        _queue.value = emptyList()
        _playlistViewMode.value = PlaylistViewMode.RECENT
        startPlayback(song, recordHistory = true)
        schedulePersistSession()
    }

    fun playFromList(songs: List<Song>, song: Song) {
        val index = songs.indexOfFirst { it.id == song.id }
        if (index < 0) {
            playStandaloneSong(song)
            return
        }

        cancelPrepare()
        restoredPositionMs = 0L
        navigationHistory.clear()
        songs.take(index).forEach { navigationHistory.addLast(it) }
        _canSkipPrevious.value = navigationHistory.isNotEmpty()
        syncRecentlyPlayed()

        val upcoming = songs.drop(index + 1)
            .filterNot { it.id == song.id }
            .distinctBy { it.id }
        _queue.value = upcoming
        _playlistViewMode.value = PlaylistViewMode.QUEUE

        startPlayback(song, recordHistory = false)
        schedulePersistSession()
    }

    fun enqueue(song: Song) {
        val updated = _queue.value.orEmpty()
            .filterNot { it.id == song.id } + song
        _queue.value = updated
        _playlistViewMode.value = PlaylistViewMode.QUEUE
        schedulePersistSession()
    }

    fun enqueueNext(song: Song) {
        val updated = listOf(song) + _queue.value.orEmpty()
            .filterNot { it.id == song.id }
        _queue.value = updated
        _playlistViewMode.value = PlaylistViewMode.QUEUE
        schedulePersistSession()
    }

    fun skipNext(): Boolean {
        val queueSnapshot = _queue.value.orEmpty()
        val next = queueSnapshot.firstOrNull() ?: return false
        restoredPositionMs = 0L
        _queue.value = queueSnapshot.drop(1)
        _playlistViewMode.value = if (_queue.value.isEmpty()) PlaylistViewMode.RECENT else PlaylistViewMode.QUEUE
        startPlayback(next, recordHistory = true)
        schedulePersistSession()
        return true
    }

    fun skipPrevious(): Boolean {
        if (navigationHistory.isEmpty()) return false
        val previous = navigationHistory.removeLast()
        val current = _currentSong.value
        if (current != null) {
            enqueueNext(current)
        }
        restoredPositionMs = 0L
        _canSkipPrevious.value = navigationHistory.isNotEmpty()
        startPlayback(previous, recordHistory = false)
        schedulePersistSession()
        return true
    }

    fun playFromQueue(songId: String) {
        val queueSnapshot = _queue.value.orEmpty()
        val song = queueSnapshot.firstOrNull { it.id == songId } ?: return
        restoredPositionMs = 0L
        _queue.value = queueSnapshot.filterNot { it.id == songId }
        _playlistViewMode.value = if (_queue.value.isEmpty()) PlaylistViewMode.RECENT else PlaylistViewMode.QUEUE
        startPlayback(song, recordHistory = true)
        schedulePersistSession()
    }

    fun playFromRecent(songId: String) {
        val song = navigationHistory.lastOrNull { it.id == songId } ?: return
        rebuildNavigationHistory(
            navigationHistory.filterNot { it.id == songId }
        )
        restoredPositionMs = 0L
        _queue.value = emptyList()
        _playlistViewMode.value = PlaylistViewMode.RECENT
        startPlayback(song, recordHistory = true)
        schedulePersistSession()
    }

    fun removeFromQueue(songId: String) {
        _queue.value = _queue.value.orEmpty().filterNot { it.id == songId }
        if (_queue.value.isEmpty()) {
            _playlistViewMode.value = PlaylistViewMode.RECENT
        }
        schedulePersistSession()
    }

    fun clearQueue() {
        _queue.value = emptyList()
        _playlistViewMode.value = PlaylistViewMode.RECENT
        schedulePersistSession()
    }

    @Synchronized
    fun clearResolvedUrlCache() {
        songUrlCache.clear()
    }

    fun removeFromRecentlyPlayed(songId: String) {
        rebuildNavigationHistory(
            navigationHistory.filterNot { it.id == songId }
        )
    }

    fun clearNowPlaying() {
        cancelPrepare()
        _currentSong.value = null
        restoredPositionMs = 0L
        schedulePersistSession()
    }

    fun restorePreviewSong(song: Song) {
        if (_currentSong.value != null) return
        cancelPrepare()
        navigationHistory.clear()
        _canSkipPrevious.value = false
        syncRecentlyPlayed()
        _queue.value = emptyList()
        _playlistViewMode.value = PlaylistViewMode.RECENT
        pendingPreparedSong = null
        _isLoading.value = false
        restoredPositionMs = 0L
        _currentSong.value = song
        schedulePersistSession()
    }

    fun resetPlayback() {
        cancelPrepare()
        navigationHistory.clear()
        _canSkipPrevious.value = false
        syncRecentlyPlayed()
        _queue.value = emptyList()
        _playlistViewMode.value = PlaylistViewMode.RECENT
        _currentSong.value = null
        _isLoading.value = false
        restoredPositionMs = 0L
        restoredPlayWhenReady = false
        pendingPreparedSong = null
        player?.stop()
        player?.clearMediaItems()
        stateStore?.clear()
    }

    fun onPlaybackEndedAutoAdvance() {
        skipNext()
    }

    fun recoverCurrentPlayback(resumePositionMs: Long, reason: String) {
        val song = _currentSong.value ?: return
        val now = SystemClock.elapsedRealtime()
        if (lastRecoverySongId == song.id && now - lastRecoveryAtMs < RECOVERY_WINDOW_MS) {
            recoveryAttemptsForSong += 1
        } else {
            lastRecoverySongId = song.id
            lastRecoveryAtMs = now
            recoveryAttemptsForSong = 1
        }

        if (recoveryAttemptsForSong > MAX_RECOVERY_ATTEMPTS) {
            _error.tryEmit("当前歌曲播放不稳定，请切换音质后重试")
            return
        }

        prepareJob?.cancel()
        lyricsJob?.cancel()

        val token = ++prepareToken
        prepareJob = scope.launch {
            _isLoading.value = true
            try {
                val refreshed = song.copy(url = null)
                val urlResult = withContext(Dispatchers.IO) {
                    resolveSongUrl(refreshed, forceRefresh = true)
                }
                val refreshedUrl = urlResult.getOrNull()?.trim().orEmpty()
                if (prepareToken != token) return@launch

                if (urlResult.isSuccess && refreshedUrl.isNotBlank()) {
                    val prepared = song.copy(url = refreshedUrl)
                    _currentSong.value = prepared
                    playPreparedSong(
                        song = prepared,
                        startPositionMs = resumePositionMs,
                        shouldAutoPlay = true
                    )
                    _error.tryEmit(reason)
                } else {
                    _error.tryEmit(urlResult.exceptionOrNull()?.message ?: "恢复播放失败")
                }
            } finally {
                if (prepareToken == token) {
                    _isLoading.value = false
                }
            }
        }
    }

    private fun startPlayback(
        song: Song,
        recordHistory: Boolean,
        startPositionMs: Long = 0L,
        shouldAutoPlay: Boolean = true
    ) {
        lastRecoverySongId = null
        recoveryAttemptsForSong = 0
        lastRecoveryAtMs = 0L
        val current = _currentSong.value
        if (recordHistory && current != null && current.id != song.id) {
            navigationHistory.addLast(current)
            if (navigationHistory.size > MAX_HISTORY) {
                navigationHistory.removeFirst()
            }
            _canSkipPrevious.value = true
            syncRecentlyPlayed()
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
                    playPreparedSong(prepared, startPositionMs, shouldAutoPlay)
                    schedulePersistSession()

                    schedulePostStartWork(prepared, token)
                } else {
                    // Fallback to legacy prepare path (may include additional server-side requirements).
                    Log.d(TAG, "url fast path failed in ${urlCost}ms, fallback prepareSong(), songId=${song.id}")
                    repository.prepareSong(song)
                        .onSuccess { prepared ->
                            if (prepareToken == token) {
                                prepared.url?.trim()?.takeIf { it.isNotBlank() }
                                    ?.let { putCachedUrl(prepared.id, prepared.source, it) }
                                _currentSong.value = prepared
                                playPreparedSong(prepared, startPositionMs, shouldAutoPlay)
                                schedulePersistSession()
                                schedulePostStartWork(prepared, token)
                            }
                        }
                        .onFailure { throwable ->
                            if (throwable !is CancellationException && prepareToken == token) {
                                _error.tryEmit(throwable.message ?: "播放失败")
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

    private suspend fun resolveSongUrl(song: Song, forceRefresh: Boolean = false): Result<String> {
        val existing = song.url?.trim().orEmpty()
        if (!forceRefresh && existing.isNotBlank()) return Result.success(existing)

        val cached = getCachedUrl(song.id, song.source)
        if (!forceRefresh && cached != null) return Result.success(cached)

        val fetched = repository.getSongUrl(
            song.id,
            source = song.source,
            forceRefresh = forceRefresh
        )
        fetched.getOrNull()?.trim()?.takeIf { it.isNotBlank() }
            ?.let { putCachedUrl(song.id, song.source, it) }
        return fetched
    }

    private fun schedulePostStartWork(prepared: Song, token: Long) {
        if (prepared.lyric.isNullOrBlank()) {
            fetchLyricsInBackground(prepared, token)
        }
        prefetchNextUrl(token)
    }

    private fun fetchLyricsInBackground(prepared: Song, token: Long) {
        lyricsJob?.cancel()
        lyricsJob = scope.launch {
            delay(LYRICS_FETCH_DELAY_MS)
            if (prepareToken != token) return@launch
            val lyric = withContext(Dispatchers.IO) {
                repository.getLyrics(prepared.id, source = prepared.source).getOrNull()
            }
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
        if (getCachedUrl(next.id, next.source) != null) return
        scope.launch {
            delay(NEXT_URL_PREFETCH_DELAY_MS)
            if (prepareToken != token) return@launch
            withContext(Dispatchers.IO) { resolveSongUrl(next) }
        }
    }

    @Synchronized
    private fun getCachedUrl(songId: String, source: String): String? =
        songUrlCache[currentUrlCacheKey(songId, source)]

    @Synchronized
    private fun putCachedUrl(songId: String, source: String, url: String) {
        songUrlCache[currentUrlCacheKey(songId, source)] = url
    }

    private fun currentUrlCacheKey(songId: String, source: String): String {
        val level = appContext
            ?.let { AudioQualityPreferences.getPreferredLevel(it) }
            ?: AudioQualityPreferences.getPreferredLevel()
        return "$source|$songId|${level.storageValue}"
    }

    private fun playPreparedSongWithFallback(
        previousSong: Song,
        nextSong: Song,
        startPositionMs: Long,
        shouldAutoPlay: Boolean,
        token: Long,
        timeoutMs: Long = 5000L
    ) {
        val activePlayer = player
        if (activePlayer == null) {
            playPreparedSong(nextSong, startPositionMs, shouldAutoPlay)
            return
        }

        var settled = false
        lateinit var listener: Player.Listener

        // Detaches the listener without touching playback. Used when this switch has been
        // superseded by a newer request (token bumped): the newer request owns the player now,
        // so we must not revert, but we must still remove our listener to avoid leaking it.
        fun detach() {
            if (settled) return
            settled = true
            activePlayer.removeListener(listener)
        }

        fun settleSuccess() = detach()

        fun settleFailure() {
            if (settled) return
            settled = true
            activePlayer.removeListener(listener)
            _currentSong.value = previousSong
            playPreparedSong(previousSong, startPositionMs, shouldAutoPlay)
            _error.tryEmit("新音质播放失败，已恢复原音质")
        }

        listener = object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (prepareToken == token && playbackState == Player.STATE_READY) {
                    settleSuccess()
                }
            }

            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                if (prepareToken == token) {
                    settleFailure()
                }
            }
        }

        activePlayer.addListener(listener)
        playPreparedSong(nextSong, startPositionMs, shouldAutoPlay)

        scope.launch {
            delay(timeoutMs)
            if (settled) return@launch
            if (prepareToken == token) {
                // Still the active switch: revert if it never reached READY.
                if (activePlayer.playbackState != Player.STATE_READY) {
                    settleFailure()
                } else {
                    settleSuccess()
                }
            } else {
                // Superseded by a newer request; just remove our listener, don't revert.
                detach()
            }
        }
    }

    @androidx.annotation.OptIn(markerClass = [UnstableApi::class])
    private fun playPreparedSong(
        song: Song,
        startPositionMs: Long = 0L,
        shouldAutoPlay: Boolean = true
    ) {
        val mediaUrl = song.url?.trim().orEmpty()
        if (mediaUrl.isBlank()) {
            _error.tryEmit("播放地址为空")
            return
        }

        val activePlayer = player
        if (activePlayer == null) {
            pendingPreparedSong = song
            restoredPositionMs = startPositionMs.coerceAtLeast(0L)
            restoredPlayWhenReady = shouldAutoPlay
            return
        }

        val sinceTap = (SystemClock.elapsedRealtime() - lastStartElapsedMs).coerceAtLeast(0L)
        Log.d(TAG, "playPreparedSong after ${sinceTap}ms, songId=${song.id}")

        // Defensive: some endpoints may return partial song objects (e.g., missing album/picUrl/artists).
        // Avoid crashing on playback start.
        val title = song.name.ifBlank { "Unknown" }
        val artist = song.artists.orEmpty().joinToString(", ") { it.name }.ifBlank { "Unknown" }
        val album = song.album.name.takeIf { it.isNotBlank() }
        // Prefer HTTPS so the system media notification BitmapLoader can fetch artwork.
        val artworkUri = ImageUrl.bestQuality(song.album.picUrl)?.let { Uri.parse(it) }
        // duration from API helps the system QS media player show a progress bar
        // before (and if) the stream itself reports a duration.
        val durationMs = song.duration.takeIf { it > 0L }

        val metadataBuilder = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
            .setArtworkUri(artworkUri)
        if (album != null) {
            metadataBuilder.setAlbumTitle(album)
        }
        if (durationMs != null) {
            metadataBuilder.setDurationMs(durationMs)
        }
        val metadata = metadataBuilder.build()

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
        if (startPositionMs > 0L) {
            activePlayer.seekTo(startPositionMs)
            restoredPositionMs = startPositionMs
        }
        activePlayer.playWhenReady = shouldAutoPlay
        if (shouldAutoPlay) {
            activePlayer.play()
        } else {
            activePlayer.pause()
        }
        schedulePersistSession()
    }

    @androidx.annotation.OptIn(markerClass = [UnstableApi::class])
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

    private fun rebuildNavigationHistory(songs: List<Song>) {
        navigationHistory.clear()
        songs.forEach { navigationHistory.addLast(it) }
        _canSkipPrevious.value = navigationHistory.isNotEmpty()
        syncRecentlyPlayed()
    }

    private fun syncRecentlyPlayed() {
        val seen = LinkedHashSet<String>()
        _recentlyPlayed.value = navigationHistory.asReversed()
            .filter { seen.add(it.id) }
    }
}
