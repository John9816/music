package com.music.player.ui.activity

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.drawable.Drawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.util.Log
import android.view.LayoutInflater
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.isVisible
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.DataSource
import com.bumptech.glide.load.engine.GlideException
import com.bumptech.glide.request.RequestListener
import com.bumptech.glide.request.RequestOptions
import com.bumptech.glide.request.target.Target
import com.google.android.material.chip.Chip
import com.music.player.R
import com.music.player.data.live.TvChannel
import com.music.player.data.live.TvChannelCatalog
import com.music.player.data.live.TvChannelCatalogItem
import com.music.player.data.live.TvLiveApiClient
import com.music.player.data.live.TvLogoUrl
import com.music.player.data.live.TvSourceSelector
import com.music.player.databinding.ActivityTvLiveBinding
import com.music.player.databinding.ItemTvChannelBinding
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.util.applyEdgeToEdge
import com.music.player.ui.util.applyNavigationBarInsetPadding
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.util.resolveThemeColor
import kotlinx.coroutines.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])
class TvLiveActivity : AppCompatActivity() {

    private lateinit var binding: ActivityTvLiveBinding
    private lateinit var adapter: ChannelAdapter

    private var allChannels: List<TvChannelCatalogItem> = emptyList()
    private var visibleChannels: List<TvChannelCatalogItem> = emptyList()
    private var selectedGroup: String = ""
    private var loadJob: Job? = null
    private var loadRequestId: Long = 0L
    private var filterJob: Job? = null
    private var sourceTimeoutJob: Job? = null
    private var playingId: String? = null
    private var playingItem: TvChannelCatalogItem? = null
    private var playingChannel: TvChannel? = null
    private var pendingChannel: TvChannelCatalogItem? = null
    private var currentSourceIndex: Int = 0
    private var sourceAttemptOrder: List<Int> = emptyList()
    private var sourceAttemptPosition: Int = 0
    private val failedSources = LinkedHashMap<String, Long>()
    private var playbackState: PlaybackState = PlaybackState.IDLE
    private var controlsHideRunnable: Runnable? = null
    private var isPlayerChromeVisible: Boolean = true
    private val mainHandler = Handler(Looper.getMainLooper())
    private var player: ExoPlayer? = null
    @Volatile
    private var destroyRequested: Boolean = false
    @Volatile
    private var playbackRequestId: Long = 0L
    private var isFullscreen: Boolean = false
    private var isExitingFullscreen: Boolean = false
    private var requestedOrientationBeforeFullscreen = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    private var configurationOrientationBeforeFullscreen = Configuration.ORIENTATION_UNDEFINED
    private var normalPlayerLayout: PlayerLayoutSnapshot? = null

    private data class PlayerLayoutSnapshot(
        val cardWidth: Int,
        val cardHeight: Int,
        val frameHeight: Int,
        val marginLeft: Int,
        val marginTop: Int,
        val marginRight: Int,
        val marginBottom: Int
    )

