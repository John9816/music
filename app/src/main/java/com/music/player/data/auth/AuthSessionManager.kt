package com.music.player.data.auth

import android.annotation.SuppressLint
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

private const val TAG = "AuthSessionManager"
private const val PREFS_NAME = "auth_prefs"
private const val ENCRYPTED_PREFS_NAME = "auth_prefs_secure"
private const val MIRROR_PREFS_NAME = "auth_prefs_mirror"

/** Session store keys shared by the encrypted primary store, the plaintext fallback and the mirror. */
internal object AuthSessionKeys {
    const val ACCESS_TOKEN = "access_token"
    const val REFRESH_TOKEN = "refresh_token"
    const val EXPIRES_AT_MS = "expires_at_ms"
    const val USER_ID = "user_id"
}

/** Thin key/value facade over a session store so the auth logic is unit-testable on the JVM. */
internal interface SessionStore {
    fun readString(key: String): String?
    fun readLong(key: String): Long

    /** True when either token is present, regardless of expiry. */
    fun hasAnySessionToken(): Boolean
    fun isEmpty(): Boolean
    fun editor(): SessionStoreEditor
}

internal interface SessionStoreEditor {
    fun putString(key: String, value: String?): SessionStoreEditor
    fun putLong(key: String, value: Long): SessionStoreEditor
    fun remove(key: String): SessionStoreEditor
    fun commit()
}

/** [SessionStore] backed by Android [SharedPreferences]. */
internal class SharedPrefsSessionStore(
    internal val prefs: SharedPreferences
) : SessionStore {
    override fun readString(key: String): String? = prefs.getString(key, null)
    override fun readLong(key: String): Long = prefs.getLong(key, 0L)
    override fun hasAnySessionToken(): Boolean =
        !readString(AuthSessionKeys.ACCESS_TOKEN).isNullOrBlank() ||
            !readString(AuthSessionKeys.REFRESH_TOKEN).isNullOrBlank()
    override fun isEmpty(): Boolean = prefs.all.isEmpty()
    // The returned editor is committed by every caller (writeBoth/clearSessionKeys).
    @SuppressLint("CommitPrefEdits")
    override fun editor(): SessionStoreEditor = object : SessionStoreEditor {
        private val editor = prefs.edit()
        override fun putString(key: String, value: String?): SessionStoreEditor {
            if (value == null) editor.remove(key) else editor.putString(key, value)
            return this
        }
        override fun putLong(key: String, value: Long): SessionStoreEditor {
            editor.putLong(key, value)
            return this
        }
        override fun remove(key: String): SessionStoreEditor {
            editor.remove(key)
            return this
        }
        override fun commit() {
            editor.commit()
        }
    }
}

/**
 * Holds the resolved primary/mirror stores and whether the primary is encrypted at rest.
 */
private data class AuthStores(
    val primary: SessionStore,
    val mirror: SessionStore,
    val encryptedActive: Boolean
) {
    companion object {
        fun forContext(context: Context): AuthStores {
            // Plain mirror so a Keystore/EncryptedSharedPreferences glitch cannot wipe login
            // state on devices where encryption is unavailable. Must be built BEFORE the
            // primary store: createPrimaryPrefs reads the mirror.
            val mirror = SharedPrefsSessionStore(
                context.getSharedPreferences(MIRROR_PREFS_NAME, Context.MODE_PRIVATE)
            )
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
                val primary = SharedPrefsSessionStore(encrypted)
                migrateLegacyPrefs(legacyStore(context), primary)
                restoreFromMirrorIfPrimaryEmpty(primary, mirror)
                // Tokens now live in the encrypted store. The mirror copy is stale anyway
                // (it is never written while encryption works) and keeping it would both leak
                // plaintext tokens at rest and resurrect logged-out sessions on cold start.
                wipeMirrorIfPrimaryHasSession(primary, mirror)
                AuthStores(primary, mirror, encryptedActive = true)
            } catch (t: Throwable) {
                AuthLog.w(TAG, "EncryptedSharedPreferences unavailable, falling back to plain prefs", t)
                val primary = SharedPrefsSessionStore(
                    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                )
                migrateLegacyPrefs(legacyStore(context), primary)
                restoreFromMirrorIfPrimaryEmpty(primary, mirror)
                AuthStores(primary, mirror, encryptedActive = false)
            }
        }

        private fun legacyStore(context: Context): SessionStore =
            SharedPrefsSessionStore(
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            )
    }
}

