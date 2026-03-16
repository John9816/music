package com.music.player.ui.activity

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.ViewModelProvider
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.BuildConfig
import com.music.player.R
import com.music.player.data.auth.UserProfile
import com.music.player.databinding.ActivitySettingsBinding
import com.music.player.ui.util.ImmersiveHeaderBackground
import com.music.player.ui.util.applyEdgeToEdge
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.viewmodel.AuthState
import com.music.player.ui.viewmodel.AuthViewModel
import com.music.player.ui.viewmodel.MusicViewModel
import com.music.player.ui.viewmodel.UpdateState
import com.music.player.ui.viewmodel.UpdateViewModel

class SettingsActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_SHOULD_RECREATE_MAIN = "extra_should_recreate_main"
    }

    private lateinit var binding: ActivitySettingsBinding
    private lateinit var authViewModel: AuthViewModel
    private lateinit var updateViewModel: UpdateViewModel
    private lateinit var musicViewModel: MusicViewModel
    private lateinit var immersiveHeaderBackground: ImmersiveHeaderBackground
    private var currentUser: UserProfile? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.applySavedNightMode(this)
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val isNightMode =
            (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES
        applyEdgeToEdge(binding.root, lightSystemBars = !isNightMode)
        binding.toolbar.applyStatusBarInsetPadding()

        authViewModel = ViewModelProvider(this)[AuthViewModel::class.java]
        updateViewModel = ViewModelProvider(this)[UpdateViewModel::class.java]
        musicViewModel = ViewModelProvider(this)[MusicViewModel::class.java]
        immersiveHeaderBackground = ImmersiveHeaderBackground(this, binding.immersiveHeader.ivHeaderBackground)

        setupUi()
        setupObservers()
        binding.tvAppVersion.text = "Local version: ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"
        authViewModel.refreshProfile()
    }

    private fun setupUi() {
        binding.toolbar.setNavigationOnClickListener { finish() }

        binding.btnEditProfile.setOnClickListener { showEditProfileDialog() }
        binding.btnCheckUpdate.setOnClickListener { updateViewModel.check(BuildConfig.VERSION_CODE) }
        binding.btnTheme.setOnClickListener { showThemeDialog() }
        binding.btnLogout.setOnClickListener {
            authViewModel.signOut()
            navigateToLogin()
        }
    }

    private fun setupObservers() {
        musicViewModel.currentSong.observe(this) { song ->
            immersiveHeaderBackground.setImageUrl(song?.album?.picUrl)
        }

        authViewModel.currentUser.observe(this) { user ->
            currentUser = user
            binding.tvEmail.text = user?.email ?: getString(R.string.profile_email_placeholder)
        }

        updateViewModel.state.observe(this) { state ->
            when (state) {
                is UpdateState.Idle -> Unit
                is UpdateState.Loading -> {
                    Toast.makeText(this, getString(R.string.profile_check_update) + "...", Toast.LENGTH_SHORT).show()
                }
                is UpdateState.Latest -> {
                    Toast.makeText(this, getString(R.string.update_latest), Toast.LENGTH_SHORT).show()
                    updateViewModel.reset()
                }
                is UpdateState.UpdateAvailable -> {
                    showUpdateDialog(
                        BuildConfig.VERSION_NAME,
                        BuildConfig.VERSION_CODE,
                        state.latest.version,
                        state.latest.buildNumber,
                        state.latest.description,
                        state.latest.downloadUrl,
                        state.force
                    )
                    updateViewModel.reset()
                }
                is UpdateState.Error -> {
                    Toast.makeText(this, state.message, Toast.LENGTH_LONG).show()
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

    private fun showUpdateDialog(
        currentVersion: String,
        currentBuildNumber: Int,
        version: String,
        buildNumber: Int,
        description: String?,
        downloadUrl: String?,
        force: Boolean
    ) {
        val message = buildString {
            append("Local: ").append(currentVersion).append(" (").append(currentBuildNumber).append(")")
            append("\nRemote: ").append(version).append(" (").append(buildNumber).append(")")
            if (!description.isNullOrBlank()) {
                append("\n\n").append(description.trim())
            }
        }

        val dialog = MaterialAlertDialogBuilder(this)
            .setTitle(R.string.update_title)
            .setMessage(message)
            .setPositiveButton(R.string.update_download) { _, _ ->
                val url = downloadUrl?.trim().orEmpty()
                if (url.isBlank()) {
                    Toast.makeText(this, getString(R.string.update_no_url), Toast.LENGTH_SHORT).show()
                    return@setPositiveButton
                }
                runCatching {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                }.onFailure {
                    Toast.makeText(this, it.message ?: getString(R.string.update_no_url), Toast.LENGTH_SHORT).show()
                }
            }

        if (force) {
            dialog.setCancelable(false)
            dialog.setNegativeButton(R.string.update_exit) { _, _ -> finishAffinity() }
        } else {
            dialog.setNegativeButton(R.string.update_later, null)
        }

        dialog.show()
    }

    private fun navigateToLogin() {
        startActivity(Intent(this, LoginActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        })
        finish()
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
}
