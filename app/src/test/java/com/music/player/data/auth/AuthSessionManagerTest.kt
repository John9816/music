package com.music.player.data.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthSessionManagerTest {

    private class FakeStore : SessionStore {
        private val map = HashMap<String, Any>()

        override fun readString(key: String): String? = map[key] as? String
        override fun readLong(key: String): Long = map[key] as? Long ?: 0L
        override fun hasAnySessionToken(): Boolean =
            !readString(AuthSessionKeys.ACCESS_TOKEN).isNullOrBlank() ||
                !readString(AuthSessionKeys.REFRESH_TOKEN).isNullOrBlank()
        override fun isEmpty(): Boolean = map.isEmpty()
        override fun editor(): SessionStoreEditor = object : SessionStoreEditor {
            override fun putString(key: String, value: String?): SessionStoreEditor {
                if (value == null) map.remove(key) else map[key] = value
                return this
            }
            override fun putLong(key: String, value: Long): SessionStoreEditor {
                map[key] = value
                return this
            }
            override fun remove(key: String): SessionStoreEditor {
                map.remove(key)
                return this
            }
            override fun commit() = Unit
        }
    }

    @Test
    fun saveWithEncryptionNeverWritesPlainMirror() {
        val primary = FakeStore()
        val mirror = FakeStore()
        val manager = AuthSessionManager(primary, mirror, encryptedActive = true)

        manager.saveSession("access", "refresh", 3600, "u1")

        assertEquals("access", primary.readString(AuthSessionKeys.ACCESS_TOKEN))
        assertTrue("plaintext mirror must stay clean while encryption is active", mirror.isEmpty())
    }

    @Test
    fun saveWithoutEncryptionKeepsMirrorFallbackInSync() {
        val primary = FakeStore()
        val mirror = FakeStore()
        val manager = AuthSessionManager(primary, mirror, encryptedActive = false)

        manager.saveSession("access", "refresh", 3600, "u1")

        assertEquals("access", mirror.readString(AuthSessionKeys.ACCESS_TOKEN))
        assertFalse(mirror.isEmpty())
    }

    @Test
    fun logoutClearsStalePlainMirrorLeftByOlderVersions() {
        // Older app versions wrote tokens into the plaintext mirror. After an upgrade the
        // encrypted primary is used, but logout must still wipe that legacy plaintext copy.
        val primary = FakeStore()
        val mirror = FakeStore()
        mirror.editor()
            .putString(AuthSessionKeys.ACCESS_TOKEN, "legacy-access")
            .putString(AuthSessionKeys.REFRESH_TOKEN, "legacy-refresh")
            .putLong(AuthSessionKeys.EXPIRES_AT_MS, 0L)
            .putString(AuthSessionKeys.USER_ID, "legacy-user")
            .commit()
        val manager = AuthSessionManager(primary, mirror, encryptedActive = true)

        manager.clear()

        assertFalse(manager.isLoggedIn())
        assertNull(primary.readString(AuthSessionKeys.ACCESS_TOKEN))
        assertNull(primary.readString(AuthSessionKeys.REFRESH_TOKEN))
        assertNull("stale mirror token must not survive logout", mirror.readString(AuthSessionKeys.ACCESS_TOKEN))
        assertNull("stale mirror refresh token must not survive logout", mirror.readString(AuthSessionKeys.REFRESH_TOKEN))
        assertTrue(mirror.isEmpty())
    }

    @Test
    fun coldStartAfterLogoutDoesNotResurrectSession() {
        val primary = FakeStore()
        val mirror = FakeStore()
        val manager = AuthSessionManager(primary, mirror, encryptedActive = true)
        manager.saveSession("access", "refresh", 3600, "u1")
        manager.clear()

        // Simulate a process restart over the same on-disk stores.
        val restarted = AuthSessionManager(primary, mirror, encryptedActive = true)

        assertFalse("logged-out session must not be restored on cold start", restarted.isLoggedIn())
        assertNull(restarted.getCachedUserId())
    }

    @Test
    fun logoutWithoutEncryptionClearsBothStores() {
        val primary = FakeStore()
        val mirror = FakeStore()
        val manager = AuthSessionManager(primary, mirror, encryptedActive = false)
        manager.saveSession("access", "refresh", 3600, "u1")
        assertFalse(mirror.isEmpty())

        manager.clear()

        assertFalse(manager.isLoggedIn())
        assertTrue(primary.isEmpty())
        assertTrue(mirror.isEmpty())
    }

    @Test
    fun restoreFromMirrorCopiesIntoEmptyPrimary() {
        val primary = FakeStore()
        val mirror = FakeStore()
        mirror.editor()
            .putString(AuthSessionKeys.ACCESS_TOKEN, "mirror-access")
            .putString(AuthSessionKeys.REFRESH_TOKEN, "mirror-refresh")
            .commit()

        restoreFromMirrorIfPrimaryEmpty(primary, mirror)

        assertEquals("mirror-access", primary.readString(AuthSessionKeys.ACCESS_TOKEN))
        assertEquals("mirror-refresh", primary.readString(AuthSessionKeys.REFRESH_TOKEN))
    }

    @Test
    fun restoreFromMirrorDoesNotOverwriteExistingPrimarySession() {
        val primary = FakeStore()
        val mirror = FakeStore()
        primary.editor()
            .putString(AuthSessionKeys.ACCESS_TOKEN, "primary-access")
            .commit()
        mirror.editor()
            .putString(AuthSessionKeys.ACCESS_TOKEN, "mirror-access")
            .commit()

        restoreFromMirrorIfPrimaryEmpty(primary, mirror)

        assertEquals("primary-access", primary.readString(AuthSessionKeys.ACCESS_TOKEN))
    }

    @Test
    fun wipeMirrorRemovesPlaintextAfterMigration() {
        val primary = FakeStore()
        val mirror = FakeStore()
        primary.editor().putString(AuthSessionKeys.ACCESS_TOKEN, "encrypted-access").commit()
        mirror.editor()
            .putString(AuthSessionKeys.ACCESS_TOKEN, "plain-access")
            .putString(AuthSessionKeys.REFRESH_TOKEN, "plain-refresh")
            .commit()

        wipeMirrorIfPrimaryHasSession(primary, mirror)

        assertTrue(mirror.isEmpty())
    }

    @Test
    fun migrateLegacyPrefsMovesThenClearsLegacy() {
        val legacy = FakeStore()
        val primary = FakeStore()
        legacy.editor()
            .putString(AuthSessionKeys.ACCESS_TOKEN, "old-access")
            .putString(AuthSessionKeys.REFRESH_TOKEN, "old-refresh")
            .putString(AuthSessionKeys.USER_ID, "old-user")
            .commit()

        migrateLegacyPrefs(legacy, primary)

        assertEquals("old-access", primary.readString(AuthSessionKeys.ACCESS_TOKEN))
        assertEquals("old-refresh", primary.readString(AuthSessionKeys.REFRESH_TOKEN))
        assertTrue(legacy.isEmpty())
    }
}
