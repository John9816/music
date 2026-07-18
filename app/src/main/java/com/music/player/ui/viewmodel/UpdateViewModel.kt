package com.music.player.ui.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.viewModelScope
import com.music.player.data.repository.AppVersionInfo
import com.music.player.data.repository.AppVersionRepository
import com.music.player.data.repository.VersionComparator
import kotlinx.coroutines.launch

sealed class UpdateState {
    data object Idle : UpdateState()
    data class Loading(val userInitiated: Boolean) : UpdateState()
    data class Latest(val latest: AppVersionInfo, val userInitiated: Boolean) : UpdateState()
    data class UpdateAvailable(
        val latest: AppVersionInfo,
        val force: Boolean,
        val userInitiated: Boolean
    ) : UpdateState()
    data class Error(val message: String, val userInitiated: Boolean) : UpdateState()
}

class UpdateViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = AppVersionRepository(application.applicationContext)

    private val _state = MutableLiveData<UpdateState>(UpdateState.Idle)
    val state: LiveData<UpdateState> = _state

    fun reset() {
        _state.value = UpdateState.Idle
    }

    fun check(currentVersion: String, currentBuildNumber: Int, userInitiated: Boolean = true) {
        viewModelScope.launch {
            _state.value = UpdateState.Loading(userInitiated)
            repository.getLatestVersion()
                .onSuccess { latest ->
                    if (latest == null) {
                        _state.value = UpdateState.Error(
                            message = "Unable to check for updates right now.",
                            userInitiated = userInitiated
                        )
                        return@onSuccess
                    }

                    val shouldUpdate = VersionComparator.isNewer(currentVersion, latest.version)
                    val isBelowMin = currentBuildNumber < latest.minBuildNumber
                    val force = latest.forceUpdate || isBelowMin
                    _state.value = if (shouldUpdate && latest.downloadUrl.isNullOrBlank()) {
                        UpdateState.Error("新版本没有适用于当前构建的安装包。", userInitiated)
                    } else if (shouldUpdate) {
                        UpdateState.UpdateAvailable(
                            latest = latest,
                            force = force,
                            userInitiated = userInitiated
                        )
                    } else {
                        UpdateState.Latest(latest, userInitiated)
                    }
                }
                .onFailure {
                    _state.value = UpdateState.Error(
                        message = it.message ?: "Failed to check for updates.",
                        userInitiated = userInitiated
                    )
                }
        }
    }
}
