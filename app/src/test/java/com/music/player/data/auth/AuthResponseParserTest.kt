package com.music.player.data.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class AuthResponseParserTest {
    @Test
    fun parsesWebsiteEnvelopeAndRefreshToken() {
        val parsed = AuthResponseParser.parse(
            """{"code":0,"message":"ok","data":{"token":"access","refreshToken":"refresh","expiresInMinutes":120,"username":"alice"}}"""
        )

        assertEquals(0, parsed?.code)
        assertEquals("access", parsed?.data?.token)
        assertEquals("access", parsed?.data?.access_token)
        assertEquals("refresh", parsed?.data?.refresh_token)
        assertEquals(120L, parsed?.data?.expiresInMinutes)
        assertEquals("alice", parsed?.data?.username)
    }

    @Test
    fun parsesStandardSupabaseResponse() {
        val parsed = AuthResponseParser.parse(
            """{"access_token":"access","refresh_token":"refresh","expires_in":3600,"token_type":"bearer"}"""
        )

        assertNotNull(parsed)
        assertEquals("access", parsed?.data?.token)
        assertEquals("refresh", parsed?.data?.refresh_token)
        assertEquals(3600, parsed?.data?.expires_in)
        assertEquals("bearer", parsed?.data?.tokenType)
    }
}
