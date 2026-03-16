package com.music.player.data.model

data class PlaylistCategory(
    val apiName: String,
    val name: String,
    val groupId: Int? = null,
    val groupName: String? = null,
    val hot: Boolean = false
) {
    val displayName: String =
        if (groupName.isNullOrBlank() || groupName == name) name else "$groupName · $name"

    companion object {
        val All = PlaylistCategory(apiName = "", name = "全部", groupId = null, groupName = null, hot = true)
    }
}

