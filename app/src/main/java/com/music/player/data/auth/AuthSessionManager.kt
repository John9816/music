package com.music.player.data.auth

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

class AuthSessionManager(context: Context) {
    private val appContext = context.applicationContext
    private val prefs: SharedPreferences = createPrefs(appContext)
    private val refreshMutex = Mutex()

    private fun createPrefs(context: Context): SharedPreferences {
        // Tokens are sensitive; store them encrypted at rest. If the Android Keystore is
        // unavailable (rare device/OEM issues), fall back to plain prefs so auth still works.
        return try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            val encrypted = EncryptedSharedPreferences.create(
                context,
                ENCRYPTED_PREFS_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            migrateLegacyPrefs(context, encrypted)
            encrypted
        } catch (t: Throwable) {
            Log.w(TAG, "EncryptedSharedPreferences unavailable, falling back to plain prefs", t)
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }
    }

    /** Moves any tokens saved by older versions in plain prefs into the encrypted store, then wipes them. */
    private fun migrateLegacyPrefs(context: Context, encrypted: SharedPreferences) {
        val legacy = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (legacy.all.isEmpty()) return
        if (encrypted.getString(KEY_ACCESS_TOKEN, null) == null) {
            encrypted.edit()
                .putString(KEY_ACCESS_TOKEN, legacy.getString(KEY_ACCESS_TOKEN, null))
                .putString(KEY_REFRESH_TOKEN, legacy.getString(KEY_REFRESH_TOKEN, null))
                .putLong(KEY_EXPIRES_AT_MS, legacy.getLong(KEY_EXPIRES_AT_MS, 0L))
                .putString(KEY_USER_ID, legacy.getString(KEY_USER_ID, null))
                .apply()
        }
        legacy.edit().clear().apply()
    }

    fun isLoggedIn(): Boolean {
        return !getRefreshToken().isNullOrBlank() || !getAccessToken().isNullOrBlank()
    }

    fun getCachedUserId(): String? = prefs.getString(KEY_USER_ID, null)

    fun cacheUserId(userId: String) {
        prefs.edit().putString(KEY_USER_ID, userId).apply()
    }

    fun syncUserIdFromAccessToken(accessToken: String): String? {
        val tokenUserId = extractUserIdFromJwt(accessToken)?.trim().orEmpty()
        if (tokenUserId.isBlank()) return null

        if (getCachedUserId() != tokenUserId) {
            cacheUserId(tokenUserId)
        }
        return tokenUserId
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

        // 无刷新令牌时无法续期：仍返回现有令牌，交由服务端以 401 判定是否失效。
        // 本地 expiresAtMs 可能因时钟或后端策略不准，提前判定过期会造成误登出。
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
        return refreshMutex.withLock {
            val currentRefreshToken = getRefreshToken() ?: return@withLock null
            refreshAccessToken(authApi, currentRefreshToken)
        }
    }

    private suspend fun refreshAccessToken(authApi: SupabaseAuthApi, refreshToken: String): String? {
        return try {
            val response = authApi.refreshToken(RefreshTokenRequest(refreshToken))
            if (!response.isSuccessful || response.body() == null) return null
            val body = AuthResponseParser.parse(response.body()?.string().orEmpty())?.data ?: return null
            val newAccess = body.token ?: body.access_token ?: return null

            saveSession(
                accessToken = newAccess,
                refreshToken = body.refresh_token ?: refreshToken,
                expiresInSeconds = body.expires_in ?: body.expiresInMinutes?.let { (it * 60L).toInt() },
                userId = syncUserIdFromAccessToken(newAccess) ?: getCachedUserId()
            )

            newAccess
        } catch (_: Exception) {
            null
        }
    }

    private fun extractUserIdFromJwt(accessToken: String): String? {
        return runCatching {
            val parts = accessToken.split('.')
            if (parts.size < 2) return null

            val payload = parts[1]
            val normalizedPayload = buildString(payload.length + 4) {
                append(payload)
                repeat((4 - payload.length % 4) % 4) { append('=') }
            }

            val decoded = Base64.decode(
                normalizedPayload,
                Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
            )
            JSONObject(String(decoded, Charsets.UTF_8)).optString("sub").takeIf { it.isNotBlank() }
        }.getOrNull()
    }

    private fun getAccessToken(): String? = prefs.getString(KEY_ACCESS_TOKEN, null)
    private fun getRefreshToken(): String? = prefs.getString(KEY_REFRESH_TOKEN, null)
    private fun getExpiresAtMs(): Long = prefs.getLong(KEY_EXPIRES_AT_MS, 0L)

    private fun isNearExpiry(expiresAtMs: Long): Boolean {
        if (expiresAtMs <= 0L) return true
        return System.currentTimeMillis() >= (expiresAtMs - EXPIRY_SAFETY_WINDOW_MS)
    }

    private companion object {
        private const val TAG = "AuthSessionManager"
        private const val PREFS_NAME = "auth_prefs"
        private const val ENCRYPTED_PREFS_NAME = "auth_prefs_secure"
        private const val KEY_ACCESS_TOKEN = "access_token"
        private const val KEY_REFRESH_TOKEN = "refresh_token"
        private const val KEY_EXPIRES_AT_MS = "expires_at_ms"
        private const val KEY_USER_ID = "user_id"

        private const val EXPIRY_SAFETY_WINDOW_MS = 60_000L
    }
}
