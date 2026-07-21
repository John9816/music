package com.music.player.ui.util

import com.music.player.data.auth.UserProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class UserAvatarUrlTest {

    @Test
    fun absoluteApiUrl_joinsRelativeAvatarPath() {
        val absolute = absoluteApiUrl("/api/v1/user/avatar/2-abc.png")
        assertEquals(
            "https://api.751152.xyz/api/v1/user/avatar/2-abc.png",
            absolute
        )
    }

    @Test
    fun absoluteApiUrl_keepsFullHttps() {
        val url = "https://cdn.example.com/a.png"
        assertEquals(url, absoluteApiUrl(url))
    }

    @Test
    fun resolveAvatarModel_usesAbsoluteRemoteForSitePath() {
        val profile = UserProfile(
            id = "2",
            username = "u",
            avatar_url = "/api/v1/user/avatar/2-9f3bef.png"
        )
        val model = profile.resolveAvatarModel()
        assertTrue(model is String)
        assertEquals(
            "https://api.751152.xyz/api/v1/user/avatar/2-9f3bef.png",
            model
        )
    }
}
