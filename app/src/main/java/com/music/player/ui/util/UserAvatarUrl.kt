package com.music.player.ui.util

import android.net.Uri
import com.music.player.data.auth.UserProfile

fun UserProfile.resolveAvatarUrl(): String {
    val direct = avatar_url?.trim().orEmpty()
    if (direct.isNotBlank()) return direct

    val seed = nickname?.trim().orEmpty()
        .ifBlank { username?.trim().orEmpty() }
        .ifBlank { email?.trim().orEmpty() }
        .ifBlank { id }

    return "https://api.dicebear.com/9.x/initials/png?seed=${Uri.encode(seed)}&radius=50&backgroundType=gradientLinear"
}
