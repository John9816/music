package com.music.player.data.model

data class UserPlaylist(
    val id: String,
    val name: String,
    val description: String? = null,
    val coverUrl: String? = null,
    val source: String? = null,
    val sourceId: String? = null,
    val sourceUrl: String? = null,
    val creatorName: String? = null,
    val trackCount: Int = 0,
    val isPublic: Boolean = false,
    val createdAt: String? = null,
    val updatedAt: String? = null
)
