package com.music.player.ui.activity

import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
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
import com.bumptech.glide.Glide
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.MainActivity
import com.music.player.R
import com.music.player.data.auth.UserProfile
import com.music.player.databinding.ActivityProfileBinding
import com.music.player.ui.util.ImmersiveHeaderBackground
import com.music.player.ui.util.resolveAvatarUrl
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.viewmodel.AuthState
import com.music.player.ui.viewmodel.AuthViewModel

class ProfileActivity : AppCompatActivity() {

    private lateinit var binding: ActivityProfileBinding
    private lateinit var authViewModel: AuthViewModel
    private lateinit var immersiveHeaderBackground: ImmersiveHeaderBackground
    private lateinit var insetsController: WindowInsetsControllerCompat
    private var currentUser: UserProfile? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.applySavedNightMode(this)
        super.onCreate(savedInstanceState)
        binding = ActivityProfileBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val isNightMode =
            (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        insetsController = WindowInsetsControllerCompat(window, binding.root).apply {
            isAppearanceLightStatusBars = !isNightMode
            isAppearanceLightNavigationBars = !isNightMode
        }
        ViewCompat.setOnApplyWindowInsetsListener(binding.toolbar) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(top = bars.top)
            insets
        }
        ViewCompat.setOnApplyWindowInsetsListener(binding.scrollView) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(bottom = bars.bottom)
            insets
        }
        binding.toolbar.requestApplyInsets()
        binding.scrollView.requestApplyInsets()

        authViewModel = ViewModelProvider(this)[AuthViewModel::class.java]
        immersiveHeaderBackground = ImmersiveHeaderBackground(
            this,
            binding.immersiveHeader.ivHeaderBackground
        ) { suggestion ->
            insetsController.isAppearanceLightStatusBars = suggestion.lightSystemBars
            insetsController.isAppearanceLightNavigationBars = suggestion.lightSystemBars
            binding.immersiveHeader.viewHeaderScrim.alpha = suggestion.topScrimAlpha
        }

        setupUI()
        setupObservers()
        authViewModel.refreshProfile()
    }

    private fun setupUI() {
        binding.toolbar.setNavigationOnClickListener {
            finish()
        }
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

        binding.btnEditProfile.setOnClickListener {
            showEditProfileDialog()
        }

        binding.btnLogout.setOnClickListener {
            authViewModel.signOut()
            navigateToLogin()
        }
    }

    private fun setupObservers() {
        authViewModel.currentUser.observe(this) { user ->
            currentUser = user
            user?.let {
                binding.tvEmail.text = it.email ?: getString(R.string.profile_email_placeholder)
                binding.tvUsername.text = getString(R.string.profile_username, it.username ?: "未设置")
                binding.tvNickname.text = getString(R.string.profile_nickname, it.nickname ?: "未设置")
                binding.tvSignature.text = it.signature ?: getString(R.string.profile_signature_empty)
                binding.tvUserId.text = getString(R.string.profile_user_id, "${it.id.take(8)}...")

                binding.ivAvatar.setPadding(0, 0, 0, 0)
                binding.ivAvatar.imageTintList = null
                Glide.with(binding.ivAvatar)
                    .load(it.resolveAvatarUrl())
                    .placeholder(R.drawable.ic_person_24)
                    .error(R.drawable.ic_person_24)
                    .circleCrop()
                    .into(binding.ivAvatar)

                if (!it.badge.isNullOrEmpty()) {
                    binding.tvBadge.text = getString(R.string.profile_badge, it.badge)
                    binding.tvBadge.visibility = View.VISIBLE
                } else {
                    binding.tvBadge.visibility = View.GONE
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
                    authViewModel.refreshProfile()
                }
                is AuthState.Error -> {
                    binding.btnEditProfile.isEnabled = true
                    binding.btnLogout.isEnabled = true
                    Toast.makeText(this, state.message, Toast.LENGTH_LONG).show()
                }
                is AuthState.Idle -> {
                    binding.btnEditProfile.isEnabled = true
                    binding.btnLogout.isEnabled = true
                }
            }
        }
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
}
