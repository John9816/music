package com.music.player.ui.activity

import android.content.Intent
import android.content.res.ColorStateList
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.ViewModelProvider
import com.bumptech.glide.Glide
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.data.auth.UserProfile
import com.music.player.databinding.ActivityProfileBinding
import com.music.player.ui.util.ImmersiveHeaderBackground
import com.music.player.ui.util.applyEdgeToEdge
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.viewmodel.AuthState
import com.music.player.ui.viewmodel.AuthViewModel
import com.music.player.ui.viewmodel.MusicViewModel

class ProfileActivity : AppCompatActivity() {

    private lateinit var binding: ActivityProfileBinding
    private lateinit var authViewModel: AuthViewModel
    private lateinit var musicViewModel: MusicViewModel
    private lateinit var immersiveHeaderBackground: ImmersiveHeaderBackground
    private var currentUser: UserProfile? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.applySavedNightMode(this)
        super.onCreate(savedInstanceState)
        binding = ActivityProfileBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val isNightMode =
            (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES
        applyEdgeToEdge(binding.root, lightSystemBars = !isNightMode)
        binding.toolbar.applyStatusBarInsetPadding()

        authViewModel = ViewModelProvider(this)[AuthViewModel::class.java]
        musicViewModel = ViewModelProvider(this)[MusicViewModel::class.java]
        immersiveHeaderBackground = ImmersiveHeaderBackground(this, binding.immersiveHeader.ivHeaderBackground)

        setupUI()
        setupObservers()
        authViewModel.refreshProfile()
    }

    private fun setupUI() {
        binding.toolbar.setNavigationOnClickListener {
            finish()
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
        musicViewModel.currentSong.observe(this) { song ->
            immersiveHeaderBackground.setImageUrl(song?.album?.picUrl)
        }

        authViewModel.currentUser.observe(this) { user ->
            currentUser = user
            user?.let {
                binding.tvEmail.text = it.email ?: getString(R.string.profile_email_placeholder)
                binding.tvUsername.text = getString(R.string.profile_username, it.username ?: "未设置")
                binding.tvNickname.text = getString(R.string.profile_nickname, it.nickname ?: "未设置")
                binding.tvSignature.text = it.signature ?: getString(R.string.profile_signature_empty)
                binding.tvUserId.text = getString(R.string.profile_user_id, "${it.id.take(8)}...")

                val avatarUrl = it.avatar_url?.trim().orEmpty()
                if (avatarUrl.isBlank()) {
                    val paddingPx = (22f * resources.displayMetrics.density).toInt()
                    binding.ivAvatar.setPadding(paddingPx, paddingPx, paddingPx, paddingPx)
                    binding.ivAvatar.imageTintList = ColorStateList.valueOf(getColor(R.color.brand_primary))
                    binding.ivAvatar.setImageResource(R.drawable.ic_person_24)
                } else {
                    binding.ivAvatar.setPadding(0, 0, 0, 0)
                    binding.ivAvatar.imageTintList = null
                    Glide.with(binding.ivAvatar)
                        .load(avatarUrl)
                        .placeholder(R.drawable.ic_person_24)
                        .error(R.drawable.ic_person_24)
                        .circleCrop()
                        .into(binding.ivAvatar)
                }

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
