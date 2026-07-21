package com.music.player.data.auth

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Process-wide authentication state used to route the UI after a confirmed session expiry. */
object AuthSessionState {
    private val _expired = MutableStateFlow(false)
    val expired = _expired.asStateFlow()

    fun notifyExpired() {
        _expired.value = true
    }

    fun markActive() {
        _expired.value = false
    }
}

sealed interface TokenRefreshResult {
    data class Success(val accessToken: String) : TokenRefreshResult
    data object MissingRefreshToken : TokenRefreshResult
    data object InvalidSession : TokenRefreshResult
    data object TransientFailure : TokenRefreshResult
}

internal enum class RefreshFailure {
    INVALID_SESSION,
    TRANSIENT
}

internal fun classifyRefreshFailure(httpCode: Int?): RefreshFailure =
    if (httpCode == 400 || httpCode == 401) {
        RefreshFailure.INVALID_SESSION
    } else {
        RefreshFailure.TRANSIENT
    }
