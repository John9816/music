package com.music.player.data.auth

import org.junit.Assert.assertEquals
import org.junit.Test

class AuthSessionStateTest {
    @Test
    fun `refresh 400 and 401 invalidate the session`() {
        assertEquals(RefreshFailure.INVALID_SESSION, classifyRefreshFailure(400))
        assertEquals(RefreshFailure.INVALID_SESSION, classifyRefreshFailure(401))
    }

    @Test
    fun `network and server failures are transient`() {
        assertEquals(RefreshFailure.TRANSIENT, classifyRefreshFailure(null))
        assertEquals(RefreshFailure.TRANSIENT, classifyRefreshFailure(408))
        assertEquals(RefreshFailure.TRANSIENT, classifyRefreshFailure(500))
    }
}
