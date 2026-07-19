package com.music.player.ui.activity

import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.updatePadding
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import com.bumptech.glide.Glide
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.BuildConfig
import com.music.player.R
import com.music.player.data.auth.UserProfile
import com.music.player.data.settings.AudioQualityPreferences
import com.music.player.data.settings.AppSettings
import com.music.player.data.settings.MusicSourcePreferences
import com.music.player.data.api.RetrofitClient
import com.music.player.data.repository.MusicRepository
import com.music.player.data.repository.AlbumRepository
import com.music.player.databinding.ActivitySettingsBinding
import com.music.player.playback.PlaybackCoordinator
import com.music.player.ui.util.ImmersiveHeaderBackground
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.viewmodel.AuthState
import com.music.player.ui.viewmodel.AuthViewModel
import com.music.player.ui.viewmodel.UpdateState
import com.music.player.ui.viewmodel.UpdateViewModel
import com.music.player.update.AppUpdateDialogs
import com.music.player.update.AppUpdateInstaller
import com.music.player.update.AppUpdatePreferences
import com.music.player.ui.util.SongDownloader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

class SettingsActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_SHOULD_RECREATE_MAIN = "extra_should_recreate_main"
    }

    private lateinit var binding: ActivitySettingsBinding
    private lateinit var authViewModel: AuthViewModel
    private lateinit var updateViewModel: UpdateViewModel
    private lateinit var appUpdateInstaller: AppUpdateInstaller
    private lateinit var appUpdatePreferences: AppUpdatePreferences
    private lateinit var immersiveHeaderBackground: ImmersiveHeaderBackground
    private lateinit var insetsController: WindowInsetsControllerCompat
    private var currentUser: UserProfile? = null
    private var shouldRecreateMain: Boolean = false
    private val musicRepository = MusicRepository()

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.prepareActivity(this)
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        shouldRecreateMain = savedInstanceState?.getBoolean(EXTRA_SHOULD_RECREATE_MAIN)
            ?: intent.getBooleanExtra(EXTRA_SHOULD_RECREATE_MAIN, false)
        if (shouldRecreateMain) {
            markMainNeedsRecreate()
        }

        val isNightMode = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        insetsController = applyEdgeToEdge(binding.root, lightSystemBars = !isNightMode)
        binding.toolbar.applyStatusBarInsetPadding()
        binding.scrollView.applyNavigationBarInsetPadding()

        authViewModel = ViewModelProvider(this)[AuthViewModel::class.java]
        updateViewModel = ViewModelProvider(this)[UpdateViewModel::class.java]
        appUpdateInstaller = AppUpdateInstaller(this)
        appUpdatePreferences = AppUpdatePreferences(this)
        immersiveHeaderBackground = ImmersiveHeaderBackground(
            this,
            binding.immersiveHeader.ivHeaderBackground
        ) { suggestion ->
            insetsController.isAppearanceLightStatusBars = suggestion.lightSystemBars
            insetsController.isAppearanceLightNavigationBars = suggestion.lightSystemBars
            binding.immersiveHeader.viewHeaderScrim.alpha = suggestion.topScrimAlpha
        }

        setupUi()
        setupObservers()
        updateAudioQualitySummary()
        updateSleepTimerSummary(AppSettings.remainingSleepMinutes(this))
        updateStreamQualitySummary(AppSettings.mobileStreamQuality(this))
        updateMusicSourceSummary()
        binding.tvSourceStatusSummary.setText(R.string.settings_source_not_checked)
        updateCacheSize()
        updateDownloadedSize()
        authViewModel.refreshProfile()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && ::insetsController.isInitialized) {
            insetsController.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    override fun onResume() {
        super.onResume()
        if (::binding.isInitialized) {
            updateDownloadedSize()
        }
    }

    private fun setupUi() {
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.tvEmail.text = getString(R.string.app_name)
        binding.tvAppVersion.text = BuildConfig.VERSION_NAME

        binding.btnLogout.setOnClickListener { showLogoutConfirmation() }

        // Playback
        binding.layoutAudioQuality.setOnClickListener { showAudioQualityDialog() }
        binding.layoutSleepTimer.setOnClickListener { showSleepTimerDialog() }

        // Network
        binding.layoutStreamQuality.setOnClickListener { showStreamQualityDialog() }
        binding.layoutMusicSource.setOnClickListener { showMusicSourceDialog() }
        binding.layoutSourceStatus.setOnClickListener { checkMusicSource() }
        binding.switchDownloadWifiOnly.isChecked = AppSettings.isDownloadWifiOnly(this)
        binding.switchDownloadWifiOnly.setOnCheckedChangeListener { _, isChecked ->
            AppSettings.setDownloadWifiOnly(this, isChecked)
        }

        // Cache
        binding.layoutManageDownloads.setOnClickListener {
            startActivity(Intent(this, DownloadsActivity::class.java))
        }
        binding.layoutClearCache.setOnClickListener { clearCache() }

        // Theme & Update
        binding.layoutCheckUpdate.setOnClickListener {
            updateViewModel.check(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, userInitiated = true)
        }

        // About
        binding.layoutHelpFeedback.setOnClickListener {
            startActivity(Intent(this, HelpFeedbackActivity::class.java))
        }
        binding.layoutUserAgreement.setOnClickListener {
            // Open user agreement URL
            openUrl("https://duckmusic.app/agreement")
        }
        binding.layoutPrivacyPolicy.setOnClickListener {
            // Open privacy policy URL
            openUrl("https://duckmusic.app/privacy")
        }
        binding.layoutOpenSourceLicenses.setOnClickListener {
            showOpenSourceLicenses()
        }
    }

    private fun setupObservers() {
        authViewModel.currentUser.observe(this) { user ->
            currentUser = user
            binding.tvEmail.text = getString(R.string.app_name)
        }

        updateViewModel.state.observe(this) { state ->
            when (state) {
                is UpdateState.Idle -> Unit
                is UpdateState.Loading -> {
                    if (state.userInitiated) {
                        Toast.makeText(this, getString(R.string.profile_check_update) + "...", Toast.LENGTH_SHORT).show()
                    }
                }
                is UpdateState.Latest -> {
                    if (state.userInitiated) {
                        Toast.makeText(this, getString(R.string.update_latest), Toast.LENGTH_SHORT).show()
                    }
                    updateViewModel.reset()
                }
                is UpdateState.UpdateAvailable -> {
                    appUpdatePreferences.clearSkippedIfOlderThan(state.latest.buildNumber)
                    if (!state.userInitiated &&
                        appUpdatePreferences.shouldSuppressAutoPrompt(state.latest.buildNumber, force = state.force)
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
                is UpdateState.Error -> {
                    if (state.userInitiated) {
                        Toast.makeText(this, state.message, Toast.LENGTH_LONG).show()
                    }
                    updateViewModel.reset()
                }
            }
        }

        authViewModel.authState.observe(this) { state ->
            when (state) {
                is AuthState.Loading -> {
                    binding.btnEditProfile.isEnabled = false
                    binding.btnLogout.isEnabled = false
                }
                is AuthState.Success -> {
                    binding.btnEditProfile.isEnabled = true
                    binding.btnLogout.isEnabled = true
                    Toast.makeText(this, state.message, Toast.LENGTH_SHORT).show()
                    authViewModel.resetAuthState()
                    authViewModel.refreshProfile()
                }
                is AuthState.Error -> {
                    binding.btnEditProfile.isEnabled = true
                    binding.btnLogout.isEnabled = true
                    Toast.makeText(this, state.message, Toast.LENGTH_LONG).show()
                    authViewModel.resetAuthState()
                }
                is AuthState.Idle -> {
                    binding.btnEditProfile.isEnabled = true
                    binding.btnLogout.isEnabled = true
                }
            }
        }
    }

    private fun showLogoutConfirmation() {
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.profile_logout)
            .setMessage("确定要退出当前账号吗？")
            .setPositiveButton(R.string.profile_logout) { _, _ ->
                authViewModel.signOut()
                navigateToLogin()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showEditProfileDialog() {
        val user = currentUser ?: return
        val dialogView = layoutInflater.inflate(R.layout.dialog_edit_profile, null)

        val etUsername = dialogView.findViewById<com.google.android.material.textfield.TextInputEditText>(R.id.etUsername)
        val etNickname = dialogView.findViewById<com.google.android.material.textfield.TextInputEditText>(R.id.etNickname)
        val etSignature = dialogView.findViewById<com.google.android.material.textfield.TextInputEditText>(R.id.etSignature)
        val etAvatarUrl = dialogView.findViewById<com.google.android.material.textfield.TextInputEditText>(R.id.etAvatarUrl)

        etUsername.setText(user.username.orEmpty())
        etNickname.setText(user.nickname.orEmpty())
        etSignature.setText(user.signature.orEmpty())
        etAvatarUrl.setText(user.avatar_url.orEmpty())

        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.profile_edit_title)
            .setView(dialogView)
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.profile_edit_confirm) { _, _ ->
                authViewModel.updateProfile(
                    username = etUsername.text?.toString()?.trim(),
                    nickname = etNickname.text?.toString()?.trim(),
                    signature = etSignature.text?.toString()?.trim(),
                    avatarUrl = etAvatarUrl.text?.toString()?.trim()
                )
            }
            .show()
    }

    private fun showAudioQualityDialog() {
        val levels = AudioQualityPreferences.Level.entries.toTypedArray()
        val names: Array<String> = levels.map { it.displayName }.toTypedArray()
        val current = levels.indexOf(AudioQualityPreferences.getPreferredLevel(this)).coerceAtLeast(0)

        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.settings_audio_quality_dialog_title)
            .setSingleChoiceItems(names, current) { dialog, which ->
                AudioQualityPreferences.setPreferredLevel(this@SettingsActivity, levels[which])
                updateAudioQualitySummary()
                PlaybackCoordinator.reloadCurrentSongForAudioQualityChange()
                dialog.dismiss()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showSleepTimerDialog() {
        val options = arrayOf(
            getString(R.string.sleep_timer_off),
            getString(R.string.sleep_timer_15min),
            getString(R.string.sleep_timer_30min),
            getString(R.string.sleep_timer_45min),
            getString(R.string.sleep_timer_60min)
        )
        val durations = arrayOf(0L, 15L, 30L, 45L, 60L)

        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.sleep_timer_dialog_title)
            .setItems(options) { _, which ->
                val minutes = durations[which]
                if (minutes == 0L) {
                    PlaybackCoordinator.cancelSleepTimer()
                    Toast.makeText(this, R.string.sleep_timer_cancelled, Toast.LENGTH_SHORT).show()
                } else {
                    PlaybackCoordinator.setSleepTimer(minutes)
                    Toast.makeText(this, getString(R.string.sleep_timer_set, options[which]), Toast.LENGTH_SHORT).show()
                }
                updateSleepTimerSummary(minutes)
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showStreamQualityDialog() {
        val options = arrayOf(
            getString(R.string.settings_stream_quality_wifi_only),
            "标准音质",
            "高品质",
            "极高音质"
        )
        val values = AppSettings.MobileStreamQuality.entries.toTypedArray()
        val current = values.indexOf(AppSettings.mobileStreamQuality(this)).coerceAtLeast(0)

        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.settings_stream_quality)
            .setSingleChoiceItems(options, current) { dialog, which ->
                AppSettings.setMobileStreamQuality(this, values[which])
                updateStreamQualitySummary(values[which])
                PlaybackCoordinator.reloadCurrentSongForAudioQualityChange()
                dialog.dismiss()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showMusicSourceDialog() {
        val sources = MusicSourcePreferences.Source.entries
        val active = MusicSourcePreferences.activeSource(this)
        val checked = sources.indexOf(active).coerceAtLeast(0)
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.settings_switch_source)
            .setSingleChoiceItems(sources.map { it.displayName }.toTypedArray(), checked) { dialog, which ->
                val selected = sources[which]
                dialog.dismiss()
                if (selected == active) return@setSingleChoiceItems
                verifyAndSwitchMusicSource(selected)
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun verifyAndSwitchMusicSource(source: MusicSourcePreferences.Source) {
        binding.layoutMusicSource.isEnabled = false
        binding.tvSourceStatusSummary.setText(R.string.settings_source_checking)
        lifecycleScope.launch {
            val result = withTimeoutOrNull(12_000L) { musicRepository.checkSource(source) }
                ?: Result.failure(Exception("音源检测超时"))
            binding.layoutMusicSource.isEnabled = true
            if (result.isFailure) {
                binding.tvSourceStatusSummary.setText(R.string.settings_source_unavailable)
                Toast.makeText(
                    this@SettingsActivity,
                    getString(R.string.settings_source_switch_failed, source.displayName),
                    Toast.LENGTH_SHORT
                ).show()
                return@launch
            }
            MusicSourcePreferences.setActiveSource(this@SettingsActivity, source)
            onMusicSourceChanged()
            Toast.makeText(
                this@SettingsActivity,
                getString(R.string.settings_source_switched, source.displayName),
                Toast.LENGTH_SHORT
            ).show()
        }
    }

    private fun checkMusicSource() {
        val source = MusicSourcePreferences.activeSource(this)
        binding.layoutSourceStatus.isEnabled = false
        binding.tvSourceStatusSummary.setText(R.string.settings_source_checking)
        lifecycleScope.launch {
            val result = musicRepository.checkSource(source)
            binding.layoutSourceStatus.isEnabled = true
            binding.tvSourceStatusSummary.setText(
                if (result.isSuccess) R.string.settings_source_available
                else R.string.settings_source_unavailable
            )
            result.exceptionOrNull()?.message?.takeIf { it.isNotBlank() }?.let {
                Toast.makeText(this@SettingsActivity, it, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun onMusicSourceChanged() {
        MusicRepository.clearCaches()
        AlbumRepository.clearCaches()
        PlaybackCoordinator.clearResolvedUrlCache()
        updateMusicSourceSummary()
        binding.tvSourceStatusSummary.setText(R.string.settings_source_not_checked)
        markMainNeedsRecreate()
    }

    private fun updateMusicSourceSummary() {
        binding.tvMusicSourceSummary.text = MusicSourcePreferences.activeSource(this).displayName
    }

    private fun showSkinDialog() {
        val items = arrayOf(
            getString(R.string.settings_color_theme),
            getString(R.string.settings_player_style)
        )

        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.profile_theme)
            .setItems(items) { _, which ->
                when (which) {
                    0 -> showThemeDialog()
                    1 -> showPlayerStyleDialog()
                }
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showThemeDialog() {
        val skins = ThemeManager.AppThemeSkin.entries.toList()
        val items = skins.map { s -> "${getString(s.titleResId)}\n${getString(s.summaryResId)}" }.toTypedArray()
        val checked = skins.indexOf(ThemeManager.getAppThemeSkin(this)).coerceAtLeast(0)

        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.theme_dialog_title)
            .setSingleChoiceItems(items, checked) { dialog, which ->
                ThemeManager.setAppThemeSkin(this, skins[which])
                markMainNeedsRecreate()
                dialog.dismiss()
                recreate()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showPlayerStyleDialog() {
        val styles = ThemeManager.PlayerStyle.entries.toList()
        val items = styles.map { s -> "${getString(s.titleResId)}\n${getString(s.summaryResId)}" }.toTypedArray()
        val checked = styles.indexOf(ThemeManager.getPlayerStyle(this)).coerceAtLeast(0)

        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.player_style_dialog_title)
            .setSingleChoiceItems(items, checked) { dialog, which ->
                ThemeManager.setPlayerStyle(this, styles[which])
                markMainNeedsRecreate()
                Toast.makeText(this, getString(R.string.settings_restart_hint), Toast.LENGTH_SHORT).show()
                dialog.dismiss()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showOpenSourceLicenses() {
        val licenses = buildString {
            appendLine("${getString(R.string.app_name)} 使用以下开源项目：")
            appendLine()
            appendLine("Retrofit — Apache 2.0")
            appendLine("OkHttp — Apache 2.0")
            appendLine("Glide — Apache 2.0")
            appendLine("ExoPlayer (Media3) — Apache 2.0")
            appendLine("Kotlin Coroutines — Apache 2.0")
            appendLine("Material Components — Apache 2.0")
        }
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.settings_open_source_licenses)
            .setMessage(licenses)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    private fun openUrl(url: String) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))
            startActivity(intent)
        } catch (e: Exception) {
            Toast.makeText(this, "无法打开链接", Toast.LENGTH_SHORT).show()
        }
    }

    private fun updateAudioQualitySummary() {
        binding.tvAudioQualitySummary.text = AudioQualityPreferences.getPreferredLevel(this).displayName
    }

    private fun updateSleepTimerSummary(minutes: Long) {
        if (minutes <= 0L) {
            binding.tvSleepTimerSummary.setText(R.string.settings_sleep_timer_off_summary)
        } else {
            binding.tvSleepTimerSummary.text = getString(R.string.settings_sleep_timer_minutes, minutes)
        }
    }

    private fun updateStreamQualitySummary(quality: AppSettings.MobileStreamQuality) {
        binding.tvStreamQualitySummary.text = when (quality) {
            AppSettings.MobileStreamQuality.WIFI_ONLY -> getString(R.string.settings_stream_quality_summary)
            AppSettings.MobileStreamQuality.STANDARD -> "标准音质（省流量）"
            AppSettings.MobileStreamQuality.HIGH -> "高品质"
            AppSettings.MobileStreamQuality.EXTREME -> "极高音质（消耗流量）"
        }
    }

    private fun updateCacheSize() {
        val cacheDir = Glide.getPhotoCacheDir(this)
        val imageCacheSize = cacheDir?.let { calculateDirSize(it) } ?: 0L
        val size = imageCacheSize + RetrofitClient.httpCacheSizeBytes()
        binding.tvCacheSize.text = getString(R.string.settings_cache_size, formatSize(size))
    }

    private fun updateDownloadedSize() {
        lifecycleScope.launch {
            val totalSize = withContext(Dispatchers.IO) {
                SongDownloader.downloadDirs(this@SettingsActivity)
                    .flatMap { it.listFiles().orEmpty().asIterable() }
                    .filter { it.isFile && !it.name.endsWith(".part", ignoreCase = true) }
                    .distinctBy { it.absolutePath }
                    .sumOf { it.length().coerceAtLeast(0L) }
            }
            binding.tvDownloadedSize.text = formatSize(totalSize)
        }
    }

    private fun clearCache() {
        Thread {
            Glide.get(this).clearDiskCache()
            RetrofitClient.clearHttpCache()
            MusicRepository.clearCaches()
            AlbumRepository.clearCaches()
            PlaybackCoordinator.clearResolvedUrlCache()
            runOnUiThread {
                Glide.get(this).clearMemory()
                Toast.makeText(this, R.string.settings_cache_cleared, Toast.LENGTH_SHORT).show()
                updateCacheSize()
            }
        }.start()
    }

    private fun calculateDirSize(dir: java.io.File): Long {
        var size = 0L
        dir.listFiles()?.forEach { file ->
            size += if (file.isDirectory) calculateDirSize(file) else file.length()
        }
        return size
    }

    private fun formatSize(bytes: Long): String {
        return when {
            bytes >= 1024 * 1024 * 1024 -> String.format("%.1f GB", bytes / (1024.0 * 1024 * 1024))
            bytes >= 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024))
            bytes >= 1024 -> String.format("%.1f KB", bytes / 1024.0)
            else -> "$bytes B"
        }
    }

    private fun markMainNeedsRecreate() {
        shouldRecreateMain = true
        intent.putExtra(EXTRA_SHOULD_RECREATE_MAIN, true)
        setResult(RESULT_OK, android.content.Intent().putExtra(EXTRA_SHOULD_RECREATE_MAIN, true))
    }

    private fun navigateToLogin() {
        startActivity(Intent(this, LoginActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        })
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::appUpdateInstaller.isInitialized) {
            appUpdateInstaller.dispose()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(EXTRA_SHOULD_RECREATE_MAIN, shouldRecreateMain)
        super.onSaveInstanceState(outState)
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
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    private fun View.applyStatusBarInsetPadding() {
        val initialTop = (layoutParams as? androidx.constraintlayout.widget.ConstraintLayout.LayoutParams)?.topMargin ?: 0
        ViewCompat.setOnApplyWindowInsetsListener(this) { view, insets ->
            val bars = insets.getInsetsIgnoringVisibility(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(top = initialTop + bars.top)
            insets
        }
        requestApplyInsets()
    }

    private fun View.applyNavigationBarInsetPadding() {
        ViewCompat.setOnApplyWindowInsetsListener(this) { view, insets ->
            val bars = insets.getInsetsIgnoringVisibility(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(bottom = bars.bottom)
            insets
        }
        requestApplyInsets()
    }
}
