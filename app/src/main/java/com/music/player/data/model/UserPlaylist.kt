package com.music.player.data.model

data class UserPlaylist(
    val id: String,
    val name: String,
    val description: String? = null,
    val coverUrl: String? = null,
    val isPublic: Boolean = false,
    val createdAt: String? = null,
    val updatedAt: String? = null
)

