package com.music.player.data.auth

import org.junit.Assert.assertEquals
import org.junit.Test

class AuthSessionStateTest {
    @Test
    fun `only hard auth failures invalidate the session`() {
        assertEquals(RefreshFailure.INVALID_SESSION, classifyRefreshFailure(401))
        assertEquals(RefreshFailure.INVALID_SESSION, classifyRefreshFailure(403))
    }

    @Test
    fun `network and soft failures are transient`() {
        assertEquals(RefreshFailure.TRANSIENT, classifyRefreshFailure(null))
        assertEquals(RefreshFailure.TRANSIENT, classifyRefreshFailure(400))
        assertEquals(RefreshFailure.TRANSIENT, classifyRefreshFailure(404))
        assertEquals(RefreshFailure.TRANSIENT, classifyRefreshFailure(408))
        assertEquals(RefreshFailure.TRANSIENT, classifyRefreshFailure(500))
    }
}
