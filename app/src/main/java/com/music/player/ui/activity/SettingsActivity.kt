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
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.BuildConfig
import com.music.player.MainActivity
import com.music.player.R
import com.music.player.data.auth.UserProfile
import com.music.player.databinding.ActivitySettingsBinding
import com.music.player.ui.util.ImmersiveHeaderBackground
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.viewmodel.AuthState
import com.music.player.ui.viewmodel.AuthViewModel
import com.music.player.ui.viewmodel.UpdateState
import com.music.player.ui.viewmodel.UpdateViewModel
import com.music.player.update.AppUpdateInstaller
import com.music.player.update.AppUpdatePreferences
import com.music.player.update.showAppUpdateDialog

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

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.applySavedNightMode(this)
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val isNightMode =
            (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
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
        binding.tvAppVersion.text = "Local version: ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"
        authViewModel.refreshProfile()
    }

    private fun setupUi() {
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.toolbar.inflateMenu(R.menu.toolbar_search)
        binding.toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_search_tab -> {
                    openSongSearch()
                    true
                }
                else -> false
            }
        }

        binding.btnEditProfile.setOnClickListener { showEditProfileDialog() }
        binding.btnCheckUpdate.setOnClickListener {
            updateViewModel.check(BuildConfig.VERSION_CODE, userInitiated = true)
        }
        binding.btnTheme.setOnClickListener { showThemeDialog() }
        binding.btnLogout.setOnClickListener {
            authViewModel.signOut()
            navigateToLogin()
        }
    }

    private fun setupObservers() {
        authViewModel.currentUser.observe(this) { user ->
            currentUser = user
            binding.tvEmail.text = user?.email ?: getString(R.string.profile_email_placeholder)
        }

        updateViewModel.state.observe(this) { state ->
            when (state) {
                is UpdateState.Idle -> Unit
                is UpdateState.Loading -> {
                    if (state.userInitiated) {
                        Toast.makeText(
                            this,
                            getString(R.string.profile_check_update) + "...",
                            Toast.LENGTH_SHORT
                        ).show()
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

    private fun showThemeDialog() {
        val items = arrayOf(
            getString(R.string.theme_follow_system),
            getString(R.string.theme_light),
            getString(R.string.theme_dark)
        )

        val currentMode = ThemeManager.getNightMode(this)
        val checked = when (currentMode) {
            androidx.appcompat.app.AppCompatDelegate.MODE_NIGHT_NO -> 1
            androidx.appcompat.app.AppCompatDelegate.MODE_NIGHT_YES -> 2
            else -> 0
        }

        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.profile_theme)
            .setSingleChoiceItems(items, checked) { dialog, which ->
                val mode = when (which) {
                    1 -> androidx.appcompat.app.AppCompatDelegate.MODE_NIGHT_NO
                    2 -> androidx.appcompat.app.AppCompatDelegate.MODE_NIGHT_YES
                    else -> androidx.appcompat.app.AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
                }
                ThemeManager.setNightMode(this, mode)
                setResult(RESULT_OK, Intent().putExtra(EXTRA_SHOULD_RECREATE_MAIN, true))
                dialog.dismiss()
                finish()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun navigateToLogin() {
        startActivity(Intent(this, LoginActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        })
        finish()
    }

    private fun openSongSearch() {
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(MainActivity.EXTRA_INITIAL_TAB_ID, R.id.nav_library)
                putExtra(MainActivity.EXTRA_FOCUS_LIBRARY_SEARCH, true)
            }
        )
    }

    private fun showEditProfileDialog() {
        val user = currentUser ?: return
        val dialogView = layoutInflater.inflate(R.layout.dialog_edit_profile, null)

        val etUsername =
            dialogView.findViewById<com.google.android.material.textfield.TextInputEditText>(R.id.etUsername)
        val etNickname =
            dialogView.findViewById<com.google.android.material.textfield.TextInputEditText>(R.id.etNickname)
        val etSignature =
            dialogView.findViewById<com.google.android.material.textfield.TextInputEditText>(R.id.etSignature)
        val etAvatarUrl =
            dialogView.findViewById<com.google.android.material.textfield.TextInputEditText>(R.id.etAvatarUrl)

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

    override fun onDestroy() {
        super.onDestroy()
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
