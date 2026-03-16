package com.music.player.data.model

data class PlaylistCategoryGroup(
    val id: Int,
    val name: String
)

data class PlaylistCategoryCatalog(
    val groups: List<PlaylistCategoryGroup>,
    val categories: List<PlaylistCategory>
)

