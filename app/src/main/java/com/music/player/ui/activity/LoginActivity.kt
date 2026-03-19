package com.music.player.ui.activity

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.ViewModelProvider
import com.music.player.MainActivity
import com.music.player.R
import com.music.player.databinding.ActivityLoginBinding
import com.music.player.ui.util.ImmersiveHeaderBackground
import com.music.player.ui.util.applyEdgeToEdge
import com.music.player.ui.util.applySystemBarInsetPadding
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.viewmodel.AuthState
import com.music.player.ui.viewmodel.AuthViewModel

class LoginActivity : AppCompatActivity() {

    private lateinit var binding: ActivityLoginBinding
    private lateinit var authViewModel: AuthViewModel
    private lateinit var immersiveHeaderBackground: ImmersiveHeaderBackground
    private lateinit var insetsController: WindowInsetsControllerCompat
    private var isLoginMode = true

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.applySavedNightMode(this)
        super.onCreate(savedInstanceState)
        binding = ActivityLoginBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val isNightMode =
            (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES
        insetsController = applyEdgeToEdge(binding.root, lightSystemBars = !isNightMode)
        binding.scrollView.applySystemBarInsetPadding(applyTop = true, applyBottom = true)

        authViewModel = ViewModelProvider(this)[AuthViewModel::class.java]
        immersiveHeaderBackground = ImmersiveHeaderBackground(
            this,
            binding.immersiveHeader.ivHeaderBackground
        ) { suggestion ->
            insetsController.isAppearanceLightStatusBars = suggestion.lightSystemBars
            insetsController.isAppearanceLightNavigationBars = suggestion.lightSystemBars
            binding.immersiveHeader.viewHeaderScrim.alpha = suggestion.topScrimAlpha
        }

        if (authViewModel.isLoggedIn()) {
            navigateToMain()
            return
        }

        setupUi()
        setupObservers()
    }

    private fun setupUi() {
        updateUiMode()

        binding.btnSubmit.setOnClickListener {
            submitAuth()
        }

        binding.etPassword.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                submitAuth()
                true
            } else {
                false
            }
        }

        binding.tvToggleMode.setOnClickListener {
            isLoginMode = !isLoginMode
            updateUiMode()
            authViewModel.resetAuthState()
        }
    }

    private fun setupObservers() {
        authViewModel.authState.observe(this) { state ->
            when (state) {
                is AuthState.Loading -> {
                    binding.progressBar.visibility = View.VISIBLE
                    binding.btnSubmit.isEnabled = false
                    binding.tvToggleMode.isEnabled = false
                }
                is AuthState.Success -> {
                    binding.progressBar.visibility = View.GONE
                    binding.btnSubmit.isEnabled = true
                    binding.tvToggleMode.isEnabled = true
                    Toast.makeText(this, state.message, Toast.LENGTH_SHORT).show()
                    navigateToMain()
                }
                is AuthState.Error -> {
                    binding.progressBar.visibility = View.GONE
                    binding.btnSubmit.isEnabled = true
                    binding.tvToggleMode.isEnabled = true
                    Toast.makeText(this, state.message, Toast.LENGTH_LONG).show()
                }
                is AuthState.Idle -> {
                    binding.progressBar.visibility = View.GONE
                    binding.btnSubmit.isEnabled = true
                    binding.tvToggleMode.isEnabled = true
                }
            }
        }
    }

    private fun submitAuth() {
        val email = binding.etEmail.text?.toString()?.trim().orEmpty()
        val password = binding.etPassword.text?.toString()?.trim().orEmpty()

        if (!validateInput(email, password)) {
            return
        }

        if (isLoginMode) {
            authViewModel.signIn(email, password)
        } else {
            authViewModel.signUp(email, password)
        }
    }

    private fun updateUiMode() {
        if (isLoginMode) {
            binding.tvTitle.text = getString(R.string.login_title)
            binding.tvSubtitle.text = getString(R.string.login_subtitle)
            binding.btnSubmit.text = getString(R.string.login_action)
            binding.tvToggleMode.text = getString(R.string.toggle_to_signup)
        } else {
            binding.tvTitle.text = getString(R.string.signup_title)
            binding.tvSubtitle.text = getString(R.string.signup_subtitle)
            binding.btnSubmit.text = getString(R.string.signup_action)
            binding.tvToggleMode.text = getString(R.string.toggle_to_login)
        }
    }

    private fun validateInput(email: String, password: String): Boolean {
        binding.emailInputLayout.error = null
        binding.passwordInputLayout.error = null

        if (email.isEmpty()) {
            binding.emailInputLayout.error = getString(R.string.email_required)
            return false
        }
        if (!android.util.Patterns.EMAIL_ADDRESS.matcher(email).matches()) {
            binding.emailInputLayout.error = getString(R.string.email_invalid)
            return false
        }
        if (password.isEmpty()) {
            binding.passwordInputLayout.error = getString(R.string.password_required)
            return false
        }
        if (password.length < 6) {
            binding.passwordInputLayout.error = getString(R.string.password_too_short)
            return false
        }
        return true
    }

    private fun navigateToMain() {
        startActivity(Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra(MainActivity.EXTRA_FROM_LOGIN, true)
        })
        finish()
    }
}
