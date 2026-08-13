package com.music.player

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

private const val SECURE_PREFS_NAME = "auth_prefs_secure"
private const val PLAIN_PREFS_NAME = "auth_prefs"
private const val MIRROR_PREFS_NAME = "auth_prefs_mirror"

private object LegacyAuthKeys {
    const val ACCESS_TOKEN = "access_token"
    const val REFRESH_TOKEN = "refresh_token"
    const val EXPIRES_AT_MS = "expires_at_ms"
    const val USER_ID = "user_id"

    val all = listOf(ACCESS_TOKEN, REFRESH_TOKEN, EXPIRES_AT_MS, USER_ID)
}

internal data class LegacyAuthSession(
    val accessToken: String,
    val refreshToken: String,
    val expiresAtMs: Long?,
    val userId: String?,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "accessToken" to accessToken,
        "refreshToken" to refreshToken,
        "expiresAtMs" to expiresAtMs,
        "userId" to userId,
    )
}

internal interface LegacyPreferenceStore {
    fun value(key: String): Any?

    fun clearSession()
}

private class SharedPreferencesLegacyStore(
    private val preferences: SharedPreferences,
) : LegacyPreferenceStore {
    override fun value(key: String): Any? = preferences.all[key]

    override fun clearSession() {
        val editor = preferences.edit()
        LegacyAuthKeys.all.forEach(editor::remove)
        editor.commit()
    }
}

internal class LegacyAuthSessionStore(
    private val providers: List<() -> LegacyPreferenceStore?>,
) {
    fun read(): LegacyAuthSession? {
        for (provider in providers) {
            val store = runCatching { provider() }.getOrNull() ?: continue
            val accessToken = normalizedString(store.value(LegacyAuthKeys.ACCESS_TOKEN))
            val refreshToken = normalizedString(store.value(LegacyAuthKeys.REFRESH_TOKEN))
            if (accessToken == null || refreshToken == null) continue

            return LegacyAuthSession(
                accessToken = accessToken,
                refreshToken = refreshToken,
                expiresAtMs = positiveLong(store.value(LegacyAuthKeys.EXPIRES_AT_MS)),
                userId = normalizedString(store.value(LegacyAuthKeys.USER_ID)),
            )
        }
        return null
    }

    fun clear() {
        providers.forEach { provider ->
            runCatching { provider()?.clearSession() }
        }
    }

    private fun normalizedString(value: Any?): String? =
        (value as? String)?.trim()?.takeIf(String::isNotEmpty)

    private fun positiveLong(value: Any?): Long? {
        val parsed = when (value) {
            is Number -> value.toLong()
            else -> value?.toString()?.toLongOrNull()
        }
        return parsed?.takeIf { it > 0L }
    }

    companion object {
        fun fromContext(context: Context): LegacyAuthSessionStore {
            val applicationContext = context.applicationContext
            return LegacyAuthSessionStore(
                listOf(
                    {
                        val masterKey = MasterKey.Builder(applicationContext)
                            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                            .build()
                        val preferences = EncryptedSharedPreferences.create(
                            applicationContext,
                            SECURE_PREFS_NAME,
                            masterKey,
                            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
                        )
                        SharedPreferencesLegacyStore(preferences)
                    },
                    {
                        SharedPreferencesLegacyStore(
                            applicationContext.getSharedPreferences(
                                PLAIN_PREFS_NAME,
                                Context.MODE_PRIVATE,
                            ),
                        )
                    },
                    {
                        SharedPreferencesLegacyStore(
                            applicationContext.getSharedPreferences(
                                MIRROR_PREFS_NAME,
                                Context.MODE_PRIVATE,
                            ),
                        )
                    },
                ),
            )
        }
    }
}
