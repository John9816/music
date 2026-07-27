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
import com.music.player.data.settings.AppSettings
import com.music.player.ui.util.ImageUrl
import com.music.player.ui.util.SongDownloader
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
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
    private const val RECOVERY_WINDOW_MS = 45_000L
    private const val MAX_RECOVERY_ATTEMPTS = 2
    /** Prefetch next URLs almost immediately so skip does not wait on getSongUrl. */
    private const val NEXT_URL_PREFETCH_DELAY_MS = 80L
    private const val PREFETCH_AHEAD_COUNT = 3
    /** NetEase-like: >3s into track → previous rewinds current. */
    private const val PREVIOUS_REWIND_THRESHOLD_MS = 3_000L
    private const val PERSIST_DEBOUNCE_MS = 400L
    private const val POSITION_PERSIST_INTERVAL_MS = 5_000L

    private val repository = MusicRepository()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val navigationHistory = ArrayDeque<Song>()
    private var prepareJob: Job? = null
    private var lyricsJob: Job? = null
    /** Song id currently being fetched for lyrics (dedupe concurrent calls). */
    private var lyricsTargetId: String? = null
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
    private var songUrlCache: SongUrlCache? = null

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

    private val _playbackMode = MutableStateFlow(PlaybackMode.REPEAT_ALL)
    val playbackMode: StateFlow<PlaybackMode> = _playbackMode.asStateFlow()

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
        songUrlCache = SongUrlCache(appContext!!)
        restoreSessionFromDisk()
        PlaybackService.start(appContext!!)
        restoreSleepTimer()
    }

    @androidx.annotation.OptIn(markerClass = [UnstableApi::class])
    fun attachPlayer(context: Context, player: Player) {
        appContext = context.applicationContext
        MusicRepository.setApplicationContext(appContext!!)
        if (stateStore == null) {
            stateStore = PlaybackStateStore(appContext!!)
        }
        if (songUrlCache == null) {
            songUrlCache = SongUrlCache(appContext!!)
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
            AudioEqualizerController.attachSession(appContext!!, player.audioSessionId)
        }

        pendingPreparedSong?.let {
            pendingPreparedSong = null
            playPreparedSong(it, restoredPositionMs, restoredPlayWhenReady)
            restoredPositionMs = 0L
            restoredPlayWhenReady = false
        } ?: resumeRestoredCurrentIfNeeded()

        startPositionPersistenceLoop()
        notifyWidget()
    }

    fun togglePlayPause() {
        val active = player ?: return
        if (active.isPlaying || active.playWhenReady) {
            active.playWhenReady = false
        } else {
            if (active.mediaItemCount == 0) {
                _currentSong.value?.let { playStandaloneSong(it) }
            } else {
                active.playWhenReady = true
            }
        }
        notifyWidget()
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
            AudioEqualizerController.release()
            notifyWidget()
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
                // Lyrics are cheap and not tied to streaming: prefetch so the full player can show them.
                ensureLyricsLoaded(current)
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

    /**
     * Live radio / HLS live window: ExoPlayer duration & position slide with the window,
     * so treating them as VOD progress makes the bar jump. UI should hide/disable seek.
     */
    fun isLivePlayback(): Boolean {
        val song = _currentSong.value
        if (song != null && isRadioSong(song)) return true
        val p = player ?: return false
        if (p.mediaItemCount <= 0) return false
        return runCatching { p.isCurrentMediaItemLive }.getOrDefault(false)
    }

    fun isRadioSong(song: Song): Boolean =
        song.source.equals("radio", ignoreCase = true) ||
            song.id.startsWith("radio:", ignoreCase = true)

    /**
     * UI progress for mini-player / full player. Prefers live [Player] position when media is
     * loaded; otherwise uses the cold-start restored position + song metadata duration so the
     * progress bar is not stuck at 0 after reopening the app.
     */
    fun displayPositionMs(): Long {
        if (isLivePlayback()) return 0L
        val p = player
        val durationHint = displayDurationMs()
        if (p != null && p.mediaItemCount > 0) {
            val live = p.currentPosition.coerceAtLeast(0L)
            val state = p.playbackState
            // Before prepare/seek settles, ExoPlayer often reports 0; keep restored progress.
            if (live <= 0L &&
                restoredPositionMs > 0L &&
                (state == Player.STATE_IDLE || state == Player.STATE_BUFFERING || !p.isPlaying)
            ) {
                return clampPosition(restoredPositionMs, durationHint)
            }
            return clampPosition(live, durationHint)
        }
        return clampPosition(restoredPositionMs, durationHint)
    }

    fun displayDurationMs(): Long {
        // Never surface sliding live-window length as song duration.
        if (isLivePlayback()) return 0L
        val songDuration = _currentSong.value?.duration?.coerceAtLeast(0L) ?: 0L
        val p = player
        if (p != null && p.mediaItemCount > 0) {
            val d = p.duration
            if (d > 0L && d != C.TIME_UNSET) {
                return d
            }
        }
        return songDuration
    }

    private fun clampPosition(positionMs: Long, durationMs: Long): Long {
        val pos = positionMs.coerceAtLeast(0L)
        return if (durationMs > 0L) pos.coerceAtMost(durationMs) else pos
    }

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
        // Same track: keep lyrics; only stream URL changes.

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
                    schedulePostStartWork(prepared)
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

    /**
     * Play one song without wiping the existing up-next queue.
     * List contexts should prefer [playFromList] (replace list from tap point).
     */
    fun playStandaloneSong(song: Song) {
        restoredPositionMs = 0L
        // Keep queue: "insert-style" so search / options don't destroy a long playlist session.
        _playlistViewMode.value =
            if (_queue.value.isNotEmpty()) PlaylistViewMode.QUEUE else PlaylistViewMode.RECENT
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

        _queue.value = PlaybackQueueLogic.upcomingFromList(songs, song, _playbackMode.value)
        _playlistViewMode.value = PlaylistViewMode.QUEUE

        startPlayback(song, recordHistory = false)
        schedulePersistSession()
    }

    fun setPlaybackMode(mode: PlaybackMode) {
        if (_playbackMode.value == mode) return
        _playbackMode.value = mode
        player?.let(PlaybackModeController::applyEngineDefaults)
        schedulePersistSession()
    }

    fun cyclePlaybackMode(): PlaybackMode {
        val next = PlaybackModeController.next(_playbackMode.value)
        setPlaybackMode(next)
        return next
    }

    fun enqueue(song: Song) {
        _queue.value = PlaybackQueueLogic.enqueue(_queue.value.orEmpty(), song)
        _playlistViewMode.value = PlaylistViewMode.QUEUE
        schedulePersistSession()
        notifyWidget()
    }

    fun enqueueNext(song: Song) {
        _queue.value = PlaybackQueueLogic.enqueueNext(_queue.value.orEmpty(), song)
        _playlistViewMode.value = PlaylistViewMode.QUEUE
        schedulePersistSession()
        notifyWidget()
    }

    fun skipNext(): Boolean {
        return advanceToNext(userInitiated = true)
    }

    /**
     * @return true if a next track started (or current was rewound / looped).
     */
    private fun advanceToNext(userInitiated: Boolean): Boolean {
        val mode = _playbackMode.value
        val queueSnapshot = _queue.value.orEmpty()

        // User skip in single-repeat still advances (NetEase); auto-end loops current.
        if (!userInitiated && mode == PlaybackMode.REPEAT_ONE) {
            return restartCurrentTrack()
        }

        val pick = PlaybackQueueLogic.takeNext(queueSnapshot, mode)
        val next = pick.song
        if (next != null) {
            _queue.value = pick.remainingQueue
            restoredPositionMs = 0L
            _playlistViewMode.value =
                if (_queue.value.isEmpty()) PlaylistViewMode.RECENT else PlaylistViewMode.QUEUE
            startPlayback(withWarmedUrl(next), recordHistory = true)
            schedulePersistSession()
            return true
        }

        // Queue empty: list loop rebuilds from history + current (session list).
        if (mode == PlaybackMode.REPEAT_ALL || mode == PlaybackMode.SHUFFLE) {
            val rebuilt = rebuildLoopQueue()
            if (rebuilt != null) {
                restoredPositionMs = 0L
                _playlistViewMode.value = PlaylistViewMode.QUEUE
                startPlayback(withWarmedUrl(rebuilt), recordHistory = true)
                schedulePersistSession()
                return true
            }
        }

        // Single-track session under REPEAT_ALL / SHUFFLE with nothing else: re-play current.
        if (!userInitiated && mode != PlaybackMode.REPEAT_ONE) {
            return restartCurrentTrack()
        }
        return false
    }

    private fun restartCurrentTrack(): Boolean {
        val song = _currentSong.value ?: return false
        val activePlayer = player
        if (activePlayer != null && activePlayer.mediaItemCount > 0) {
            activePlayer.seekTo(0L)
            restoredPositionMs = 0L
            activePlayer.playWhenReady = true
            activePlayer.play()
            schedulePersistSession()
            return true
        }
        restoredPositionMs = 0L
        startPlayback(song, recordHistory = false, startPositionMs = 0L, shouldAutoPlay = true)
        return true
    }

    /**
     * When up-next is empty, rebuild from history + current so list-loop / shuffle continue.
     * Returns the song that should play next (first of rebuilt remaining queue).
     */
    private fun rebuildLoopQueue(): Song? {
        val current = _currentSong.value ?: return null
        val rebuilt = PlaybackQueueLogic.rebuildLoopQueue(
            history = navigationHistory.toList(),
            current = current,
            mode = _playbackMode.value
        ) ?: return null
        _queue.value = rebuilt.second
        return rebuilt.first
    }

    fun skipPrevious(): Boolean {
        val activePlayer = player
        val positionMs = when {
            activePlayer != null && activePlayer.mediaItemCount > 0 ->
                activePlayer.currentPosition.coerceAtLeast(0L)
            else -> restoredPositionMs.coerceAtLeast(0L)
        }
        if (positionMs > PREVIOUS_REWIND_THRESHOLD_MS) {
            return restartCurrentTrack()
        }

        if (navigationHistory.isEmpty()) {
            // Already at start: still rewind to 0 for consistency.
            return restartCurrentTrack()
        }
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
        val current = _currentSong.value
        if (current != null && current.id == songId) {
            // Removing "now playing": advance, or stop if nothing left.
            if (!advanceToNext(userInitiated = true)) {
                cancelPrepare()
                _currentSong.value = null
                restoredPositionMs = 0L
                player?.stop()
                player?.clearMediaItems()
                _playlistViewMode.value =
                    if (_queue.value.isEmpty()) PlaylistViewMode.RECENT else PlaylistViewMode.QUEUE
                schedulePersistSession()
            }
            return
        }
        _queue.value = _queue.value.orEmpty().filterNot { it.id == songId }
        if (_queue.value.isEmpty() && _currentSong.value == null) {
            _playlistViewMode.value = PlaylistViewMode.RECENT
        }
        schedulePersistSession()
    }

    /** Clear only up-next; keep the song that is currently playing. */
    fun clearQueue() {
        _queue.value = emptyList()
        if (_currentSong.value == null) {
            _playlistViewMode.value = PlaylistViewMode.RECENT
        }
        schedulePersistSession()
    }

    fun setPlaylistViewMode(mode: PlaylistViewMode) {
        if (_playlistViewMode.value == mode) return
        _playlistViewMode.value = mode
        schedulePersistSession()
    }

    fun clearResolvedUrlCache() {
        songUrlCache?.clear()
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
        ensureLyricsLoaded(song)
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
        // Coordinator owns multi-track modes; ignore ExoPlayer repeat flags.
        if (!advanceToNext(userInitiated = false)) {
            // Natural end of a non-looping one-shot session — stay paused on last track.
            player?.pause()
        }
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
            // Terminal for this track: try next song instead of leaving the player dead.
            if (advanceToNext(userInitiated = true)) {
                _error.tryEmit("当前歌曲无法播放，已切换下一首")
            } else {
                _error.tryEmit("当前歌曲播放失败，请切换音质或稍后再试")
            }
            return
        }

        prepareJob?.cancel()
        // Keep lyrics for the same track during recovery.

        val token = ++prepareToken
        // First recovery: reuse cache if still valid. Only force network on later attempts.
        val forceNetwork = recoveryAttemptsForSong > 1
        prepareJob = scope.launch {
            _isLoading.value = true
            try {
                val refreshed = song.copy(url = null)
                val urlResult = withContext(Dispatchers.IO) {
                    resolveSongUrl(refreshed, forceRefresh = forceNetwork)
                }
                val refreshedUrl = urlResult.getOrNull()?.trim().orEmpty()
                if (prepareToken != token) return@launch

                if (urlResult.isSuccess && refreshedUrl.isNotBlank()) {
                    val prepared = song.copy(url = refreshedUrl)
                    _currentSong.value = prepared
                    ensureLyricsLoaded(prepared)
                    playPreparedSong(
                        song = prepared,
                        startPositionMs = resumePositionMs,
                        shouldAutoPlay = true
                    )
                    _error.tryEmit(reason)
                } else if (prepareToken == token) {
                    // Soft miss: one forced refresh before abandoning the track.
                    if (!forceNetwork) {
                        val forced = withContext(Dispatchers.IO) {
                            resolveSongUrl(refreshed, forceRefresh = true)
                        }
                        val forcedUrl = forced.getOrNull()?.trim().orEmpty()
                        if (prepareToken == token && forced.isSuccess && forcedUrl.isNotBlank()) {
                            val prepared = song.copy(url = forcedUrl)
                            _currentSong.value = prepared
                            ensureLyricsLoaded(prepared)
                            playPreparedSong(
                                song = prepared,
                                startPositionMs = resumePositionMs,
                                shouldAutoPlay = true
                            )
                            _error.tryEmit(reason)
                            return@launch
                        }
                    }
                    if (advanceToNext(userInitiated = true)) {
                        _error.tryEmit("播放地址失效，已切换下一首")
                    } else {
                        _error.tryEmit(urlResult.exceptionOrNull()?.message ?: "恢复播放失败")
                    }
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

        // Keep existing LRC when re-selecting the same track (e.g. resume after restore).
        val base = if (current?.id == song.id && !current.lyric.isNullOrBlank()) {
            song.copy(lyric = current.lyric, url = song.url ?: current.url)
        } else {
            song
        }
        // Attach prefetched stream URL before IO when possible (skip gap shrinks a lot).
        val seed = withWarmedUrl(base)
        // Paint cover / title immediately; do not wait for stream URL.
        _currentSong.value = seed
        // Lyrics run in parallel with URL resolve — not after playback starts.
        ensureLyricsLoaded(seed)

        val token = ++prepareToken
        lastStartElapsedMs = SystemClock.elapsedRealtime()
        prepareJob = scope.launch {
            _isLoading.value = true
            try {
                ensureServiceRunning()

                val urlStart = SystemClock.elapsedRealtime()
                // If seed already has a playable URL (prefetch / local), skip network.
                val urlResult = withContext(Dispatchers.IO) { resolveSongUrl(seed) }
                val urlCost = SystemClock.elapsedRealtime() - urlStart
                val fastUrl = urlResult.getOrNull()?.trim().orEmpty()
                if (urlResult.isSuccess && fastUrl.isNotBlank()) {
                    if (prepareToken != token) return@launch

                    // Preserve lyric filled in by the parallel fetch while URL was resolving.
                    val lyricNow = _currentSong.value?.takeIf { it.id == seed.id }?.lyric
                    val prepared = seed.copy(
                        url = fastUrl,
                        lyric = lyricNow?.takeIf { it.isNotBlank() } ?: seed.lyric
                    )
                    _currentSong.value = prepared
                    Log.d(
                        TAG,
                        "resolved url in ${urlCost}ms (fast path), songId=${seed.id}, prewarmed=${!seed.url.isNullOrBlank()}"
                    )
                    playPreparedSong(prepared, startPositionMs, shouldAutoPlay)
                    schedulePersistSession()

                    schedulePostStartWork(prepared)
                } else {
                    // Fallback to legacy prepare path (may include additional server-side requirements).
                    Log.d(TAG, "url fast path failed in ${urlCost}ms, fallback prepareSong(), songId=${seed.id}")
                    repository.prepareSong(seed)
                        .onSuccess { prepared ->
                            if (prepareToken == token) {
                                prepared.url?.trim()?.takeIf { it.isNotBlank() }
                                    ?.let { putCachedUrl(prepared.id, prepared.source, it) }
                                val lyricNow = _currentSong.value?.takeIf { it.id == prepared.id }?.lyric
                                val merged = if (!lyricNow.isNullOrBlank() && prepared.lyric.isNullOrBlank()) {
                                    prepared.copy(lyric = lyricNow)
                                } else {
                                    prepared
                                }
                                _currentSong.value = merged
                                playPreparedSong(merged, startPositionMs, shouldAutoPlay)
                                schedulePersistSession()
                                schedulePostStartWork(merged)
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

    /** Attach cached stream URL onto the song model when present (no network). */
    private fun withWarmedUrl(song: Song): Song {
        if (!song.url.isNullOrBlank()) return song
        val cached = getCachedUrl(song.id, song.source) ?: return song
        return song.copy(url = cached)
    }

    private suspend fun resolveSongUrl(song: Song, forceRefresh: Boolean = false): Result<String> {
        // Prefer a previously downloaded file so catalog / search / playlist entries work offline.
        val localUrl = appContext?.let { SongDownloader.localPlaybackUri(it, song) }?.trim().orEmpty()
        val offlineOnly = appContext?.let { AppSettings.isOfflineOnly(it) } == true
        val networkOk = com.music.player.data.api.NetworkRuntime.isNetworkAvailable()

        if (!forceRefresh) {
            val existing = song.url?.trim().orEmpty()
            if (existing.isNotBlank() && SongDownloader.isPlayableLocalUrl(existing)) {
                return Result.success(existing)
            }
            if (localUrl.isNotBlank()) {
                putCachedUrl(song.id, song.source, localUrl)
                return Result.success(localUrl)
            }
            if (offlineOnly || !networkOk) {
                val cachedOffline = getCachedUrl(song.id, song.source)
                if (cachedOffline != null && !SongDownloader.isLocalFileUrl(cachedOffline)) {
                    // Stale remote URL may still work from CDN; try it when offline-only is off
                    // but network is flaky. When offline-only, only local files are allowed.
                    if (!offlineOnly) return Result.success(cachedOffline)
                }
                return Result.failure(IllegalStateException("离线模式：该歌曲尚未下载"))
            }
            if (existing.isNotBlank() && !SongDownloader.isLocalFileUrl(existing)) {
                return Result.success(existing)
            }

            val cached = getCachedUrl(song.id, song.source)
            if (cached != null) {
                if (SongDownloader.isLocalFileUrl(cached) && !SongDownloader.isPlayableLocalUrl(cached)) {
                    // Stale local cache entry; fall through to network.
                } else {
                    return Result.success(cached)
                }
            }
        } else if (localUrl.isNotBlank()) {
            // Quality re-resolve still keeps offline local as last-resort after network failure.
        }

        if (offlineOnly && localUrl.isBlank()) {
            return Result.failure(IllegalStateException("离线模式：该歌曲尚未下载"))
        }

        val fetched = repository.getSongUrl(
            song.id,
            source = song.source,
            forceRefresh = forceRefresh
        )
        val remote = fetched.getOrNull()?.trim().orEmpty()
        if (remote.isNotBlank()) {
            putCachedUrl(song.id, song.source, remote)
            return Result.success(remote)
        }
        if (localUrl.isNotBlank()) {
            putCachedUrl(song.id, song.source, localUrl)
            return Result.success(localUrl)
        }
        return fetched
    }

    private fun schedulePostStartWork(prepared: Song) {
        ensureLyricsLoaded(prepared)
        prefetchNextUrl()
    }

    /**
     * Load lyrics as soon as the current track identity is known (restore, open player, play).
     * Independent of ExoPlayer prepare / stream URL so cover + LRC can appear before audio is ready.
     */
    fun ensureLyricsForCurrentSong() {
        _currentSong.value?.let { ensureLyricsLoaded(it) }
    }

    private fun ensureLyricsLoaded(song: Song) {
        val id = song.id.trim()
        if (id.isBlank()) return
        if (!song.lyric.isNullOrBlank()) return
        val live = _currentSong.value
        if (live?.id == id && !live.lyric.isNullOrBlank()) return
        if (lyricsTargetId == id && lyricsJob?.isActive == true) return

        lyricsTargetId = id
        lyricsJob?.cancel()
        val source = song.source
        lyricsJob = scope.launch {
            val lyric = withContext(Dispatchers.IO) {
                repository.getLyrics(id, source = source).getOrNull()
            }
                ?.trim()
                .orEmpty()
            if (lyric.isBlank()) return@launch
            if (lyricsTargetId != id) return@launch

            val current = _currentSong.value ?: return@launch
            if (current.id != id) return@launch
            if (!current.lyric.isNullOrBlank()) return@launch
            _currentSong.value = current.copy(lyric = lyric)
        }
    }

    private fun prefetchNextUrl() {
        val ahead = _queue.value.take(PREFETCH_AHEAD_COUNT)
        if (ahead.isEmpty()) return
        val token = prepareToken
        scope.launch {
            delay(NEXT_URL_PREFETCH_DELAY_MS)
            if (prepareToken != token) return@launch
            // Resolve next N URLs in parallel so skip #2/#3 are warm too.
            coroutineScope {
                ahead.map { song ->
                    async(Dispatchers.IO) {
                        if (prepareToken != token) return@async
                        if (getCachedUrl(song.id, song.source) != null) return@async
                        if (!song.url.isNullOrBlank()) {
                            putCachedUrl(song.id, song.source, song.url!!.trim())
                            return@async
                        }
                        resolveSongUrl(song)
                    }
                }.awaitAll()
            }
        }
    }

    private fun getCachedUrl(songId: String, source: String): String? =
        songUrlCache?.get(songId, source)

    private fun putCachedUrl(songId: String, source: String, url: String) {
        songUrlCache?.put(songId, source, url)
    }

    private fun notifyWidget() {
        val ctx = appContext ?: return
        runCatching {
            com.music.player.widget.PlayerAppWidget.refreshAll(ctx)
        }
    }

    /** Called from [PlaybackService] when play/pause or state changes outside coordinator APIs. */
    fun notifyWidgetExternal() = notifyWidget()

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
        // Always OFF at engine level — app handles loop/shuffle on ENDED.
        PlaybackModeController.applyEngineDefaults(activePlayer)
        activePlayer.prepare()
        if (activePlayer is androidx.media3.exoplayer.ExoPlayer) {
            appContext?.let { AudioEqualizerController.attachSession(it, activePlayer.audioSessionId) }
        }
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
        notifyWidget()
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
        lyricsTargetId = null
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
