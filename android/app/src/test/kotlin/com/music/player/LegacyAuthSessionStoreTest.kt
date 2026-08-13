package com.music.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LegacyAuthSessionStoreTest {
    @Test
    fun `secure session has priority and read does not clear stores`() {
        val secure = FakeLegacyPreferenceStore(
            mapOf(
                "access_token" to "secure-access",
                "refresh_token" to "secure-refresh",
                "expires_at_ms" to 123456L,
                "user_id" to "42",
            ),
        )
        val plain = FakeLegacyPreferenceStore(
            mapOf(
                "access_token" to "plain-access",
                "refresh_token" to "plain-refresh",
            ),
        )
        val store = LegacyAuthSessionStore(listOf({ secure }, { plain }))

        val session = store.read()

        assertEquals("secure-access", session?.accessToken)
        assertEquals("secure-refresh", session?.refreshToken)
        assertEquals(123456L, session?.expiresAtMs)
        assertEquals("42", session?.userId)
        assertEquals(0, secure.clearCalls)
        assertEquals(0, plain.clearCalls)
    }

    @Test
    fun `provider failure falls back to the next complete store`() {
        val plain = FakeLegacyPreferenceStore(
            mapOf(
                "access_token" to "plain-access",
                "refresh_token" to "plain-refresh",
            ),
        )
        val store = LegacyAuthSessionStore(
            listOf(
                { throw IllegalStateException("keystore unavailable") },
                { plain },
            ),
        )

        assertEquals("plain-access", store.read()?.accessToken)
    }

    @Test
    fun `partial store falls back instead of returning partial credentials`() {
        val secure = FakeLegacyPreferenceStore(
            mapOf("access_token" to "partial-access"),
        )
        val mirror = FakeLegacyPreferenceStore(
            mapOf(
                "access_token" to "mirror-access",
                "refresh_token" to "mirror-refresh",
                "expires_at_ms" to "987654",
            ),
        )
        val store = LegacyAuthSessionStore(listOf({ secure }, { mirror }))

        val session = store.read()

        assertEquals("mirror-access", session?.accessToken)
        assertEquals(987654L, session?.expiresAtMs)
    }

    @Test
    fun `all partial stores produce no migration session`() {
        val accessOnly = FakeLegacyPreferenceStore(
            mapOf("access_token" to "partial-access"),
        )
        val refreshOnly = FakeLegacyPreferenceStore(
            mapOf("refresh_token" to "partial-refresh"),
        )
        val store = LegacyAuthSessionStore(
            listOf({ accessOnly }, { refreshOnly }),
        )

        assertNull(store.read())
    }

    @Test
    fun `clear attempts every available store and is idempotent`() {
        val secure = FakeLegacyPreferenceStore(emptyMap())
        val plain = FakeLegacyPreferenceStore(emptyMap())
        val mirror = FakeLegacyPreferenceStore(emptyMap())
        val store = LegacyAuthSessionStore(
            listOf(
                { secure },
                { throw IllegalStateException("keystore unavailable") },
                { plain },
                { mirror },
            ),
        )

        store.clear()
        store.clear()

        assertEquals(2, secure.clearCalls)
        assertEquals(2, plain.clearCalls)
        assertEquals(2, mirror.clearCalls)
    }
}

private class FakeLegacyPreferenceStore(
    private val values: Map<String, Any?>,
) : LegacyPreferenceStore {
    var clearCalls = 0

    override fun value(key: String): Any? = values[key]

    override fun clearSession() {
        clearCalls++
    }
}