class AuthSessionManager private constructor(
    private val stores: AuthStores,
    private val appContext: Context?
) {
    private val refreshMutex = Mutex()

    constructor(context: Context) : this(
        stores = AuthStores.forContext(context.applicationContext),
        appContext = context.applicationContext
    )

    /** Test seam: injects in-memory stores and skips Android-only cache cleanup. */
    internal constructor(
        primaryPrefs: SessionStore,
        mirrorPrefs: SessionStore,
        encryptedActive: Boolean
    ) : this(
        stores = AuthStores(primaryPrefs, mirrorPrefs, encryptedActive),
        appContext = null
    )

    private val primaryPrefs: SessionStore get() = stores.primary
    private val mirrorPrefs: SessionStore get() = stores.mirror
    private val encryptedActive: Boolean get() = stores.encryptedActive

    fun isLoggedIn(): Boolean {
        return !getRefreshToken().isNullOrBlank() || !getAccessToken().isNullOrBlank()
    }

    fun getCachedUserId(): String? =
        primaryPrefs.readString(AuthSessionKeys.USER_ID)
            ?: mirrorPrefs.readString(AuthSessionKeys.USER_ID)

    fun cacheUserId(userId: String) {
        writeBoth { editor -> editor.putString(AuthSessionKeys.USER_ID, userId) }
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
        writeBoth(::clearSessionKeys)
        // Logout must also wipe the plaintext mirror unconditionally: the getters fall
        // back to it, and a stale copy would resurrect the session on the next cold start.
        clearSessionKeys(mirrorPrefs.editor()).commit()

        // Business library cache is not stored in session prefs — clear explicitly.
        appContext?.let { ctx ->
            runCatching {
                SupabaseMusicRepository(ctx).clearLocalLibraryForUser(userId)
            }.onFailure { AuthLog.w(TAG, "clear local library on session end failed", it) }
        }
        // Clear music/album memory caches so a different user never sees stale data.
        runCatching {
            com.music.player.data.repository.MusicRepository.clearCaches()
        }.onFailure { AuthLog.w(TAG, "clear music caches on session end failed", it) }
        runCatching {
            com.music.player.data.repository.AlbumRepository.clearCaches()
        }.onFailure { AuthLog.w(TAG, "clear album caches on session end failed", it) }
    }

    fun invalidateSession() {
        clear()
        AuthSessionState.notifyExpired()
    }

    fun saveSession(
        accessToken: String,
        refreshToken: String?,
        expiresInSeconds: Int?,
        userId: String?
    ) {
        val expiresAtMs = resolveExpiresAtMs(accessToken, expiresInSeconds)

        if (refreshToken.isNullOrBlank()) {
            AuthLog.w(TAG, "Auth response has no refresh token; session lasts until access token is rejected")
        } else if (expiresAtMs == null) {
            AuthLog.w(TAG, "Auth response has no expiry and JWT exp claim is missing; will refresh only after 401")
        }

        writeBoth { editor ->
            editor.putString(AuthSessionKeys.ACCESS_TOKEN, accessToken)
                .putString(AuthSessionKeys.REFRESH_TOKEN, refreshToken)
                // 0 means "unknown" — do NOT treat as expired (see isNearExpiry).
                .putLong(AuthSessionKeys.EXPIRES_AT_MS, expiresAtMs ?: 0L)
                .putString(AuthSessionKeys.USER_ID, userId)
        }
        AuthSessionState.markActive()
        AuthLog.d(
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
        // 未知过期时间：不要主动刷新，避免错误刷新接口把会话清掉。
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
                AuthLog.w(TAG, "Refresh HTTP $code")
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
            AuthLog.w(TAG, "Access token refresh failed: ${e.javaClass.simpleName}: ${e.message}")
            TokenRefreshResult.TransientFailure
        }
    }

    private fun getAccessToken(): String? =
        primaryPrefs.readString(AuthSessionKeys.ACCESS_TOKEN)
            ?: mirrorPrefs.readString(AuthSessionKeys.ACCESS_TOKEN)

    private fun getRefreshToken(): String? =
        primaryPrefs.readString(AuthSessionKeys.REFRESH_TOKEN)
            ?: mirrorPrefs.readString(AuthSessionKeys.REFRESH_TOKEN)

    private fun getExpiresAtMs(): Long {
        val primary = primaryPrefs.readLong(AuthSessionKeys.EXPIRES_AT_MS)
        if (primary > 0L) return primary
        return mirrorPrefs.readLong(AuthSessionKeys.EXPIRES_AT_MS)
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

    private fun writeBoth(block: (SessionStoreEditor) -> SessionStoreEditor) {
        // commit() so tokens survive process death right after login.
        block(primaryPrefs.editor()).commit()
        // Only write the plaintext mirror when encrypted storage is unavailable;
        // otherwise tokens stay encrypted at rest and the mirror stays clean.
        if (!encryptedActive) {
            block(mirrorPrefs.editor()).commit()
        }
    }

    private companion object {
        const val EXPIRY_SAFETY_WINDOW_MS = 60_000L
    }
}

/** Moves any tokens saved by older versions in plain prefs into the primary store, then wipes them. */
internal fun migrateLegacyPrefs(legacy: SessionStore, primary: SessionStore) {
    if (legacy === primary) return
    if (legacy is SharedPrefsSessionStore && primary is SharedPrefsSessionStore &&
        legacy.prefs === primary.prefs
    ) {
        // Fallback path: primary IS the legacy file — do not wipe it.
        return
    }
    if (legacy.isEmpty()) return
    if (primary.readString(AuthSessionKeys.ACCESS_TOKEN).isNullOrBlank() &&
        primary.readString(AuthSessionKeys.REFRESH_TOKEN).isNullOrBlank()
    ) {
        copySession(from = legacy, to = primary)
    }
    clearSessionKeys(legacy.editor()).commit()
}

/** Restores a session from the mirror only when the primary store is completely empty. */
internal fun restoreFromMirrorIfPrimaryEmpty(primary: SessionStore, mirror: SessionStore) {
    val primaryEmpty = primary.readString(AuthSessionKeys.ACCESS_TOKEN).isNullOrBlank() &&
        primary.readString(AuthSessionKeys.REFRESH_TOKEN).isNullOrBlank()
    if (primaryEmpty && mirror.hasAnySessionToken()) {
        AuthLog.i(TAG, "Restoring auth session from mirror preferences")
        copySession(from = mirror, to = primary)
    }
}

/** One-time cleanup: once tokens are in the (encrypted) primary store, drop the plaintext mirror copy. */
internal fun wipeMirrorIfPrimaryHasSession(primary: SessionStore, mirror: SessionStore) {
    val primaryHasSession = !primary.readString(AuthSessionKeys.ACCESS_TOKEN).isNullOrBlank() ||
        !primary.readString(AuthSessionKeys.REFRESH_TOKEN).isNullOrBlank()
    if (!primaryHasSession) return
    clearSessionKeys(mirror.editor()).commit()
}

internal fun clearSessionKeys(editor: SessionStoreEditor): SessionStoreEditor =
    editor.remove(AuthSessionKeys.ACCESS_TOKEN)
        .remove(AuthSessionKeys.REFRESH_TOKEN)
        .remove(AuthSessionKeys.EXPIRES_AT_MS)
        .remove(AuthSessionKeys.USER_ID)

internal fun copySession(from: SessionStore, to: SessionStore) {
    to.editor()
        .putString(AuthSessionKeys.ACCESS_TOKEN, from.readString(AuthSessionKeys.ACCESS_TOKEN))
        .putString(AuthSessionKeys.REFRESH_TOKEN, from.readString(AuthSessionKeys.REFRESH_TOKEN))
        .putLong(AuthSessionKeys.EXPIRES_AT_MS, from.readLong(AuthSessionKeys.EXPIRES_AT_MS))
        .putString(AuthSessionKeys.USER_ID, from.readString(AuthSessionKeys.USER_ID))
        .commit()
}

/** Log wrapper that never crashes the caller — also keeps the class JVM-unit-test friendly. */
internal object AuthLog {
    fun d(tag: String, msg: String) = runCatching { Log.d(tag, msg) }
    fun i(tag: String, msg: String) = runCatching { Log.i(tag, msg) }
    fun w(tag: String, msg: String) = runCatching { Log.w(tag, msg) }
    fun w(tag: String, msg: String, t: Throwable) = runCatching { Log.w(tag, msg, t) }
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
