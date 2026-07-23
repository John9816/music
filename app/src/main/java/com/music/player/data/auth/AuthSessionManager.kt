package com.music.player.data.auth

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.music.player.data.repository.SupabaseMusicRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okio.ByteString.Companion.decodeBase64

class AuthSessionManager(context: Context) {
    private val appContext = context.applicationContext
    /**
     * Plain mirror so a Keystore/EncryptedSharedPreferences glitch cannot wipe login state.
     * Must be initialized BEFORE primaryPrefs — createPrimaryPrefs reads the mirror.
     */
    private val mirrorPrefs: SharedPreferences =
        appContext.getSharedPreferences(MIRROR_PREFS_NAME, Context.MODE_PRIVATE)
    private val primaryPrefs: SharedPreferences = createPrimaryPrefs(appContext)
    private val refreshMutex = Mutex()

    private fun createPrimaryPrefs(context: Context): SharedPreferences {
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
            restoreFromMirrorIfPrimaryEmpty(encrypted)
            encrypted
        } catch (t: Throwable) {
            Log.w(TAG, "EncryptedSharedPreferences unavailable, falling back to plain prefs", t)
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).also { plain ->
                migrateLegacyPrefs(context, plain)
                restoreFromMirrorIfPrimaryEmpty(plain)
            }
        }
    }

    /** Moves any tokens saved by older versions in plain prefs into the primary store, then wipes them. */
    private fun migrateLegacyPrefs(context: Context, primary: SharedPreferences) {
        val legacy = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (legacy === primary || legacy.all.isEmpty()) return
        if (primary.getString(KEY_ACCESS_TOKEN, null).isNullOrBlank() &&
            primary.getString(KEY_REFRESH_TOKEN, null).isNullOrBlank()
        ) {
            copySession(from = legacy, to = primary)
        }
        legacy.edit().clear().commit()
    }

    private fun restoreFromMirrorIfPrimaryEmpty(primary: SharedPreferences) {
        val primaryEmpty = primary.getString(KEY_ACCESS_TOKEN, null).isNullOrBlank() &&
            primary.getString(KEY_REFRESH_TOKEN, null).isNullOrBlank()
        val mirrorHasSession = !mirrorPrefs.getString(KEY_ACCESS_TOKEN, null).isNullOrBlank() ||
            !mirrorPrefs.getString(KEY_REFRESH_TOKEN, null).isNullOrBlank()
        if (primaryEmpty && mirrorHasSession) {
            Log.i(TAG, "Restoring auth session from mirror preferences")
            copySession(from = mirrorPrefs, to = primary)
        }
    }

    private fun copySession(from: SharedPreferences, to: SharedPreferences) {
        to.edit()
            .putString(KEY_ACCESS_TOKEN, from.getString(KEY_ACCESS_TOKEN, null))
            .putString(KEY_REFRESH_TOKEN, from.getString(KEY_REFRESH_TOKEN, null))
            .putLong(KEY_EXPIRES_AT_MS, from.getLong(KEY_EXPIRES_AT_MS, 0L))
            .putString(KEY_USER_ID, from.getString(KEY_USER_ID, null))
            .commit()
    }

    fun isLoggedIn(): Boolean {
        return !getRefreshToken().isNullOrBlank() || !getAccessToken().isNullOrBlank()
    }

    fun getCachedUserId(): String? =
        primaryPrefs.getString(KEY_USER_ID, null)
            ?: mirrorPrefs.getString(KEY_USER_ID, null)

    fun cacheUserId(userId: String) {
        writeBoth { editor -> editor.putString(KEY_USER_ID, userId) }
    }

    fun syncUserIdFromAccessToken(accessToken: String): String? {
        val tokenUserId = JwtTokenParser.userId(accessToken)?.trim().orEmpty()
        if (tokenUserId.isBlank()) return null

        if (getCachedUserId() != tokenUserId) {
            cacheUserId(tokenUserId)
        }
        return tokenUserId
    }

    fun clear() {
        // Capture before wipe so library disk/RAM can be dropped for this account.
        val userId = getCachedUserId()
        writeBoth { editor ->
            editor.remove(KEY_ACCESS_TOKEN)
                .remove(KEY_REFRESH_TOKEN)
                .remove(KEY_EXPIRES_AT_MS)
                .remove(KEY_USER_ID)
        }
        // Business library cache is not stored in session prefs — clear explicitly.
        runCatching {
            SupabaseMusicRepository(appContext).clearLocalLibraryForUser(userId)
        }.onFailure { Log.w(TAG, "clear local library on session end failed", it) }
    }

    fun invalidateSession() {
        clear()
        AuthSessionState.notifyExpired()
    }

    fun saveSession(accessToken: String, refreshToken: String?, expiresInSeconds: Int?, userId: String?) {
        val expiresAtMs = resolveExpiresAtMs(accessToken, expiresInSeconds)

        if (refreshToken.isNullOrBlank()) {
            Log.w(TAG, "Auth response has no refresh token; session lasts until access token is rejected")
        } else if (expiresAtMs == null) {
            Log.w(TAG, "Auth response has no expiry and JWT exp claim is missing; will refresh only after 401")
        }

        writeBoth { editor ->
            editor.putString(KEY_ACCESS_TOKEN, accessToken)
                .putString(KEY_REFRESH_TOKEN, refreshToken)
                // 0 means "unknown" — do NOT treat as expired (see isNearExpiry).
                .putLong(KEY_EXPIRES_AT_MS, expiresAtMs ?: 0L)
                .putString(KEY_USER_ID, userId)
        }
        AuthSessionState.markActive()
        Log.d(
            TAG,
            "Session saved (refresh=${!refreshToken.isNullOrBlank()}, expiresAt=${expiresAtMs ?: 0L})"
        )
    }

    suspend fun getValidAccessToken(authApi: SupabaseAuthApi): String? {
        val token = getAccessToken()
        val refreshToken = getRefreshToken()
        if (token.isNullOrBlank()) {
            if (refreshToken.isNullOrBlank()) return null
            return when (val result = forceRefresh(authApi)) {
                is TokenRefreshResult.Success -> result.accessToken
                else -> null
            }
        }
        val expiresAtMs = getExpiresAtMs()

        // 无刷新令牌时无法续期：仍返回现有令牌，交由服务端以 401 判定是否失效。
        if (refreshToken.isNullOrBlank()) return token
        // 未知过期时间：不要主动刷，避免错误刷新接口把会话清掉。
        if (!isNearExpiry(expiresAtMs)) return token

        return refreshMutex.withLock {
            val existingToken = getAccessToken() ?: return@withLock null
            val existingRefresh = getRefreshToken()
            val existingExpiresAtMs = getExpiresAtMs()

            if (existingRefresh.isNullOrBlank()) return@withLock existingToken
            if (!isNearExpiry(existingExpiresAtMs)) return@withLock existingToken

            when (val result = refreshAccessToken(authApi, existingRefresh)) {
                is TokenRefreshResult.Success -> result.accessToken
                // Keep access token if refresh is hard-failed only after server said session is dead.
                // InvalidSession already cleared storage.
                TokenRefreshResult.InvalidSession -> null
                TokenRefreshResult.MissingRefreshToken,
                TokenRefreshResult.TransientFailure -> existingToken
            }
        }
    }

    suspend fun forceRefresh(authApi: SupabaseAuthApi): TokenRefreshResult {
        return refreshMutex.withLock {
            val currentRefreshToken = getRefreshToken()
                ?: return@withLock TokenRefreshResult.MissingRefreshToken
            refreshAccessToken(authApi, currentRefreshToken)
        }
    }

    private suspend fun refreshAccessToken(
        authApi: SupabaseAuthApi,
        refreshToken: String
    ): TokenRefreshResult {
        return try {
            val response = authApi.refreshToken(RefreshTokenRequest(refreshToken))
            if (!response.isSuccessful) {
                val code = response.code()
                Log.w(TAG, "Refresh HTTP $code")
                return when (classifyRefreshFailure(code)) {
                    RefreshFailure.INVALID_SESSION -> {
                        // Only clear when the server explicitly rejects the session.
                        invalidateSession()
                        TokenRefreshResult.InvalidSession
                    }
                    RefreshFailure.TRANSIENT -> TokenRefreshResult.TransientFailure
                }
            }
            val body = AuthResponseParser.parse(response.body()?.string().orEmpty())?.data
                ?: return TokenRefreshResult.TransientFailure
            val newAccess = body.token ?: body.access_token
                ?: return TokenRefreshResult.TransientFailure

            saveSession(
                accessToken = newAccess,
                // Some backends rotate refresh tokens; keep old if absent.
                refreshToken = body.refresh_token?.takeIf { it.isNotBlank() } ?: refreshToken,
                expiresInSeconds = body.expires_in
                    ?: body.expiresInMinutes?.let { (it * 60L).toInt() },
                userId = syncUserIdFromAccessToken(newAccess) ?: getCachedUserId()
            )

            TokenRefreshResult.Success(newAccess)
        } catch (ce: CancellationException) {
            throw ce
        } catch (e: Exception) {
            Log.w(TAG, "Access token refresh failed: ${e.javaClass.simpleName}: ${e.message}")
            TokenRefreshResult.TransientFailure
        }
    }

    private fun getAccessToken(): String? =
        primaryPrefs.getString(KEY_ACCESS_TOKEN, null)
            ?: mirrorPrefs.getString(KEY_ACCESS_TOKEN, null)

    private fun getRefreshToken(): String? =
        primaryPrefs.getString(KEY_REFRESH_TOKEN, null)
            ?: mirrorPrefs.getString(KEY_REFRESH_TOKEN, null)

    private fun getExpiresAtMs(): Long {
        val primary = primaryPrefs.getLong(KEY_EXPIRES_AT_MS, 0L)
        if (primary > 0L) return primary
        return mirrorPrefs.getLong(KEY_EXPIRES_AT_MS, 0L)
    }

    /**
     * Unknown expiry (0) must NOT force refresh — backends without exp claims were refreshing
     * on every request; a failing refresh endpoint then wiped the session every cold start.
     */
    private fun isNearExpiry(expiresAtMs: Long): Boolean {
        if (expiresAtMs <= 0L) return false
        return System.currentTimeMillis() >= (expiresAtMs - EXPIRY_SAFETY_WINDOW_MS)
    }

    private fun resolveExpiresAtMs(accessToken: String, expiresInSeconds: Int?): Long? {
        expiresInSeconds?.takeIf { it > 0 }?.let { seconds ->
            return System.currentTimeMillis() + (seconds.toLong() * 1000L)
        }
        JwtTokenParser.expiresAtMs(accessToken)?.let { return it }
        // Unknown: store 0 and only refresh after the server returns 401.
        return null
    }

    private fun writeBoth(block: (SharedPreferences.Editor) -> SharedPreferences.Editor) {
        // commit() so tokens survive process death right after login.
        primaryPrefs.edit().let { block(it).commit() }
        mirrorPrefs.edit().let { block(it).commit() }
    }

    private companion object {
        private const val TAG = "AuthSessionManager"
        private const val PREFS_NAME = "auth_prefs"
        private const val ENCRYPTED_PREFS_NAME = "auth_prefs_secure"
        private const val MIRROR_PREFS_NAME = "auth_prefs_mirror"
        private const val KEY_ACCESS_TOKEN = "access_token"
        private const val KEY_REFRESH_TOKEN = "refresh_token"
        private const val KEY_EXPIRES_AT_MS = "expires_at_ms"
        private const val KEY_USER_ID = "user_id"

        private const val EXPIRY_SAFETY_WINDOW_MS = 60_000L
    }
}

