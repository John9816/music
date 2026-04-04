package com.music.player.ui.viewmodel

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.viewModelScope
import com.music.player.data.auth.AuthRepository
import com.music.player.data.auth.AuthResult
import com.music.player.data.auth.UserProfile
import com.music.player.playback.PlaybackCoordinator
import kotlinx.coroutines.launch

class AuthViewModel(application: Application) : AndroidViewModel(application) {
    private val authRepository = AuthRepository(application.applicationContext)

    private val _authState = MutableLiveData<AuthState>()
    val authState: LiveData<AuthState> = _authState

    private val _currentUser = MutableLiveData<UserProfile?>()
    val currentUser: LiveData<UserProfile?> = _currentUser

    init {
        checkCurrentUser()
    }

    private fun checkCurrentUser() {
        viewModelScope.launch {
            _currentUser.value = authRepository.getCurrentUser()
        }
    }

    fun signIn(email: String, password: String) {
        viewModelScope.launch {
            _authState.value = AuthState.Loading
            when (val result = authRepository.signIn(email, password)) {
                is AuthResult.Success -> {
                    _currentUser.value = result.user
                    _authState.value = AuthState.Success("登录成功")
                }
                is AuthResult.Error -> {
                    _authState.value = AuthState.Error(result.message)
                }
            }
        }
    }

    fun signUp(email: String, password: String) {
        viewModelScope.launch {
            _authState.value = AuthState.Loading
            when (val result = authRepository.signUp(email, password)) {
                is AuthResult.Success -> {
                    _currentUser.value = result.user
                    _authState.value = AuthState.Success("注册成功")
                }
                is AuthResult.Error -> {
                    _authState.value = AuthState.Error(result.message)
                }
            }
        }
    }

    fun signOut() {
        viewModelScope.launch {
            authRepository.signOut()
            PlaybackCoordinator.resetPlayback()
            _currentUser.value = null
            _authState.value = AuthState.Success("已退出登录")
        }
    }

    fun updateProfile(username: String?, nickname: String?, signature: String?, avatarUrl: String?) {
        viewModelScope.launch {
            _authState.value = AuthState.Loading
            when (val result = authRepository.updateUserProfile(username, nickname, signature, avatarUrl)) {
                is AuthResult.Success -> {
                    _currentUser.value = result.user
                    _authState.value = AuthState.Success("更新成功")
                }
                is AuthResult.Error -> {
                    _authState.value = AuthState.Error(result.message)
                }
            }
        }
    }

    fun uploadAvatar(imageUri: Uri) {
        viewModelScope.launch {
            _authState.value = AuthState.Loading
            when (val result = authRepository.uploadAvatarImage(imageUri)) {
                is AuthResult.Success -> {
                    _currentUser.value = result.user
                    _authState.value = AuthState.Success("头像已更新")
                }
                is AuthResult.Error -> {
                    _authState.value = AuthState.Error(result.message)
                }
            }
        }
    }

    fun refreshProfile() {
        viewModelScope.launch {
            _currentUser.value = authRepository.getCurrentUser()
        }
    }

    fun isLoggedIn(): Boolean {
        return authRepository.isUserLoggedIn()
    }

    fun resetAuthState() {
        _authState.value = AuthState.Idle
    }
}

sealed class AuthState {
    object Idle : AuthState()
    object Loading : AuthState()
    data class Success(val message: String) : AuthState()
    data class Error(val message: String) : AuthState()
}
