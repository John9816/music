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

/**
 * Only treat hard auth rejection as session death.
 * 400 is common for "refresh route missing / bad body" on website backends — wiping the
 * session there caused users to re-login on every app start.
 */
internal fun classifyRefreshFailure(httpCode: Int?): RefreshFailure =
    when (httpCode) {
        401, 403 -> RefreshFailure.INVALID_SESSION
        else -> RefreshFailure.TRANSIENT
    }
