package com.music.player.data.auth

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class AuthSessionManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val refreshMutex = Mutex()

    fun isLoggedIn(): Boolean {
        return !getRefreshToken().isNullOrBlank() || !getAccessToken().isNullOrBlank()
    }

    fun getCachedUserId(): String? = prefs.getString(KEY_USER_ID, null)

    fun cacheUserId(userId: String) {
        prefs.edit().putString(KEY_USER_ID, userId).apply()
    }

    fun clear() {
        prefs.edit()
            .remove(KEY_ACCESS_TOKEN)
            .remove(KEY_REFRESH_TOKEN)
            .remove(KEY_EXPIRES_AT_MS)
            .remove(KEY_USER_ID)
            .apply()
    }

    fun saveSession(accessToken: String, refreshToken: String?, expiresInSeconds: Int?, userId: String?) {
        val expiresAtMs = expiresInSeconds?.let { seconds ->
            System.currentTimeMillis() + (seconds.toLong() * 1000L)
        }

        prefs.edit()
            .putString(KEY_ACCESS_TOKEN, accessToken)
            .putString(KEY_REFRESH_TOKEN, refreshToken)
            .putLong(KEY_EXPIRES_AT_MS, expiresAtMs ?: 0L)
            .putString(KEY_USER_ID, userId)
            .apply()
    }

    suspend fun getValidAccessToken(authApi: SupabaseAuthApi): String? {
        val token = getAccessToken() ?: return null
        val refreshToken = getRefreshToken()
        val expiresAtMs = getExpiresAtMs()

        if (refreshToken.isNullOrBlank()) return token
        if (!isNearExpiry(expiresAtMs)) return token

        return refreshMutex.withLock {
            val existingToken = getAccessToken() ?: return@withLock null
            val existingRefresh = getRefreshToken()
            val existingExpiresAtMs = getExpiresAtMs()

            if (existingRefresh.isNullOrBlank()) return@withLock existingToken
            if (!isNearExpiry(existingExpiresAtMs)) return@withLock existingToken

            refreshAccessToken(authApi, existingRefresh) ?: existingToken
        }
    }

    suspend fun forceRefresh(authApi: SupabaseAuthApi): String? {
        val refreshToken = getRefreshToken() ?: return null
        return refreshMutex.withLock {
            refreshAccessToken(authApi, refreshToken)
        }
    }

    private suspend fun refreshAccessToken(authApi: SupabaseAuthApi, refreshToken: String): String? {
        return try {
            val response = authApi.refreshToken(RefreshTokenRequest(refreshToken))
            if (!response.isSuccessful || response.body() == null) return null
            val body = response.body()!!
            val newAccess = body.access_token ?: return null

            saveSession(
                accessToken = newAccess,
                refreshToken = body.refresh_token ?: refreshToken,
                expiresInSeconds = body.expires_in,
                userId = getCachedUserId()
            )

            newAccess
        } catch (_: Exception) {
            null
        }
    }

    private fun getAccessToken(): String? = prefs.getString(KEY_ACCESS_TOKEN, null)
    private fun getRefreshToken(): String? = prefs.getString(KEY_REFRESH_TOKEN, null)
    private fun getExpiresAtMs(): Long = prefs.getLong(KEY_EXPIRES_AT_MS, 0L)

    private fun isNearExpiry(expiresAtMs: Long): Boolean {
        if (expiresAtMs <= 0L) return true
        return System.currentTimeMillis() >= (expiresAtMs - EXPIRY_SAFETY_WINDOW_MS)
    }

    private companion object {
        private const val PREFS_NAME = "auth_prefs"
        private const val KEY_ACCESS_TOKEN = "access_token"
        private const val KEY_REFRESH_TOKEN = "refresh_token"
        private const val KEY_EXPIRES_AT_MS = "expires_at_ms"
        private const val KEY_USER_ID = "user_id"

        private const val EXPIRY_SAFETY_WINDOW_MS = 60_000L
    }
}

