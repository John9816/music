package com.music.player

import android.Manifest
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.view.View
import android.view.animation.LinearInterpolator
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.core.app.ActivityCompat
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
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.C
import androidx.media3.common.Player
import com.bumptech.glide.Glide
import com.music.player.databinding.ActivityMainBinding
import com.music.player.playback.PlaybackCoordinator
import com.music.player.ui.activity.LoginActivity
import com.music.player.ui.fragment.DiscoverFragment
import com.music.player.ui.fragment.LibraryFragment
import com.music.player.ui.fragment.NowPlayingBottomSheetFragment
import com.music.player.ui.fragment.PlaylistsFragment
import com.music.player.ui.fragment.ProfileFragment
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
        private var hasCheckedForUpdatesThisProcess = false
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
    private var miniCoverAnimator: ObjectAnimator? = null
    private var hasRestoredRecentSong = false

    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            updateMiniPlayPauseIcon(shouldShowAsPlaying(player))
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            val p = player ?: return
            updateMiniPlayPauseIcon(shouldShowAsPlaying(p))
            updateMiniProgress()
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
        libraryViewModel = ViewModelProvider(this)[LibraryViewModel::class.java]

        if (!authViewModel.isLoggedIn()) {
            navigateToLogin()
            return
        }

        updateViewModel = ViewModelProvider(this)[UpdateViewModel::class.java]
        appUpdateInstaller = AppUpdateInstaller(this)
        appUpdatePreferences = AppUpdatePreferences(this)

        requestNotificationPermissionIfNeeded()

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
        setupUpdateObservers()
        setupBottomNavigation(savedInstanceState)

        libraryViewModel.prefetch()
        maybeCheckForAppUpdate(savedInstanceState)

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
        insetsController.hide(WindowInsetsCompat.Type.systemBars())
        attachPlayerListener()
        startMiniProgressUpdates()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && ::insetsController.isInitialized) {
            insetsController.hide(WindowInsetsCompat.Type.systemBars())
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

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < 33) return
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2001)
        }
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

    private fun maybeCheckForAppUpdate(savedInstanceState: Bundle?) {
        if (savedInstanceState != null) return
        if (hasCheckedForUpdatesThisProcess) return
        hasCheckedForUpdatesThisProcess = true
        updateViewModel.check(BuildConfig.VERSION_CODE, userInitiated = false)
    }

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
            hide(WindowInsetsCompat.Type.systemBars())
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
            val floatingOffset = resources.getDimensionPixelSize(R.dimen.spacing_s)
            view.updatePadding(bottom = (bars.bottom - floatingOffset).coerceAtLeast(0))
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

    private fun setupBottomNavigation(savedInstanceState: Bundle?) {
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

        transaction.commit()

        syncTopBarState()
    }

    fun pushDetail(fragment: Fragment) {
        val fm = supportFragmentManager
        val transaction = fm.beginTransaction()

        fm.fragments
            .filter { it.id == R.id.fragmentContainer && it.isVisible }
            .forEach { transaction.hide(it) }

        transaction
            .add(R.id.fragmentContainer, fragment)
            .addToBackStack(null)
            .commit()

        syncTopBarState()
    }

    private fun syncTopBarState() {
        val top = supportFragmentManager.fragments
            .lastOrNull { it.id == R.id.fragmentContainer && it.isVisible }

        val isRootTab = when (top) {
            is DiscoverFragment, is LibraryFragment, is PlaylistsFragment, is ProfileFragment -> true
            else -> false
        }

        val showBack = top != null && !isRootTab
        binding.toolbar.navigationIcon = if (showBack) {
            ContextCompat.getDrawable(this, R.drawable.ic_arrow_back_24)
        } else {
            null
        }
        binding.toolbar.setNavigationOnClickListener {
            if (showBack) {
                supportFragmentManager.popBackStack()
            }
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
                updateMiniCoverRotation(false)
                updateMainContentPadding()
                return@observe
            }

            binding.miniPlayer.visibility = View.VISIBLE
            val artists = song.artists.joinToString(", ") { it.name }
            binding.tvMiniTitle.text = "${song.name} - $artists"
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
                    .circleCrop()
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
            if (musicViewModel.currentSong.value != null) {
                QueueBottomSheetFragment().show(supportFragmentManager, "queue")
            }
        }

        binding.miniPlayer.setOnClickListener {
            if (musicViewModel.currentSong.value != null) {
                NowPlayingBottomSheetFragment().show(supportFragmentManager, "now_playing")
            }
        }
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
        updateMiniCoverRotation(isPlaying)
    }

    private fun shouldShowAsPlaying(player: Player?): Boolean {
        player ?: return false
        if (player.playbackState == Player.STATE_ENDED) return false
        if (player.isPlaying) return true
        return player.playWhenReady
    }

    private fun updateMiniCoverRotation(isPlaying: Boolean) {
        if (binding.miniPlayer.visibility != View.VISIBLE) {
            miniCoverAnimator?.cancel()
            miniCoverAnimator = null
            binding.ivMiniCover.rotation = 0f
            return
        }

        if (!isPlaying) {
            miniCoverAnimator?.pause()
            return
        }

        val animator = miniCoverAnimator ?: ObjectAnimator.ofFloat(binding.ivMiniCover, View.ROTATION, 0f, 360f)
            .apply {
                duration = 12000L
                interpolator = LinearInterpolator()
                repeatCount = ValueAnimator.INFINITE
                repeatMode = ValueAnimator.RESTART
            }
            .also { miniCoverAnimator = it }

        if (animator.isStarted) {
            animator.resume()
        } else {
            animator.start()
        }
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
        miniCoverAnimator?.pause()
    }

    override fun onDestroy() {
        super.onDestroy()
        miniProgressJob?.cancel()
        miniProgressJob = null
        miniCoverAnimator?.cancel()
        miniCoverAnimator = null
        player?.removeListener(playerListener)
        if (::appUpdateInstaller.isInitialized) {
            appUpdateInstaller.dispose()
        }
    }

    private fun applyEdgeToEdge(rootView: View, lightSystemBars: Boolean): WindowInsetsControllerCompat {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= 29) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }

        return WindowInsetsControllerCompat(window, rootView).apply {
            isAppearanceLightStatusBars = lightSystemBars
            isAppearanceLightNavigationBars = lightSystemBars
            hide(WindowInsetsCompat.Type.navigationBars())
        }
    }

    private fun View.applyStatusBarInsetPadding() {
        applySystemBarInsetPadding(applyTop = true)
    }

    private fun View.applyNavigationBarInsetPadding() {
        applySystemBarInsetPadding(applyBottom = true)
    }

    private fun View.applySystemBarInsetPadding(
        applyTop: Boolean = false,
        applyBottom: Boolean = false
    ) {
        val initialTop = paddingTop
        val initialBottom = paddingBottom
        ViewCompat.setOnApplyWindowInsetsListener(this) { view, insets ->
            val bars = insets.safeDrawingInsets()
            view.updatePadding(
                top = initialTop + if (applyTop) bars.top else 0,
                bottom = initialBottom + if (applyBottom) bars.bottom else 0
            )
            insets
        }
        ViewCompat.requestApplyInsets(this)
    }
}
