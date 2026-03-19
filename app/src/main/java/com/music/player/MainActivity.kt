package com.music.player

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.view.Gravity
import android.view.LayoutInflater
import android.view.animation.LinearInterpolator
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.widget.Toolbar
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
import com.music.player.ui.activity.SettingsActivity
import com.music.player.ui.fragment.DiscoverFragment
import com.music.player.ui.fragment.LibraryFragment
import com.music.player.ui.fragment.NowPlayingBottomSheetFragment
import com.music.player.ui.fragment.PlaylistsFragment
import com.music.player.ui.fragment.ProfileFragment
import com.music.player.ui.fragment.QueueBottomSheetFragment
import com.music.player.ui.viewmodel.AuthViewModel
import com.music.player.ui.viewmodel.LibraryViewModel
import com.music.player.ui.viewmodel.MusicViewModel
import com.music.player.ui.viewmodel.UpdateState
import com.music.player.ui.viewmodel.UpdateViewModel
import com.music.player.update.AppUpdateInstaller
import com.music.player.update.AppUpdatePreferences
import com.music.player.update.showAppUpdateDialog
import com.music.player.ui.util.ImmersiveHeaderBackground
import com.music.player.ui.util.ThemeManager
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
    private var discoverSearchView: View? = null

    private var suppressNavCallback = false
    private var currentTabId: Int = R.id.nav_discover
    private var miniProgressJob: Job? = null
    private var miniCoverAnimator: ObjectAnimator? = null
    private var hasRestoredRecentSong = false

    private val settingsLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val shouldRecreate = result.resultCode == Activity.RESULT_OK &&
                result.data?.getBooleanExtra(SettingsActivity.EXTRA_SHOULD_RECREATE_MAIN, false) == true
            if (shouldRecreate) {
                recreate()
            }
        }

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
        ThemeManager.applySavedNightMode(this)
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

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
        attachPlayerListener()
        startMiniProgressUpdates()
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

                    showAppUpdateDialog(
                        currentVersion = BuildConfig.VERSION_NAME,
                        currentBuildNumber = BuildConfig.VERSION_CODE,
                        latest = state.latest,
                        force = state.force,
                        onConfirm = {
                            val url = state.latest.downloadUrl?.trim().orEmpty()
                            if (url.isBlank()) {
                                Toast.makeText(this, getString(R.string.update_no_url), Toast.LENGTH_SHORT).show()
                                return@showAppUpdateDialog
                            }
                            appUpdateInstaller.downloadAndInstall(url, state.latest.version)
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
        }
        ViewCompat.setOnApplyWindowInsetsListener(binding.toolbar) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(top = bars.top)
            insets
        }
        ViewCompat.setOnApplyWindowInsetsListener(binding.bottomNav) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(bottom = bars.bottom)
            insets
        }
        binding.toolbar.requestApplyInsets()
        binding.bottomNav.requestApplyInsets()
        binding.root.doOnLayout { updateMainContentPadding() }
        binding.appBar.doOnLayout { updateMainContentPadding() }
        binding.bottomNav.doOnLayout { updateMainContentPadding() }
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
        binding.toolbar.menu.clear()
        binding.toolbar.inflateMenu(R.menu.top_app_bar)
        binding.toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_search_tab -> {
                    openSongSearch()
                    true
                }
                R.id.action_settings -> {
                    settingsLauncher.launch(Intent(this, SettingsActivity::class.java))
                    true
                }
                else -> false
            }
        }
        ensureDiscoverSearchView()
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

    private fun openSongSearch() {
        intent.putExtra(EXTRA_FOCUS_LIBRARY_SEARCH, true)
        if (binding.bottomNav.selectedItemId != R.id.nav_library) {
            binding.bottomNav.selectedItemId = R.id.nav_library
        } else {
            (supportFragmentManager.findFragmentByTag(TAG_LIBRARY) as? LibraryFragment)?.requestSearchFocus()
        }
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

        val tag = when (tabId) {
            R.id.nav_library -> TAG_LIBRARY
            R.id.nav_playlists -> TAG_PLAYLISTS
            R.id.nav_profile -> TAG_PROFILE
            else -> TAG_DISCOVER
        }

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
        binding.bottomNav.visibility = if (visible) View.VISIBLE else View.GONE
        binding.root.post { updateMainContentPadding() }
    }

    private fun updateToolbar() {
        // Keep the top bar minimal and consistent (like the lyrics page).
        binding.toolbar.title = ""
        binding.toolbar.subtitle = null
        updateToolbarForVisiblePage(showBack = binding.toolbar.navigationIcon != null)
    }

    private fun ensureDiscoverSearchView() {
        if (discoverSearchView != null) return
        val searchView = LayoutInflater.from(this)
            .inflate(R.layout.view_discover_toolbar_search, binding.toolbar, false)
        val reservedActionWidth =
            resources.getDimensionPixelSize(R.dimen.control_height_l) +
                resources.getDimensionPixelSize(R.dimen.spacing_s)
        searchView.layoutParams = Toolbar.LayoutParams(
            Toolbar.LayoutParams.MATCH_PARENT,
            Toolbar.LayoutParams.WRAP_CONTENT,
            Gravity.START or Gravity.CENTER_VERTICAL
        ).apply {
            marginEnd = reservedActionWidth
        }
        searchView.findViewById<View>(R.id.cardDiscoverSearch).setOnClickListener {
            openSongSearch()
        }
        discoverSearchView = searchView
    }

    private fun updateToolbarForVisiblePage(showBack: Boolean) {
        val isDiscoverRoot = currentTabId == R.id.nav_discover && !showBack
        val searchMenuItem = binding.toolbar.menu.findItem(R.id.action_search_tab)
        searchMenuItem?.isVisible = !isDiscoverRoot

        val existingSearchView = discoverSearchView
        if (isDiscoverRoot) {
            if (existingSearchView != null && existingSearchView.parent == null) {
                binding.toolbar.addView(existingSearchView, 0)
            }
        } else if (existingSearchView?.parent === binding.toolbar) {
            binding.toolbar.removeView(existingSearchView)
        }
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
                binding.ivMiniCover.imageTintList = android.content.res.ColorStateList.valueOf(
                    getColor(R.color.brand_primary)
                )
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
        val topInset = binding.appBar.bottom.coerceAtLeast(0)
        val bottomInset = (binding.root.height - binding.bottomContentBarrier.top).coerceAtLeast(0)
        binding.fragmentContainer.updatePadding(
            top = topInset,
            bottom = bottomInset
        )
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
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(
                top = initialTop + if (applyTop) bars.top else 0,
                bottom = initialBottom + if (applyBottom) bars.bottom else 0
            )
            insets
        }
        ViewCompat.requestApplyInsets(this)
    }
}
