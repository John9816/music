package com.music.player.data.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Base64

class JwtTokenParserTest {
    @Test
    fun parsesUserIdAndExpiryFromJwtPayload() {
        val token = jwt("""{"sub":"user-123","exp":1893456000}""")

        assertEquals("user-123", JwtTokenParser.userId(token))
        assertEquals(1_893_456_000_000L, JwtTokenParser.expiresAtMs(token))
    }

    @Test
    fun returnsNullForMalformedToken() {
        assertNull(JwtTokenParser.userId("not-a-jwt"))
        assertNull(JwtTokenParser.expiresAtMs("not-a-jwt"))
    }

    private fun jwt(payload: String): String {
        val header = base64Url("""{"alg":"none","typ":"JWT"}""")
        return "$header.${base64Url(payload)}."
    }

    private fun base64Url(value: String): String {
        return Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString(value.toByteArray(Charsets.UTF_8))
    }
}
