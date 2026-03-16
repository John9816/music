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
import android.view.animation.LinearInterpolator
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
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
import com.music.player.ui.viewmodel.AuthViewModel
import com.music.player.ui.viewmodel.LibraryViewModel
import com.music.player.ui.viewmodel.MusicViewModel
import com.music.player.ui.util.ImmersiveHeaderBackground
import com.music.player.ui.util.ThemeManager
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.collect

class MainActivity : AppCompatActivity() {

    companion object {
        private const val TAG_DISCOVER = "tab_discover"
        private const val TAG_LIBRARY = "tab_library"
        private const val TAG_PLAYLISTS = "tab_playlists"
        private const val TAG_PROFILE = "tab_profile"

        const val EXTRA_FROM_LOGIN = "extra_from_login"
    }

    val player: Player?
        get() = PlaybackCoordinator.playerOrNull()

    private lateinit var binding: ActivityMainBinding
    private lateinit var musicViewModel: MusicViewModel
    private lateinit var authViewModel: AuthViewModel
    private lateinit var libraryViewModel: LibraryViewModel
    private lateinit var immersiveHeaderBackground: ImmersiveHeaderBackground

    private var suppressNavCallback = false
    private var currentTabId: Int = R.id.nav_discover
    private var miniProgressJob: Job? = null
    private var miniCoverAnimator: ObjectAnimator? = null

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

        immersiveHeaderBackground = ImmersiveHeaderBackground(this, binding.immersiveHeader.ivHeaderBackground)

        setupEdgeToEdge()

        musicViewModel = ViewModelProvider(this)[MusicViewModel::class.java]
        authViewModel = ViewModelProvider(this)[AuthViewModel::class.java]
        libraryViewModel = ViewModelProvider(this)[LibraryViewModel::class.java]

        if (!authViewModel.isLoggedIn()) {
            navigateToLogin()
            return
        }

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
        setupBottomNavigation(savedInstanceState)

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

    private fun setupEdgeToEdge() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= 29) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }

        val controller = WindowInsetsControllerCompat(window, binding.root)
        val lightSystemBars = !isNightMode()
        controller.isAppearanceLightStatusBars = lightSystemBars
        controller.isAppearanceLightNavigationBars = lightSystemBars

        ViewCompat.setOnApplyWindowInsetsListener(binding.appBar) { view, insets ->
            val statusInsets = insets.getInsets(WindowInsetsCompat.Type.statusBars())
            view.updatePadding(top = statusInsets.top)
            insets
        }

        ViewCompat.setOnApplyWindowInsetsListener(binding.bottomNav) { view, insets ->
            val navInsets = insets.getInsets(WindowInsetsCompat.Type.navigationBars())
            view.updatePadding(bottom = navInsets.bottom)
            insets
        }
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

        val initialTab = if (savedInstanceState == null) R.id.nav_discover else binding.bottomNav.selectedItemId
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
                    if (binding.bottomNav.selectedItemId != R.id.nav_library) {
                        binding.bottomNav.selectedItemId = R.id.nav_library
                    }
                    true
                }
                R.id.action_settings -> {
                    settingsLauncher.launch(Intent(this, SettingsActivity::class.java))
                    true
                }
                else -> false
            }
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
    }

    fun setBottomNavVisible(visible: Boolean) {
        binding.bottomNav.visibility = if (visible) View.VISIBLE else View.GONE
    }

    private fun updateToolbar() {
        // Keep the top bar minimal and consistent (like the lyrics page).
        binding.toolbar.title = ""
        binding.toolbar.subtitle = null
    }

    private fun setupObservers() {
        musicViewModel.currentSong.observe(this) { song ->
            immersiveHeaderBackground.setImageUrl(song?.album?.picUrl)
            if (song == null) {
                binding.miniPlayer.visibility = View.GONE
                binding.miniProgress.isIndeterminate = false
                binding.miniProgress.progress = 0
                updateMiniCoverRotation(false)
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
    }

    private fun setupMiniPlayer() {
        binding.miniProgress.max = 1000

        binding.btnMiniPlayPause.setOnClickListener {
            val p = player ?: return@setOnClickListener
            if (p.isPlaying) {
                p.pause()
            } else {
                if (p.playbackState == Player.STATE_IDLE && p.mediaItemCount > 0) {
                    p.prepare()
                }
                p.play()
            }
            updateMiniPlayPauseIcon(shouldShowAsPlaying(p))
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
    }
}