internal object JwtTokenParser {
    fun userId(accessToken: String): String? {
        return payload(accessToken)
            ?.stringOrNull("sub")
            ?.takeIf { it.isNotBlank() }
    }

    fun expiresAtMs(accessToken: String): Long? {
        val expSeconds = payload(accessToken)
            ?.longOrNull("exp")
            ?.takeIf { it > 0L }
            ?: return null
        return runCatching { Math.multiplyExact(expSeconds, 1000L) }.getOrNull()
    }

    private fun payload(accessToken: String): JsonObject? {
        return runCatching {
            val parts = accessToken.split('.')
            if (parts.size < 2) return null

            val encodedPayload = parts[1]
            val paddedPayload = buildString(encodedPayload.length + 4) {
                append(encodedPayload)
                repeat((4 - encodedPayload.length % 4) % 4) { append('=') }
            }

            val decoded = paddedPayload.decodeBase64()?.utf8() ?: return null
            JsonParser.parseString(decoded).asJsonObject
        }.getOrNull()
    }

    private fun JsonObject.stringOrNull(name: String): String? {
        val value = get(name) ?: return null
        if (value.isJsonNull || !value.isJsonPrimitive) return null
        return value.asString.trim().takeIf { it.isNotBlank() }
    }

    private fun JsonObject.longOrNull(name: String): Long? {
        val value = get(name) ?: return null
        return runCatching { value.asLong }.getOrNull()
            ?: runCatching { value.asDouble.toLong() }.getOrNull()
    }
}