    private enum class PlaybackState {
        IDLE,
        PREPARING,
        PLAYING,
        PAUSED,
        ERROR
    }

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            if (destroyRequested) return
            when (state) {
                Player.STATE_BUFFERING -> {
                    if (playingItem != null && playbackState != PlaybackState.ERROR) {
                        // Keep the original start/failover deadline — do not reset on every buffer tick.
                        val alreadyTimingOut = sourceTimeoutJob?.isActive == true
                        updatePlaybackState(
                            PlaybackState.PREPARING,
                            getString(R.string.tv_live_connecting)
                        )
                        if (!alreadyTimingOut) {
                            playingChannel?.let(::scheduleSourceTimeout)
                        }
                    }
                }
                Player.STATE_READY -> {
                    sourceTimeoutJob?.cancel()
                    rememberSuccessfulSource()
                    val exo = player
                    if (exo != null && exo.playWhenReady) {
                        updatePlaybackState(PlaybackState.PLAYING)
                    } else if (playingItem != null) {
                        updatePlaybackState(PlaybackState.PAUSED)
                    }
                }
                Player.STATE_ENDED -> {
                    // Live streams rarely end cleanly; treat unexpected end while starting as fail.
                    if (playbackState == PlaybackState.PREPARING) {
                        markCurrentSourceFailed()
                        tryNextSource()
                    }
                }
                Player.STATE_IDLE -> {
                    // Transient between media items and after release; nothing to surface.
                }
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            if (destroyRequested) return
            Log.w(TAG_PLAYER, "ExoPlayer error: ${error.errorCodeName}", error)
            markCurrentSourceFailed()
            tryNextSource()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            if (destroyRequested || playingItem == null) return
            if (playbackState == PlaybackState.PREPARING || playbackState == PlaybackState.ERROR) return
            updatePlaybackState(if (isPlaying) PlaybackState.PLAYING else PlaybackState.PAUSED)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.prepareActivity(this)
        super.onCreate(savedInstanceState)
        binding = ActivityTvLiveBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val lightBars = (resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) !=
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        applyEdgeToEdge(rootView = binding.root, lightSystemBars = lightBars)
        binding.toolbar.applyStatusBarInsetPadding()
        binding.recyclerView.applyNavigationBarInsetPadding()

        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.toolbar.inflateMenu(R.menu.menu_radio)
        binding.toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_refresh -> {
                    loadChannels(forceRefresh = true)
                    true
                }
                else -> false
            }
        }

        adapter = ChannelAdapter { channel -> onChannelClick(channel) }
        binding.recyclerView.layoutManager = LinearLayoutManager(this).apply {
            initialPrefetchItemCount = CHANNEL_PREFETCH_COUNT
        }
        binding.recyclerView.adapter = adapter
        binding.recyclerView.setHasFixedSize(true)
        binding.recyclerView.setItemViewCacheSize(CHANNEL_VIEW_CACHE_SIZE)
        binding.recyclerView.itemAnimator = null

        binding.swipeRefresh.setColorSchemeColors(resolveThemeColor(R.attr.brandPrimary))
        binding.swipeRefresh.setOnRefreshListener { loadChannels(forceRefresh = true) }
        binding.btnRetry.setOnClickListener { loadChannels(forceRefresh = true) }
        binding.btnRetry.bindPressFeedback(PressFeedback.Style.BUTTON)

        binding.etSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) {
                filterJob?.cancel()
                filterJob = lifecycleScope.launch {
                    delay(FILTER_DEBOUNCE_MS)
                    applyFilter()
                }
            }
        })
        binding.etSearch.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                hideKeyboard()
                true
            } else {
                false
            }
        }

        binding.btnPlayerPause.setOnClickListener {
            togglePlayback()
            refreshPlayingUiFromPlayer()
        }
        binding.btnPlayerPause.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnPlayerPrevious.setOnClickListener { playAdjacentChannel(offset = -1) }
        binding.btnPlayerPrevious.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnPlayerNext.setOnClickListener { playAdjacentChannel(offset = 1) }
        binding.btnPlayerNext.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnPlayerFullscreen.setOnClickListener { setFullscreen(!isFullscreen) }
        binding.btnPlayerFullscreen.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnPlayerRetry.setOnClickListener {
            playingItem?.let { playChannel(it, sourceIndex = 0) }
        }
        binding.btnPlayerRetry.bindPressFeedback(PressFeedback.Style.BUTTON)
        binding.playerFrame.setOnClickListener {
            if (playingItem != null) {
                setPlayerChromeVisible(!binding.playerControls.isVisible)
            }
        }
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (isFullscreen) {
                    setFullscreen(false)
                } else {
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                }
            }
        })

        initPlayer()
        binding.playerCard.post { applyResponsivePlayerHeight() }

        selectedGroup = lastSelectedGroup().orEmpty()
        rebuildChips()
        loadChannels(forceRefresh = false)
    }

    override fun onResume() {
        super.onResume()
        refreshPlayingUiFromPlayer()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (!isFullscreen && !isExitingFullscreen) {
            binding.playerCard.post { applyResponsivePlayerHeight() }
        }
        if (isExitingFullscreen && newConfig.orientation == configurationOrientationBeforeFullscreen) {
            binding.root.post { finishFullscreenExit() }
        }
    }

    override fun onStop() {
        setPaused(true)
        refreshPlayingUiFromPlayer()
        super.onStop()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (isFullscreen && event.repeatCount == 0) {
            when (keyCode) {
                KeyEvent.KEYCODE_CHANNEL_UP -> playAdjacentChannel(-1)
                KeyEvent.KEYCODE_CHANNEL_DOWN -> playAdjacentChannel(1)
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> togglePlayback()
                KeyEvent.KEYCODE_DPAD_UP,
                KeyEvent.KEYCODE_DPAD_DOWN,
                KeyEvent.KEYCODE_DPAD_LEFT,
                KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_ENTER -> {
                    if (binding.playerControls.isVisible) {
                        scheduleControlsHide()
                        return super.onKeyDown(keyCode, event)
                    }
                    setPlayerChromeVisible(true)
                    binding.btnPlayerPause.requestFocus()
                }
                else -> return super.onKeyDown(keyCode, event)
            }
            setPlayerChromeVisible(true)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onDestroy() {
        loadJob?.cancel()
        filterJob?.cancel()
        sourceTimeoutJob?.cancel()
        controlsHideRunnable?.let(mainHandler::removeCallbacks)
        if (isFullscreen) {
            WindowCompat.getInsetsController(window, binding.root)
                .show(WindowInsetsCompat.Type.systemBars())
            requestedOrientation = requestedOrientationBeforeFullscreen
        }
        destroyRequested = true
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        releasePlayer()
        super.onDestroy()
    }

    private fun initPlayer() {
        if (player != null) return
        updatePlaybackState(PlaybackState.IDLE)
        runCatching {
            val httpFactory = DefaultHttpDataSource.Factory()
                .setConnectTimeoutMs(8_000)
                .setReadTimeoutMs(12_000)
                .setAllowCrossProtocolRedirects(true)
                .setUserAgent(PLAYER_USER_AGENT)
            val loadControl = DefaultLoadControl.Builder()
                .setBufferDurationsMs(
                    /* minBufferMs = */ 5_000,
                    /* maxBufferMs = */ 30_000,
                    /* bufferForPlaybackMs = */ 1_000,
                    /* bufferForPlaybackAfterRebufferMs = */ 3_000
                )
                .setPrioritizeTimeOverSizeThresholds(true)
                .build()
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build()
            val exo = ExoPlayer.Builder(this)
                .setMediaSourceFactory(
                    DefaultMediaSourceFactory(DefaultDataSource.Factory(this, httpFactory))
                )
                .setLoadControl(loadControl)
                .setAudioAttributes(audioAttributes, /* handleAudioFocus = */ true)
                .setHandleAudioBecomingNoisy(true)
                .setWakeMode(C.WAKE_MODE_NETWORK)
                .build()
            exo.setVideoSurfaceView(binding.videoSurface)
            exo.addListener(playerListener)
            player = exo
            pendingChannel?.also {
                pendingChannel = null
                playChannel(it)
            }
        }.onFailure { error ->
            Log.e(TAG_PLAYER, "Failed to initialize ExoPlayer", error)
            updatePlaybackState(PlaybackState.ERROR, getString(R.string.tv_live_player_init_failed))
        }
    }

    private fun releasePlayer() {
        player?.removeListener(playerListener)
        player?.clearVideoSurface()
        player?.release()
        player = null
    }

    private fun loadChannels(forceRefresh: Boolean) {
        loadJob?.cancel()
        val requestId = ++loadRequestId
        setChannelLoading(true, refresh = forceRefresh)
        loadJob = lifecycleScope.launch {
            try {
                if (!forceRefresh && allChannels.isEmpty()) {
                    TvLiveApiClient.loadCachedChannels(this@TvLiveActivity)?.let { cached ->
                        renderChannels(cached.channels)
                    }
                }

                val result = TvLiveApiClient.loadChannels(
                    context = this@TvLiveActivity,
                    forceRefresh = forceRefresh
                )
                result.onSuccess { loaded ->
                    renderChannels(loaded.channels)
                    if (forceRefresh) {
                        Toast.makeText(
                            this@TvLiveActivity,
                            if (loaded.fromCache) R.string.tv_live_refresh_fallback else R.string.tv_live_refreshed,
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }.onFailure { error ->
                    if (allChannels.isEmpty()) {
                        adapter.submitList(emptyList())
                        showEmpty(
                            error.message ?: getString(R.string.tv_live_load_failed),
                            showRetry = true
                        )
                    } else {
                        Toast.makeText(
                            this@TvLiveActivity,
                            getString(R.string.tv_live_refresh_fallback),
                            Toast.LENGTH_SHORT
                        ).show()
                        applyFilter()
                    }
                }
            } finally {
                if (requestId == loadRequestId) {
                    setChannelLoading(false, refresh = forceRefresh)
                }
            }
        }
    }

    private suspend fun renderChannels(channels: List<TvChannel>) {
        val catalog = withContext(Dispatchers.Default) { TvChannelCatalog.build(channels) }
        if (catalog == allChannels) return
        allChannels = catalog
        binding.progress.isVisible = false
        rebuildChips()
        applyFilter()
        resumeLastChannelIfNeeded()
    }

    private fun setChannelLoading(loading: Boolean, refresh: Boolean) {
        binding.toolbar.menu.findItem(R.id.action_refresh)?.isEnabled = !loading
        binding.swipeRefresh.isEnabled = true
        binding.swipeRefresh.isRefreshing = loading && refresh
        binding.progress.isVisible = loading && allChannels.isEmpty()
        if (loading && allChannels.isEmpty()) {
            binding.emptyState.isVisible = false
        }
    }

    private fun rebuildChips() {
        val labels = buildGroupLabels(allChannels)
        if (selectedGroup.isEmpty() || selectedGroup !in labels) {
            selectedGroup = labels.firstOrNull() ?: ""
        }
        binding.chipGroup.removeAllViews()
        labels.forEach { label ->
            val chip = Chip(this, null, com.google.android.material.R.attr.chipStyle).apply {
                text = label
                isCheckable = true
                isChecked = label == selectedGroup
                isClickable = true
                minHeight = resources.getDimensionPixelSize(R.dimen.control_height_m)
                setOnClickListener {
                    selectedGroup = label
                    rememberLastGroup(label)
                    applyFilter()
                    binding.recyclerView.scrollToPosition(0)
                }
            }
            binding.chipGroup.addView(chip)
        }
        binding.chipScroll.isVisible = labels.size > 1 || allChannels.isNotEmpty()
    }

    private fun applyFilter() {
        val q = binding.etSearch.text?.toString().orEmpty().trim()
        val base = if (selectedGroup == GROUP_ALL || q.isNotBlank()) {
            allChannels
        } else {
            allChannels.filter { it.group == selectedGroup }
        }
        val filtered = if (q.isBlank()) {
            base
        } else {
            base.filter {
                it.name.contains(q, ignoreCase = true) ||
                    it.group.contains(q, ignoreCase = true)
            }
        }
        visibleChannels = filtered
        adapter.submitList(filtered)
        updateSubtitle(filtered.size)
        refreshPlayingUiFromPlayer()

        when {
            filtered.isNotEmpty() -> {
                binding.emptyState.isVisible = false
                binding.btnRetry.isVisible = false
            }
            allChannels.isEmpty() -> showEmpty(getString(R.string.tv_live_empty), showRetry = true)
            q.isNotBlank() -> showEmpty(getString(R.string.tv_live_search_empty), showRetry = false)
            else -> showEmpty(getString(R.string.tv_live_filter_empty), showRetry = false)
        }
    }

    private fun showEmpty(message: String, showRetry: Boolean) {
        binding.emptyState.isVisible = true
        binding.tvEmpty.text = message
        binding.btnRetry.isVisible = showRetry
    }

    private fun updateSubtitle(visibleCount: Int) {
        binding.tvSubtitle.text = when {
            allChannels.isEmpty() -> getString(R.string.tools_tv_live_subtitle)
            visibleCount == allChannels.size && selectedGroup == GROUP_ALL ->
                getString(R.string.tv_live_count_all, allChannels.size)
            else -> getString(R.string.tv_live_count_filtered, visibleCount, allChannels.size)
        }
    }

    private fun onChannelClick(channel: TvChannelCatalogItem) {
        val id = channel.toSongId()
        if (id == playingId) {
            when (playbackState) {
                PlaybackState.ERROR -> playChannel(channel)
                PlaybackState.PLAYING, PlaybackState.PAUSED -> togglePlayback()
                else -> Unit
            }
            return
        }
        playChannel(channel)
    }

    private fun playChannel(channel: TvChannelCatalogItem, sourceIndex: Int = -1) {
        val preferredUrl = if (sourceIndex < 0) preferredSource(channel.key) else null
        val safeIndex = if (sourceIndex >= 0) {
            sourceIndex.coerceIn(0, channel.sources.lastIndex.coerceAtLeast(0))
        } else {
            TvSourceSelector.preferredIndex(channel.sources, preferredUrl)
        }
        pruneFailedSources()
        sourceAttemptOrder = TvSourceSelector.attemptOrder(
            channel.sources,
            safeIndex,
            failedSources.keys
        )
        sourceAttemptPosition = 0
        playingId = channel.toSongId()
        playingItem = channel
        currentSourceIndex = sourceAttemptOrder.firstOrNull() ?: safeIndex
        adapter.setPlayingId(playingId)
        setPlayerChromeVisible(true)
        if (player == null) {
            pendingChannel = channel
            updatePlaybackState(
                PlaybackState.PREPARING,
                getString(R.string.tv_live_player_starting)
            )
            initPlayer()
            return
        }
        playCurrentSource()
    }

    private fun playCurrentSource() {
        val item = playingItem ?: return
        val source = item.sources.getOrNull(currentSourceIndex) ?: return
        val exo = player ?: run {
            pendingChannel = item
            initPlayer()
            return
        }
        sourceTimeoutJob?.cancel()
        pendingChannel = null
        playingChannel = source
        updatePlaybackState(
            PlaybackState.PREPARING,
            getString(
                R.string.tv_live_connecting_source,
                sourceAttemptPosition + 1,
                item.sources.size
            )
        )
        val requestId = ++playbackRequestId
        runCatching {
            exo.setMediaItem(MediaItem.fromUri(source.playUrl))
            exo.prepare()
            exo.playWhenReady = true
        }.onFailure { error ->
            Log.w(TAG_PLAYER, "Failed to load source: ${source.playUrl}", error)
            if (requestId == playbackRequestId) {
                markCurrentSourceFailed()
                tryNextSource()
            }
            return
        }
        scheduleSourceTimeout(source, requestId)
    }

    private fun scheduleSourceTimeout(source: TvChannel, requestId: Long = playbackRequestId) {
        sourceTimeoutJob?.cancel()
        // First attempt gets a bit more budget; later failovers cut sooner so users land on a live URL faster.
        val timeoutMs = if (sourceAttemptPosition == 0) {
            SOURCE_START_TIMEOUT_MS
        } else {
            SOURCE_FAILOVER_TIMEOUT_MS
        }
        sourceTimeoutJob = lifecycleScope.launch {
            delay(timeoutMs)
            if (playbackState == PlaybackState.PREPARING && playingChannel == source &&
                requestId == playbackRequestId
            ) {
                markCurrentSourceFailed()
                tryNextSource()
            }
        }
    }

    private fun tryNextSource() {
        sourceTimeoutJob?.cancel()
        val item = playingItem ?: return
        sourceAttemptPosition += 1
        val nextIndex = sourceAttemptOrder.getOrNull(sourceAttemptPosition)
        if (nextIndex != null) {
            // Drop the dead media item so ExoPlayer releases sockets before the next try.
            runCatching {
                player?.stop()
                player?.clearMediaItems()
            }
            currentSourceIndex = nextIndex
            playCurrentSource()
        } else {
            updatePlaybackState(
                PlaybackState.ERROR,
                getString(R.string.tv_live_all_sources_failed)
            )
        }
    }

    private fun preferredSource(channelKey: String): String? =
        getSharedPreferences(SOURCE_PREFS, MODE_PRIVATE).getString(channelKey, null)

    private fun rememberSuccessfulSource() {
        val item = playingItem ?: return
        val source = playingChannel ?: return
        failedSources.remove(source.playUrl)
        rememberLastChannel(item.key)
        getSharedPreferences(SOURCE_PREFS, MODE_PRIVATE)
            .edit()
            .putString(item.key, source.playUrl)
            .apply()
    }

    private fun lastSelectedGroup(): String? =
        getSharedPreferences(SOURCE_PREFS, MODE_PRIVATE).getString(LAST_GROUP_KEY, null)

    private fun rememberLastGroup(group: String) {
        getSharedPreferences(SOURCE_PREFS, MODE_PRIVATE)
            .edit()
            .putString(LAST_GROUP_KEY, group)
            .apply()
    }

    private fun lastChannelKey(): String? =
        getSharedPreferences(SOURCE_PREFS, MODE_PRIVATE).getString(LAST_CHANNEL_KEY, null)

    private fun rememberLastChannel(channelKey: String) {
        getSharedPreferences(SOURCE_PREFS, MODE_PRIVATE)
            .edit()
            .putString(LAST_CHANNEL_KEY, channelKey)
            .apply()
    }

    /** Re-opens the last successfully played channel so the page feels like a real TV. */
    private fun resumeLastChannelIfNeeded() {
        if (playingItem != null) return
        val lastKey = lastChannelKey() ?: return
        val channel = allChannels.firstOrNull { it.key == lastKey } ?: return
        playChannel(channel)
        scrollToChannel(channel)
    }

    private fun scrollToChannel(channel: TvChannelCatalogItem) {
        val index = visibleChannels.indexOfFirst { it.key == channel.key }
        if (index >= 0) {
            binding.recyclerView.scrollToPosition(index)
        }
    }

    private fun markCurrentSourceFailed() {
        playingChannel?.playUrl?.let { failedSources[it] = System.currentTimeMillis() }
    }

    private fun pruneFailedSources(nowMs: Long = System.currentTimeMillis()) {
        failedSources.entries.removeAll { nowMs - it.value >= FAILED_SOURCE_COOLDOWN_MS }
    }

    private fun playAdjacentChannel(offset: Int) {
        val channels = visibleChannels.ifEmpty { allChannels }
        if (channels.isEmpty()) return
        val currentId = playingId
        val currentIndex = channels.indexOfFirst { it.toSongId() == currentId }
        val targetIndex = if (currentIndex >= 0) {
            (currentIndex + offset + channels.size) % channels.size
        } else if (offset >= 0) {
            0
        } else {
            channels.lastIndex
        }
        playChannel(channels[targetIndex])
        if (visibleChannels.isNotEmpty()) {
            binding.recyclerView.scrollToPosition(targetIndex)
        }
    }

    private fun togglePlayback() {
        when (playbackState) {
            PlaybackState.PLAYING -> setPaused(true)
            PlaybackState.PAUSED -> setPaused(false)
            else -> Unit
        }
    }

    private fun setPaused(paused: Boolean) {
        if (playingId == null || playbackState == PlaybackState.ERROR) return
        val exo = player ?: return
        exo.playWhenReady = !paused
        updatePlaybackState(if (paused) PlaybackState.PAUSED else PlaybackState.PLAYING)
    }

    private fun refreshPlayingUiFromPlayer() {
        updatePlaybackState(playbackState)
    }

    private fun updatePlaybackState(state: PlaybackState, message: String? = null) {
        playbackState = state
        val item = playingItem
        // Keep the screen awake while a live channel is playing or connecting; otherwise
        // the device sleeps mid-stream and the picture goes black.
        val keepAwake = item != null &&
            (state == PlaybackState.PLAYING || state == PlaybackState.PREPARING)
        if (keepAwake) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        val hasChannel = item != null
        val isPreparing = state == PlaybackState.PREPARING
        val hasError = state == PlaybackState.ERROR

        binding.btnPlayerPause.setImageResource(
            if (state == PlaybackState.PLAYING) R.drawable.ic_pause_24 else R.drawable.ic_play_24
        )
        binding.btnPlayerPause.contentDescription = getString(
            if (state == PlaybackState.PLAYING) R.string.content_desc_pause else R.string.content_desc_play
        )
        binding.btnPlayerPause.isEnabled = state == PlaybackState.PLAYING || state == PlaybackState.PAUSED
        binding.btnPlayerPause.alpha = if (binding.btnPlayerPause.isEnabled) 1f else DISABLED_ALPHA
        val showChrome = hasChannel && isPlayerChromeVisible
        binding.playerControls.isVisible = showChrome
        binding.btnPlayerFullscreen.isVisible = showChrome
        binding.tvPlayerHint.isVisible = state == PlaybackState.IDLE
        binding.playerLoadingBar.isVisible = isPreparing
        binding.playerStatusContainer.isVisible =
            hasError || state == PlaybackState.PAUSED
        binding.playerProgress.isVisible = isPreparing
        binding.tvPlayerStatus.isVisible = hasError || state == PlaybackState.PAUSED
        binding.tvPlayerStatus.text = message ?: when (state) {
            PlaybackState.PREPARING -> getString(R.string.tv_live_connecting)
            PlaybackState.PAUSED -> getString(R.string.tv_live_paused)
            PlaybackState.ERROR -> getString(R.string.tv_live_all_sources_failed)
            else -> ""
        }
        binding.btnPlayerRetry.isVisible = hasError && item != null
        binding.playerNowPlaying.isVisible = showChrome
        binding.tvPlayerChannel.text = item?.name.orEmpty()
        binding.tvPlayerSource.text = if (item != null) {
            getString(
                R.string.tv_live_source_position,
                sourceAttemptPosition + 1,
                item.sources.size
            )
        } else {
            ""
        }
        val canNavigate = visibleChannels.ifEmpty { allChannels }.size > 1
        binding.btnPlayerPrevious.isEnabled = canNavigate
        binding.btnPlayerPrevious.alpha = if (canNavigate) 1f else DISABLED_ALPHA
        binding.btnPlayerNext.isEnabled = canNavigate
        binding.btnPlayerNext.alpha = if (canNavigate) 1f else DISABLED_ALPHA
        adapter.setPlaybackState(state)
        when {
            state == PlaybackState.ERROR || state == PlaybackState.PAUSED ->
                setPlayerChromeVisible(true)
            state == PlaybackState.PLAYING && isPlayerChromeVisible ->
                scheduleControlsHide()
        }
    }

    private fun setFullscreen(fullscreen: Boolean) {
        if (fullscreen) {
            if (isFullscreen) return
            isFullscreen = true
            hideKeyboard()
            requestedOrientationBeforeFullscreen = requestedOrientation
            configurationOrientationBeforeFullscreen = resources.configuration.orientation
            binding.appBar.isVisible = false
            binding.contentContainer.isVisible = false
            applyFullscreenPlayerLayout(fullscreen = true)
            binding.appBar.isVisible = binding.playerCard.parent === binding.appBar
            setPlayerChromeVisible(true)
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            WindowCompat.getInsetsController(window, binding.root).apply {
                systemBarsBehavior =
                    WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                hide(WindowInsetsCompat.Type.systemBars())
            }
        } else {
            if (!isFullscreen || isExitingFullscreen) return
            isExitingFullscreen = true
            restoreOrientationAfterFullscreen()
            binding.root.postDelayed({ finishFullscreenExit() }, FULLSCREEN_EXIT_FALLBACK_MS)
        }
    }

    private fun finishFullscreenExit() {
        if (!isExitingFullscreen || isFinishing || isDestroyed) return
        isExitingFullscreen = false
        isFullscreen = false
        applyFullscreenPlayerLayout(fullscreen = false)
        binding.contentContainer.isVisible = true
        setPlayerChromeVisible(playingItem != null)
        WindowCompat.getInsetsController(window, binding.root)
            .show(WindowInsetsCompat.Type.systemBars())
        requestedOrientation = requestedOrientationBeforeFullscreen
    }

    private fun applyFullscreenPlayerLayout(fullscreen: Boolean) {
        val playerLivesInAppBar = binding.playerCard.parent === binding.appBar
        if (fullscreen && normalPlayerLayout == null) {
            val cardParams = binding.playerCard.layoutParams as ViewGroup.MarginLayoutParams
            normalPlayerLayout = PlayerLayoutSnapshot(
                cardWidth = cardParams.width,
                cardHeight = cardParams.height,
                frameHeight = binding.playerFrame.layoutParams.height,
                marginLeft = cardParams.leftMargin,
                marginTop = cardParams.topMargin,
                marginRight = cardParams.rightMargin,
                marginBottom = cardParams.bottomMargin
            )
        }
        binding.toolbar.isVisible = !fullscreen
        binding.tvSubtitle.isVisible = !fullscreen
        binding.tilSearch.isVisible = !fullscreen
        binding.chipScroll.isVisible = !fullscreen && allChannels.isNotEmpty()
        setViewHeight(binding.appBar, if (fullscreen && playerLivesInAppBar) {
            ViewGroup.LayoutParams.MATCH_PARENT
        } else {
            ViewGroup.LayoutParams.WRAP_CONTENT
        })
        if (!playerLivesInAppBar) {
            binding.appBar.isVisible = !fullscreen
            binding.playerCard.layoutParams = binding.playerCard.layoutParams.apply {
                width = if (fullscreen) {
                    ViewGroup.LayoutParams.MATCH_PARENT
                } else {
                    normalPlayerLayout?.cardWidth ?: 0
                }
            }
        }
        setViewHeight(
            binding.playerCard,
            when {
                fullscreen -> ViewGroup.LayoutParams.MATCH_PARENT
                else -> normalPlayerLayout?.cardHeight ?: ViewGroup.LayoutParams.WRAP_CONTENT
            }
        )
        setViewHeight(
            binding.playerFrame,
            if (fullscreen) {
                ViewGroup.LayoutParams.MATCH_PARENT
            } else {
                normalPlayerLayout?.frameHeight ?: responsivePlayerHeightPx()
            }
        )
        val cardParams = binding.playerCard.layoutParams as ViewGroup.MarginLayoutParams
        if (fullscreen) {
            cardParams.setMargins(0, 0, 0, 0)
        } else {
            normalPlayerLayout?.let { original ->
                cardParams.setMargins(
                    original.marginLeft,
                    original.marginTop,
                    original.marginRight,
                    original.marginBottom
                )
            }
        }
        binding.playerCard.layoutParams = cardParams
        binding.playerCard.radius = if (fullscreen) {
            0f
        } else {
            resources.getDimension(R.dimen.tv_live_player_radius)
        }
        binding.btnPlayerFullscreen.setImageResource(
            if (fullscreen) R.drawable.ic_fullscreen_exit_24 else R.drawable.ic_fullscreen_24
        )
        binding.btnPlayerFullscreen.contentDescription = getString(
            if (fullscreen) R.string.tv_live_exit_fullscreen else R.string.tv_live_toggle_fullscreen
        )
        binding.root.requestLayout()
        if (!fullscreen) normalPlayerLayout = null
    }

    private fun setViewHeight(view: android.view.View, height: Int) {
        view.layoutParams = view.layoutParams.apply { this.height = height }
    }

    private fun applyResponsivePlayerHeight() {
        if (isFullscreen || isExitingFullscreen) return
        setViewHeight(
            binding.playerFrame,
            if (binding.playerCard.parent === binding.appBar) {
                responsivePlayerHeightPx()
            } else {
                ViewGroup.LayoutParams.MATCH_PARENT
            }
        )
    }

    private fun responsivePlayerHeightPx(): Int {
        val horizontalMargins = resources.getDimensionPixelSize(R.dimen.spacing_m) * 2
        val measuredPlayerWidth = binding.playerCard.width.takeIf { it > horizontalMargins }
        val availableWidth = measuredPlayerWidth
            ?: ((binding.root.width.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels) - horizontalMargins)
        val ratioHeight = availableWidth * 9 / 16
        val maxDp = if (resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) {
            PLAYER_MAX_HEIGHT_LANDSCAPE_DP
        } else {
            PLAYER_MAX_HEIGHT_PORTRAIT_DP
        }
        val maxHeight = (maxDp * resources.displayMetrics.density).toInt()
        return ratioHeight.coerceAtMost(maxHeight)
    }

    private fun setPlayerChromeVisible(visible: Boolean) {
        controlsHideRunnable?.let(mainHandler::removeCallbacks)
        isPlayerChromeVisible = visible
        val views = listOf(binding.playerControls, binding.btnPlayerFullscreen, binding.playerNowPlaying)
        views.forEach { view ->
            view.animate().cancel()
            if (visible) {
                view.alpha = 1f
                view.isVisible = playingItem != null
            } else if (view.isVisible) {
                view.animate()
                    .alpha(0f)
                    .setDuration(PLAYER_CHROME_FADE_MS)
                    .withEndAction { view.isVisible = false }
                    .start()
            }
        }
        if (visible && playbackState == PlaybackState.PLAYING) {
            scheduleControlsHide()
        }
    }

    private fun scheduleControlsHide() {
        controlsHideRunnable?.let(mainHandler::removeCallbacks)
        if (playbackState != PlaybackState.PLAYING) return
        controlsHideRunnable = Runnable {
            if (binding.playerControls.hasFocus() || binding.btnPlayerFullscreen.hasFocus()) {
                scheduleControlsHide()
            } else {
                setPlayerChromeVisible(false)
            }
        }.also {
            mainHandler.postDelayed(it, PLAYER_CHROME_TIMEOUT_MS)
        }
    }

    private fun restoreOrientationAfterFullscreen() {
        requestedOrientation = when (configurationOrientationBeforeFullscreen) {
            Configuration.ORIENTATION_PORTRAIT -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            Configuration.ORIENTATION_LANDSCAPE -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            else -> requestedOrientationBeforeFullscreen
        }
    }

    private fun hideKeyboard() {
        val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        imm.hideSoftInputFromWindow(binding.etSearch.windowToken, 0)
        binding.etSearch.clearFocus()
    }

    private fun buildGroupLabels(channels: List<TvChannelCatalogItem>): List<String> {
        if (channels.isEmpty()) return emptyList()
        val ranked = channels.groupingBy { it.group }
            .eachCount()
            .entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .map { it.key }
            .take(MAX_GROUP_CHIPS - 1)
        return listOf(GROUP_ALL) + ranked
    }

    private class ChannelAdapter(
        private val onClick: (TvChannelCatalogItem) -> Unit
    ) : ListAdapter<TvChannelCatalogItem, ChannelAdapter.VH>(Diff) {

        private var playingId: String? = null
        private var playbackState: PlaybackState = PlaybackState.IDLE

        init {
            setHasStableIds(true)
        }

        override fun getItemId(position: Int): Long = getItem(position).key.hashCode().toLong()

        fun setPlayingId(id: String?) {
            if (playingId == id) return
            val old = playingId
            playingId = id
            notifyPlayingChanged(old)
            notifyPlayingChanged(id)
        }

        fun setPlaybackState(state: PlaybackState) {
            if (playbackState == state) return
            playbackState = state
            notifyPlayingChanged(playingId)
        }

        private fun notifyPlayingChanged(id: String?) {
            if (id == null) return
            val idx = currentList.indexOfFirst { it.toSongId() == id }
            if (idx >= 0) notifyItemChanged(idx, PAYLOAD_PLAYING)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
            val binding = ItemTvChannelBinding.inflate(
                LayoutInflater.from(parent.context),
                parent,
                false
            )
            return VH(binding)
        }

        override fun onBindViewHolder(holder: VH, position: Int) {
            holder.bind(getItem(position), playingId, playbackState, onClick)
        }

        override fun onBindViewHolder(holder: VH, position: Int, payloads: MutableList<Any>) {
            if (payloads.contains(PAYLOAD_PLAYING)) {
                holder.bindPlaying(getItem(position), playingId, playbackState)
            } else {
                super.onBindViewHolder(holder, position, payloads)
            }
        }

        class VH(
            private val binding: ItemTvChannelBinding
        ) : RecyclerView.ViewHolder(binding.root) {
            fun bind(
                channel: TvChannelCatalogItem,
                playingId: String?,
                playbackState: PlaybackState,
                onClick: (TvChannelCatalogItem) -> Unit
            ) {
                binding.tvName.text = channel.name
                binding.tvLogoFallback.text = avatarLetter(channel)
                binding.ivLogo.isVisible = false
                binding.tvLogoFallback.isVisible = true
                if (channel.logoUrl.isNotBlank()) {
                    Glide.with(binding.ivLogo)
                        .load(TvLogoUrl.resolve(channel.logoUrl))
                        .fitCenter()
                        .override(LOGO_SIZE_PX, LOGO_SIZE_PX)
                        .apply(RequestOptions.timeoutOf(LOGO_REQUEST_TIMEOUT_MS))
                        .dontAnimate()
                        .listener(object : RequestListener<Drawable> {
                            override fun onLoadFailed(
                                e: GlideException?,
                                model: Any?,
                                target: Target<Drawable>,
                                isFirstResource: Boolean
                            ): Boolean {
                                binding.ivLogo.isVisible = false
                                binding.tvLogoFallback.isVisible = true
                                return false
                            }

                            override fun onResourceReady(
                                resource: Drawable,
                                model: Any,
                                target: Target<Drawable>?,
                                dataSource: DataSource,
                                isFirstResource: Boolean
                            ): Boolean {
                                binding.tvLogoFallback.isVisible = false
                                binding.ivLogo.isVisible = true
                                return false
                            }
                        })
                        .into(binding.ivLogo)
                } else {
                    Glide.with(binding.ivLogo).clear(binding.ivLogo)
                }
                binding.root.bindPressFeedback(PressFeedback.Style.ROW)
                binding.root.setOnClickListener { onClick(channel) }
                binding.root.setOnFocusChangeListener { _, focused ->
                    val scale = if (focused) FOCUSED_ROW_SCALE else 1f
                    binding.root.animate()
                        .scaleX(scale)
                        .scaleY(scale)
                        .setDuration(FOCUS_ANIMATION_MS)
                        .start()
                    binding.rowCard.cardElevation = if (focused) {
                        dpToPx(binding.root.context, FOCUSED_ROW_ELEVATION_DP).toFloat()
                    } else {
                        0f
                    }
                }
                bindPlaying(channel, playingId, playbackState)
            }

            fun bindPlaying(
                channel: TvChannelCatalogItem,
                playingId: String?,
                playbackState: PlaybackState
            ) {
                val id = channel.toSongId()
                val playing = id == playingId
                val preparing = playing && playbackState == PlaybackState.PREPARING
                val active = playing && playbackState == PlaybackState.PLAYING
                val ctx = binding.root.context
                val primary = ctx.resolveThemeColor(R.attr.brandPrimary)
                val normal = ctx.resolveThemeColor(R.attr.textPrimary)
                val secondary = ctx.resolveThemeColor(R.attr.textSecondary)
                val normalStroke = ctx.resolveThemeColor(R.attr.glassStrokeSoft)
                val normalSurface = ctx.resolveThemeColor(R.attr.glassSurfaceSoft)
                val selectedSurface = ctx.resolveThemeColor(R.attr.brandPrimaryLight)

                binding.tvName.setTextColor(if (playing) primary else normal)
                binding.tvLiveBadge.isVisible = playing
                binding.rowCard.strokeColor = if (playing) primary else normalStroke
                binding.rowCard.strokeWidth = if (playing) dpToPx(ctx, 2) else dpToPx(ctx, 1)
                binding.rowCard.setCardBackgroundColor(if (playing) selectedSurface else normalSurface)
                binding.rowProgress.isVisible = preparing
                binding.ivAction.isVisible = !preparing
                binding.ivAction.setImageResource(
                    if (active) R.drawable.ic_pause_24 else R.drawable.ic_play_24
                )
                binding.ivAction.imageTintList = android.content.res.ColorStateList.valueOf(
                    if (playing) primary else secondary
                )

                binding.tvMeta.text = when {
                    preparing -> ctx.getString(R.string.tv_live_connecting)
                    active -> ctx.getString(
                        R.string.tv_live_playing_source_count,
                        channel.sources.size
                    )
                    playing && playbackState == PlaybackState.ERROR ->
                        ctx.getString(R.string.tv_live_tap_to_retry)
                    playing -> ctx.getString(R.string.tv_live_paused)
                    channel.group.isNotBlank() -> ctx.getString(
                        R.string.tv_live_source_count_group,
                        channel.sources.size,
                        channel.group
                    )
                    else -> ctx.getString(R.string.tv_live_source_count, channel.sources.size)
                }
                binding.tvMeta.setTextColor(if (playing) primary else secondary)
                binding.rowCard.isSelected = playing
                binding.rowCard.contentDescription = buildString {
                    append(channel.name)
                    append(", ")
                    append(binding.tvMeta.text)
                }
            }

            private fun dpToPx(context: Context, dp: Int): Int =
                (dp * context.resources.displayMetrics.density).toInt()
        }

        private object Diff : DiffUtil.ItemCallback<TvChannelCatalogItem>() {
            override fun areItemsTheSame(a: TvChannelCatalogItem, b: TvChannelCatalogItem): Boolean =
                a.key == b.key

            override fun areContentsTheSame(a: TvChannelCatalogItem, b: TvChannelCatalogItem): Boolean = a == b
        }

        companion object {
            private const val PAYLOAD_PLAYING = "playing"
            private const val LOGO_SIZE_PX = 128
            private const val LOGO_REQUEST_TIMEOUT_MS = 3_000
            private const val FOCUS_ANIMATION_MS = 120L
            private const val FOCUSED_ROW_SCALE = 1.02f
            private const val FOCUSED_ROW_ELEVATION_DP = 5
        }
    }

    companion object {
        const val TV_ID_PREFIX = "tv:"
        private const val GROUP_ALL = "全部"
        private const val MAX_GROUP_CHIPS = 16
        private const val TAG_PLAYER = "TvLivePlayer"
        private const val PLAYER_USER_AGENT = "MusicPlayer/1.0 (Android; TV Live)"
        private const val SOURCE_PREFS = "tv_live_successful_sources"
        private const val LAST_CHANNEL_KEY = "last_channel_key"
        private const val LAST_GROUP_KEY = "last_group"
        private const val FULLSCREEN_EXIT_FALLBACK_MS = 800L
        private const val FILTER_DEBOUNCE_MS = 140L
        /** First source connect budget (Exo live open + first keyframe). */
        private const val SOURCE_START_TIMEOUT_MS = 4_000L
        /** Subsequent sources: fail fast so multi-source channels recover quicker. */
        private const val SOURCE_FAILOVER_TIMEOUT_MS = 2_500L
        private const val FAILED_SOURCE_COOLDOWN_MS = 10L * 60L * 1000L
        private const val CHANNEL_PREFETCH_COUNT = 4
        private const val CHANNEL_VIEW_CACHE_SIZE = 12
        private const val PLAYER_CHROME_TIMEOUT_MS = 3_000L
        private const val PLAYER_CHROME_FADE_MS = 180L
        private const val PLAYER_MAX_HEIGHT_PORTRAIT_DP = 260
        private const val PLAYER_MAX_HEIGHT_LANDSCAPE_DP = 190
        private const val DISABLED_ALPHA = 0.42f

        fun intent(context: Context): Intent = Intent(context, TvLiveActivity::class.java)

        private fun TvChannelCatalogItem.toSongId(): String =
            TV_ID_PREFIX + key.hashCode().toUInt().toString(16)

        private fun avatarLetter(channel: TvChannelCatalogItem): String {
            val name = channel.name.trim()
            if (name.startsWith("CCTV", ignoreCase = true)) return "C"
            val group = channel.group.trim()
            return group.take(1).ifBlank { name.take(1) }.ifBlank { "频" }
        }
    }
}
