package com.music.player

import android.Manifest
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.doOnLayout
import androidx.core.view.updatePadding
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.media3.common.C
import androidx.media3.common.Player
import com.bumptech.glide.Glide
import com.music.player.data.repository.AlbumRepository
import com.music.player.data.repository.MusicRepository
import com.music.player.data.auth.AuthSessionState
import com.music.player.data.settings.MusicSourcePreferences
import com.music.player.databinding.ActivityMainBinding
import com.music.player.playback.PlaybackCoordinator
import com.music.player.ui.activity.LoginActivity
import com.music.player.ui.fragment.DiscoverFragment
import com.music.player.ui.fragment.LibraryFragment
import com.music.player.ui.fragment.NowPlayingBottomSheetFragment
import com.music.player.ui.fragment.PlaylistsFragment
import com.music.player.ui.fragment.ProfileFragment
import com.music.player.ui.fragment.PlaylistSongsFragment
import com.music.player.ui.fragment.QueueBottomSheetFragment
import com.music.player.ui.fragment.RootTabInteraction
import com.music.player.ui.viewmodel.AuthViewModel
import com.music.player.ui.viewmodel.LibraryViewModel
import com.music.player.ui.viewmodel.MusicViewModel
import com.music.player.ui.viewmodel.UpdateState
import com.music.player.ui.viewmodel.UpdateViewModel
import com.music.player.update.AppUpdateDialogs
import com.music.player.update.AppUpdateInstaller
import com.music.player.update.AppUpdatePreferences
import com.music.player.ui.util.ImmersiveHeaderBackground
import com.music.player.ui.util.PlayerUiStyler
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.util.safeDrawingInsets
import com.music.player.ui.util.resolveThemeColorStateList
import com.music.player.ui.util.resolveThemeColor
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    companion object {
        private const val TAG_DISCOVER = "tab_discover"
        private const val TAG_LIBRARY = "tab_library"
        private const val TAG_PLAYLISTS = "tab_playlists"
        private const val TAG_PROFILE = "tab_profile"

        const val EXTRA_FROM_LOGIN = "extra_from_login"
        const val EXTRA_INITIAL_TAB_ID = "extra_initial_tab_id"
        const val EXTRA_FOCUS_LIBRARY_SEARCH = "extra_focus_library_search"

        private const val NOTIFICATION_PERMISSION_PREFS = "notification_permission_prefs"
        private const val KEY_NOTIFICATION_PERMISSION_REQUESTED = "requested"
    }

    val player: Player?
        get() = PlaybackCoordinator.playerOrNull()

    private lateinit var binding: ActivityMainBinding
    private lateinit var musicViewModel: MusicViewModel
    private lateinit var authViewModel: AuthViewModel
    private lateinit var libraryViewModel: LibraryViewModel
    private lateinit var updateViewModel: UpdateViewModel
    private lateinit var appUpdateInstaller: AppUpdateInstaller
    private lateinit var appUpdatePreferences: AppUpdatePreferences
    private lateinit var immersiveHeaderBackground: ImmersiveHeaderBackground
    private lateinit var insetsController: WindowInsetsControllerCompat

    private var suppressNavCallback = false
    private var currentTabId: Int = R.id.nav_discover
    private var topSystemBarInset: Int = 0
    private var miniProgressJob: Job? = null
    private var hasRestoredRecentSong = false
    private var isNavigatingToLogin = false

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            updateMiniPlayPauseIcon(shouldShowAsPlaying(player))
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            val p = player ?: return
            updateMiniPlayPauseIcon(shouldShowAsPlaying(p))
            updateMiniProgress()
        }

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            if (playWhenReady) {
                requestNotificationPermissionForPlaybackIfNeeded()
            }
        }

        override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
            Toast.makeText(
                this@MainActivity,
                error.localizedMessage ?: getString(R.string.playback_error_generic),
                Toast.LENGTH_SHORT
            ).show()
            updateMiniPlayPauseIcon(false)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.prepareActivity(this)
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        PlayerUiStyler.applyMiniPlayer(binding, this)

        setupEdgeToEdge()

        immersiveHeaderBackground = ImmersiveHeaderBackground(
            this,
            binding.immersiveHeader.ivHeaderBackground
        ) { suggestion ->
            insetsController.isAppearanceLightStatusBars = suggestion.lightSystemBars
            insetsController.isAppearanceLightNavigationBars = suggestion.lightSystemBars
            binding.immersiveHeader.viewHeaderScrim.alpha = suggestion.topScrimAlpha
        }

        musicViewModel = ViewModelProvider(this)[MusicViewModel::class.java]
        authViewModel = ViewModelProvider(this)[AuthViewModel::class.java]
        if (!authViewModel.isLoggedIn()) {
            isNavigatingToLogin = true
            navigateToLogin()
            return
        }
        libraryViewModel = ViewModelProvider(this)[LibraryViewModel::class.java]

        updateViewModel = ViewModelProvider(this)[UpdateViewModel::class.java]
        appUpdateInstaller = AppUpdateInstaller(this)
        appUpdatePreferences = AppUpdatePreferences(this)

        PlaybackCoordinator.init(applicationContext)
        observePlayerAttachment()
        maybeResetPlaybackAfterFreshLogin()
        attachPlayerListener()

        setSupportActionBar(binding.toolbar)
        supportActionBar?.setDisplayShowTitleEnabled(false)
        setupTopAppBar()
        supportFragmentManager.addOnBackStackChangedListener { syncTopBarState() }

        setupMiniPlayer()
        setupObservers()
        observeSessionExpiry()
        setupUpdateObservers()
        setupBottomNavigation(savedInstanceState)
        refreshForMusicSourceChangeIfNeeded()

        libraryViewModel.prefetch()

        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    val top = supportFragmentManager.fragments
                        .lastOrNull { it.id == R.id.fragmentContainer && it.isVisible }
                    val isRootTab = when (top) {
                        is DiscoverFragment, is LibraryFragment, is PlaylistsFragment, is ProfileFragment -> true
                        else -> false
                    }
                    if (top != null && !isRootTab && supportFragmentManager.backStackEntryCount > 0) {
                        supportFragmentManager.popBackStack()
                        return
                    }

                    if (currentTabId != R.id.nav_discover) {
                        binding.bottomNav.selectedItemId = R.id.nav_discover
                    } else {
                        isEnabled = false
                        onBackPressedDispatcher.onBackPressed()
                    }
                }
            }
        )

        syncTopBarState()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleInitialTabIntent()
    }

    override fun onStart() {
        super.onStart()
        PlayerUiStyler.applyMiniPlayer(binding, this)
        insetsController.show(WindowInsetsCompat.Type.systemBars())
        attachPlayerListener()
        startMiniProgressUpdates()
        maybeCheckForAppUpdate()
    }

    override fun onResume() {
        super.onResume()
        if (::appUpdateInstaller.isInitialized) {
            appUpdateInstaller.resumePendingWork()
        }
        refreshForMusicSourceChangeIfNeeded()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && ::insetsController.isInitialized) {
            insetsController.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    private fun attachPlayerListener() {
        val p = player ?: return
        p.removeListener(playerListener)
        p.addListener(playerListener)
        updateMiniPlayPauseIcon(shouldShowAsPlaying(p))
    }

    private fun observePlayerAttachment() {
        lifecycleScope.launch {
            PlaybackCoordinator.playerAttached.collect { attached ->
                if (!attached) return@collect
                attachPlayerListener()
                updateMiniPlayPauseIcon(shouldShowAsPlaying(player))
            }
        }
    }

    private fun requestNotificationPermissionForPlaybackIfNeeded() {
        if (Build.VERSION.SDK_INT < 33) return
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        if (granted) return

        val prefs = getSharedPreferences(NOTIFICATION_PERMISSION_PREFS, MODE_PRIVATE)
        if (prefs.getBoolean(KEY_NOTIFICATION_PERMISSION_REQUESTED, false)) return
        prefs.edit().putBoolean(KEY_NOTIFICATION_PERMISSION_REQUESTED, true).apply()
        notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    private fun setupUpdateObservers() {
        updateViewModel.state.observe(this) { state ->
            when (state) {
                is UpdateState.Idle -> Unit
                is UpdateState.Loading -> Unit
                is UpdateState.Latest -> updateViewModel.reset()
                is UpdateState.UpdateAvailable -> {
                    appUpdatePreferences.clearSkippedIfOlderThan(state.latest.buildNumber)
                    if (!state.userInitiated &&
                        appUpdatePreferences.shouldSuppressAutoPrompt(
                            buildNumber = state.latest.buildNumber,
                            force = state.force
                        )
                    ) {
                        updateViewModel.reset()
                        return@observe
                    }

                    AppUpdateDialogs.show(
                        activity = this,
                        currentVersion = BuildConfig.VERSION_NAME,
                        currentBuildNumber = BuildConfig.VERSION_CODE,
                        latest = state.latest,
                        force = state.force,
                        onConfirm = {
                            val url = state.latest.downloadUrl?.trim().orEmpty()
                            if (url.isBlank()) {
                                Toast.makeText(this, getString(R.string.update_no_url), Toast.LENGTH_SHORT).show()
                            } else {
                                appUpdateInstaller.downloadAndInstall(url, state.latest.version)
                            }
                        },
                        onLater = {
                            appUpdatePreferences.markSkipped(state.latest.buildNumber)
                        }
                    )
                    updateViewModel.reset()
                }
                is UpdateState.Error -> updateViewModel.reset()
            }
        }
    }

    private fun refreshForMusicSourceChangeIfNeeded() {
        if (!::musicViewModel.isInitialized || !::libraryViewModel.isInitialized) return
        val currentSource = MusicSourcePreferences.activeSource(this).storageValue
        if (!musicViewModel.updateActiveSource(currentSource)) return

        MusicRepository.clearCaches()
        AlbumRepository.clearCaches()
        PlaybackCoordinator.clearResolvedUrlCache()
        musicViewModel.clearSourceDependentState()
        libraryViewModel.prefetch(forceRefresh = true)

        supportFragmentManager.fragments
            .filterIsInstance<RootTabInteraction>()
            .forEach { it.onMusicSourceChanged() }
    }

    private fun maybeCheckForAppUpdate() {
        updateViewModel.check(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, userInitiated = false)
    }

    @Suppress("DEPRECATION")
    private fun setupEdgeToEdge() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= 29) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
        insetsController = WindowInsetsControllerCompat(window, binding.root).apply {
            isAppearanceLightStatusBars = !isNightMode()
            isAppearanceLightNavigationBars = !isNightMode()
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            show(WindowInsetsCompat.Type.systemBars())
        }
        ViewCompat.setOnApplyWindowInsetsListener(binding.toolbar) { view, insets ->
            val bars = insets.safeDrawingInsets()
            topSystemBarInset = bars.top
            view.updatePadding(top = bars.top)
            binding.root.post { updateMainContentPadding() }
            insets
        }
        ViewCompat.setOnApplyWindowInsetsListener(binding.bottomNavContainer) { view, insets ->
            val bars = insets.safeDrawingInsets()
            view.updatePadding(bottom = bars.bottom.coerceAtLeast(0))
            insets
        }
        binding.toolbar.requestApplyInsets()
        binding.bottomNavContainer.requestApplyInsets()
        binding.root.doOnLayout { updateMainContentPadding() }
        binding.appBar.doOnLayout { updateMainContentPadding() }
        binding.bottomNavContainer.doOnLayout { updateMainContentPadding() }
        binding.miniPlayer.doOnLayout { updateMainContentPadding() }
    }

    private fun isNightMode(): Boolean {
        val mode = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return mode == Configuration.UI_MODE_NIGHT_YES
    }

    fun navigateToLogin() {
        startActivity(Intent(this, LoginActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        })
        finish()
    }

    private fun observeSessionExpiry() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                AuthSessionState.expired.collect { expired ->
                    if (!expired || isNavigatingToLogin) return@collect
                    isNavigatingToLogin = true
                    PlaybackCoordinator.resetPlayback()
                    navigateToLogin()
                }
            }
        }
    }

    private fun setupBottomNavigation(savedInstanceState: Bundle?) {
        binding.bottomNav.isItemActiveIndicatorEnabled = false
        binding.bottomNav.setOnItemSelectedListener { item ->
            if (!suppressNavCallback) {
                switchToTab(item.itemId)
            }
            true
        }
        binding.bottomNav.setOnItemReselectedListener { item ->
            val fragment = supportFragmentManager.findFragmentByTag(tagForTab(item.itemId))
            (fragment as? RootTabInteraction)?.onTabReselected()
        }

        val initialTab = if (savedInstanceState == null) {
            intent.getIntExtra(EXTRA_INITIAL_TAB_ID, R.id.nav_discover)
        } else {
            binding.bottomNav.selectedItemId
        }
        suppressNavCallback = true
        binding.bottomNav.selectedItemId = initialTab
        suppressNavCallback = false
        switchToTab(initialTab)
        binding.bottomNav.post { tuneBottomNavigationItemSpacing() }
    }

    private fun tuneBottomNavigationItemSpacing() {
        val menuView = binding.bottomNav.getChildAt(0) as? ViewGroup ?: return
        val iconContainerId = com.google.android.material.R.id.navigation_bar_item_icon_container
        val iconBottomMargin = (2 * resources.displayMetrics.density).toInt()
        for (index in 0 until menuView.childCount) {
            val iconContainer = menuView.getChildAt(index).findViewById<View>(iconContainerId) ?: continue
            val params = iconContainer.layoutParams as? ViewGroup.MarginLayoutParams ?: continue
            params.bottomMargin = iconBottomMargin
            iconContainer.layoutParams = params
        }
    }

    private fun setupTopAppBar() {
        updateToolbar()
    }

    private fun handleInitialTabIntent() {
        val requestedTab = intent.getIntExtra(EXTRA_INITIAL_TAB_ID, View.NO_ID)
        if (requestedTab == View.NO_ID) return
        if (::binding.isInitialized && binding.bottomNav.selectedItemId != requestedTab) {
            binding.bottomNav.selectedItemId = requestedTab
        }
        intent.removeExtra(EXTRA_INITIAL_TAB_ID)
    }

    private fun tagForTab(tabId: Int): String = when (tabId) {
        R.id.nav_library -> TAG_LIBRARY
        R.id.nav_playlists -> TAG_PLAYLISTS
        R.id.nav_profile -> TAG_PROFILE
        else -> TAG_DISCOVER
    }

    private fun switchToTab(tabId: Int) {
        // Switching tabs resets any pushed detail pages (single-stack behavior).
        supportFragmentManager.popBackStackImmediate(
            null,
            androidx.fragment.app.FragmentManager.POP_BACK_STACK_INCLUSIVE
        )

        currentTabId = tabId
        updateToolbar()

        val fm = supportFragmentManager
        val transaction = fm.beginTransaction()
            .setReorderingAllowed(true)

        // Hide every fragment that lives in the main container (including overlay/detail pages).
        fm.fragments
            .filter { it.id == R.id.fragmentContainer }
            .forEach { transaction.hide(it) }

        val tag = tagForTab(tabId)

        val existing = fm.findFragmentByTag(tag)
        if (existing == null) {
            val fragment = when (tag) {
                TAG_LIBRARY -> LibraryFragment()
                TAG_PLAYLISTS -> PlaylistsFragment()
                TAG_PROFILE -> ProfileFragment()
                else -> DiscoverFragment()
            }
            transaction.add(R.id.fragmentContainer, fragment, tag)
        } else {
            transaction.show(existing)
        }

        transaction.commitNow()

        syncTopBarState()
    }

    fun pushDetail(fragment: Fragment) {
        val fm = supportFragmentManager
        val transaction = fm.beginTransaction()
            .setReorderingAllowed(true)

        fm.fragments
            .filter { it.id == R.id.fragmentContainer && it.isVisible }
            .forEach { transaction.hide(it) }

        transaction
            .add(R.id.fragmentContainer, fragment)
            .addToBackStack(null)
            .commit()

        syncTopBarState()
    }

    fun selectRootTab(tabId: Int) {
        if (!::binding.isInitialized) return
        if (binding.bottomNav.selectedItemId == tabId) {
            switchToTab(tabId)
            return
        }
        binding.bottomNav.selectedItemId = tabId
    }

    private fun syncTopBarState() {
        val top = supportFragmentManager.fragments
            .lastOrNull { it.id == R.id.fragmentContainer && it.isVisible }

        val isRootTab = when (top) {
            is DiscoverFragment, is LibraryFragment, is PlaylistsFragment, is ProfileFragment -> true
            else -> false
        }

        // Detail pages use Android system back / gesture navigation. Keeping a global toolbar
        // here duplicates page headers and creates a large blank top inset.
        val showBack = false
        binding.toolbar.navigationIcon = null
        binding.toolbar.setNavigationOnClickListener {
            Unit
        }
        updateToolbarForVisiblePage(showBack = showBack)
    }

    fun setBottomNavVisible(visible: Boolean) {
        binding.bottomNavContainer.visibility = if (visible) View.VISIBLE else View.GONE
        binding.root.post { updateMainContentPadding() }
    }

    private fun updateToolbar() {
        binding.toolbar.title = ""
        binding.toolbar.subtitle = null
        updateToolbarForVisiblePage(showBack = binding.toolbar.navigationIcon != null)
    }

    private fun updateToolbarForVisiblePage(showBack: Boolean) {
        binding.appBar.visibility = if (showBack) View.VISIBLE else View.GONE
        binding.root.post { updateMainContentPadding() }
    }

    private fun setupObservers() {
        musicViewModel.currentSong.observe(this) { song ->
            immersiveHeaderBackground.setImageUrl(null)
            if (song == null) {
                binding.miniPlayer.visibility = View.GONE
                binding.miniProgress.isIndeterminate = false
                binding.miniProgress.progress = 0
                resetMiniCoverRotation()
                updateMainContentPadding()
                return@observe
            }

            binding.miniPlayer.visibility = View.VISIBLE
            val artists = song.artists.joinToString(", ") { it.name }
            val artistLabel = artists.ifBlank { getString(R.string.item_artist_placeholder) }
            binding.tvMiniTitle.text = SpannableStringBuilder()
                .append(song.name)
                .append(" - ")
                .append(artistLabel)
                .apply {
                    setSpan(
                        ForegroundColorSpan(resolveThemeColor(R.attr.textSecondary)),
                        song.name.length + 3,
                        length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
            binding.tvMiniArtist.text = artistLabel
            binding.miniProgress.isIndeterminate = false
            binding.miniProgress.progress = 0

            val coverUrl = song.album.picUrl.takeIf { it.isNotBlank() }
            if (coverUrl == null) {
                binding.ivMiniCover.setImageResource(R.drawable.ic_music_note_24)
                binding.ivMiniCover.imageTintList = resolveThemeColorStateList(R.attr.brandPrimary)
            } else {
                binding.ivMiniCover.imageTintList = null
                Glide.with(this)
                    .load(coverUrl)
                    .placeholder(R.drawable.ic_music_note_24)
                    .centerCrop()
                    .into(binding.ivMiniCover)
            }

            updateMiniPlayPauseIcon(shouldShowAsPlaying(player))
            libraryViewModel.addToHistory(song)
            updateMainContentPadding()
        }

        musicViewModel.error.observe(this) { error ->
            if (!error.isNullOrBlank()) {
                Toast.makeText(this, error, Toast.LENGTH_SHORT).show()
            }
        }

        libraryViewModel.message.observe(this) { message ->
            message ?: return@observe
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
            libraryViewModel.consumeMessage()
        }

        libraryViewModel.latestHistorySong.observe(this) { song ->
            if (hasRestoredRecentSong) return@observe
            if (musicViewModel.currentSong.value != null) return@observe
            song ?: return@observe
            hasRestoredRecentSong = true
            musicViewModel.restorePreviewSong(song)
        }
    }

    private fun setupMiniPlayer() {
        binding.miniProgress.max = 1000

        binding.btnMiniPlayPause.setOnClickListener {
            it.animate().scaleX(0.85f).scaleY(0.85f).setDuration(80).withEndAction {
                it.animate().scaleX(1f).scaleY(1f).setDuration(120).start()
            }.start()
            val p = player ?: return@setOnClickListener
            val currentSong = musicViewModel.currentSong.value
            if (p.isPlaying) {
                p.pause()
            } else if (p.mediaItemCount == 0 && currentSong != null) {
                musicViewModel.playSong(currentSong)
            } else {
                if (p.playbackState == Player.STATE_IDLE && p.mediaItemCount > 0) {
                    p.prepare()
                }
                p.play()
            }
            updateMiniPlayPauseIcon(shouldShowAsPlaying(p))
        }

        binding.btnMiniQueue.setOnClickListener {
            it.animate().scaleX(0.85f).scaleY(0.85f).setDuration(80).withEndAction {
                it.animate().scaleX(1f).scaleY(1f).setDuration(120).start()
            }.start()
            musicViewModel.skipNext()
        }

        binding.miniPlayer.setOnClickListener {
            it.animate().scaleX(0.98f).scaleY(0.98f).setDuration(80).withEndAction {
                it.animate().scaleX(1f).scaleY(1f).setDuration(120).start()
            }.start()
            if (musicViewModel.currentSong.value != null) {
                NowPlayingBottomSheetFragment().show(supportFragmentManager, "now_playing")
            }
        }
    }

    fun animatePlayerBackground(expanded: Boolean) {
        val targetScale = if (expanded) 0.94f else 1f
        val targetTranslationY = if (expanded) 24f * resources.displayMetrics.density else 0f
        val targetAlpha = if (expanded) 0.78f else 1f
        binding.root.animate()
            .scaleX(targetScale)
            .scaleY(targetScale)
            .translationY(targetTranslationY)
            .alpha(targetAlpha)
            .setDuration(if (expanded) 600L else 500L)
            .setInterpolator(android.view.animation.AccelerateDecelerateInterpolator())
            .start()
    }

    private fun maybeResetPlaybackAfterFreshLogin() {
        if (!intent.getBooleanExtra(EXTRA_FROM_LOGIN, false)) return
        val p = PlaybackCoordinator.playerOrNull()
        if (p?.isPlaying == true) return
        PlaybackCoordinator.resetPlayback()
    }

    private fun updateMiniPlayPauseIcon(isPlaying: Boolean) {
        val icon = if (isPlaying) R.drawable.ic_pause_24 else R.drawable.ic_play_24
        val contentDesc = if (isPlaying) R.string.content_desc_pause else R.string.content_desc_play
        binding.btnMiniPlayPause.setImageResource(icon)
        binding.btnMiniPlayPause.contentDescription = getString(contentDesc)
        binding.tvMiniTitle.isSelected = isPlaying
        resetMiniCoverRotation()
    }

    private fun shouldShowAsPlaying(player: Player?): Boolean {
        player ?: return false
        if (player.playbackState == Player.STATE_ENDED) return false
        if (player.isPlaying) return true
        return player.playWhenReady
    }

    private fun resetMiniCoverRotation() {
        binding.ivMiniCover.rotation = 0f
    }

    private fun startMiniProgressUpdates() {
        miniProgressJob?.cancel()
        miniProgressJob = lifecycleScope.launch {
            while (isActive) {
                updateMiniProgress()
                delay(500)
            }
        }
    }

    private fun updateMiniProgress() {
        if (binding.miniPlayer.visibility != View.VISIBLE) return
        val p = player ?: return
        val durationMs = p.duration
        if (durationMs <= 0L || durationMs == C.TIME_UNSET) {
            binding.miniProgress.isIndeterminate = false
            binding.miniProgress.progress = 0
            return
        }
        binding.miniProgress.isIndeterminate = false
        val positionMs = p.currentPosition.coerceAtLeast(0L)
        val progress = ((positionMs * 1000) / durationMs).toInt().coerceIn(0, 1000)
        binding.miniProgress.progress = progress
    }

    private fun updateMainContentPadding() {
        val topInset = if (isRootTabVisible()) {
            0
        } else {
            binding.appBar.bottom.coerceAtLeast(0)
        }
        val bottomInset = (binding.root.height - binding.bottomContentBarrier.top).coerceAtLeast(0)
        binding.fragmentContainer.updatePadding(
            top = topInset,
            bottom = bottomInset
        )
    }

    private fun isRootTabVisible(): Boolean {
        val top = supportFragmentManager.fragments
            .lastOrNull { it.id == R.id.fragmentContainer && it.isVisible }
        return when (top) {
            is DiscoverFragment, is LibraryFragment, is PlaylistsFragment, is ProfileFragment -> true
            else -> false
        }
    }

    override fun onStop() {
        super.onStop()
        miniProgressJob?.cancel()
        miniProgressJob = null
    }

    override fun onDestroy() {
        super.onDestroy()
        miniProgressJob?.cancel()
        miniProgressJob = null
        player?.removeListener(playerListener)
        if (::appUpdateInstaller.isInitialized) {
            appUpdateInstaller.dispose()
        }
    }

}
