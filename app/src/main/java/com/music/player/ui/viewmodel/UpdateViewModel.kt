package com.music.player.ui.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.viewModelScope
import com.music.player.data.repository.AppVersionInfo
import com.music.player.data.repository.AppVersionRepository
import com.music.player.data.repository.VersionComparator
import com.music.player.R
import com.music.player.update.AutomaticUpdateGate
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job

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
    private var checkJob: Job? = null
    private val automaticUpdateGate = AutomaticUpdateGate()

    fun reset() {
        _state.value = UpdateState.Idle
    }

    fun check(currentVersion: String, currentBuildNumber: Int, userInitiated: Boolean = true) {
        val now = System.currentTimeMillis()
        if (!userInitiated) {
            if (!automaticUpdateGate.tryAcquire(now, checkJob?.isActive == true)) return
        } else {
            checkJob?.cancel()
        }

        checkJob = viewModelScope.launch {
            _state.value = UpdateState.Loading(userInitiated)
            repository.getLatestVersion()
                .onSuccess { latest ->
                    if (latest == null) {
                        _state.value = UpdateState.Error(
                            message = getApplication<Application>().getString(R.string.update_check_failed),
                            userInitiated = userInitiated
                        )
                        return@onSuccess
                    }

                    val shouldUpdate = VersionComparator.isNewer(currentVersion, latest.version)
                    val isBelowMin = currentBuildNumber < latest.minBuildNumber
                    val force = latest.forceUpdate || isBelowMin
                    _state.value = if (shouldUpdate && latest.downloadUrl.isNullOrBlank()) {
                        UpdateState.Error(
                            getApplication<Application>().getString(R.string.update_no_compatible_apk),
                            userInitiated
                        )
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
                        message = getApplication<Application>().getString(R.string.update_check_failed),
                        userInitiated = userInitiated
                    )
                }
        }
    }

}
