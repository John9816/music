package com.music.player.data.model

data class Song(
    val id: String,
    val name: String,
    val artists: List<Artist>,
    val album: Album,
    val duration: Long,
    var url: String? = null,
    val source: String = "netease",
    var lyric: String? = null
)

data class Artist(
    val id: String,
    val name: String
)

data class Album(
    val id: String,
    val name: String,
    val picUrl: String
)

data class Playlist(
    val id: String,
    val name: String,
    val coverImgUrl: String,
    val description: String,
    val trackCount: Int,
    val playCount: Long,
    val source: String = "netease"
)

data class LyricLine(
    val time: Float,
    val text: String
)
