package com.music.player.ui.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.viewModelScope
import com.music.player.data.repository.AppVersionInfo
import com.music.player.data.repository.AppVersionRepository
import kotlinx.coroutines.launch

sealed class UpdateState {
    data object Idle : UpdateState()
    data object Loading : UpdateState()
    data class Latest(val latest: AppVersionInfo) : UpdateState()
    data class UpdateAvailable(val latest: AppVersionInfo, val force: Boolean) : UpdateState()
    data class Error(val message: String) : UpdateState()
}

class UpdateViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = AppVersionRepository(application.applicationContext)

    private val _state = MutableLiveData<UpdateState>(UpdateState.Idle)
    val state: LiveData<UpdateState> = _state

    fun reset() {
        _state.value = UpdateState.Idle
    }

    fun check(currentBuildNumber: Int) {
        viewModelScope.launch {
            _state.value = UpdateState.Loading
            repository.getLatestVersion()
                .onSuccess { latest ->
                    if (latest == null) {
                        _state.value = UpdateState.Error("未登录，无法检查更新")
                        return@onSuccess
                    }
                    val shouldUpdate = currentBuildNumber < latest.buildNumber
                    val isBelowMin = currentBuildNumber < latest.minBuildNumber
                    val force = latest.forceUpdate || isBelowMin
                    _state.value = if (shouldUpdate) {
                        UpdateState.UpdateAvailable(latest, force = force)
                    } else {
                        UpdateState.Latest(latest)
                    }
                }
                .onFailure { _state.value = UpdateState.Error(it.message ?: "检查更新失败") }
        }
    }
}

