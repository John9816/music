package com.music.player.playback

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.Song

/**
 * Disk-backed snapshot of the in-memory playback session so force-stop / process death
 * can restore the current track, progress, and remaining playlist queue.
 */
internal class PlaybackStateStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val gson = Gson()

    fun save(snapshot: Snapshot) {
        runCatching {
            prefs.edit()
                .putString(KEY_JSON, gson.toJson(snapshot))
                .commit()
        }.onFailure { Log.w(TAG, "save playback state failed", it) }
    }

    fun load(): Snapshot? {
        val raw = prefs.getString(KEY_JSON, null)?.trim().orEmpty()
        if (raw.isBlank()) return null
        return runCatching { gson.fromJson(raw, Snapshot::class.java) }
            .onFailure { Log.w(TAG, "load playback state failed", it) }
            .getOrNull()
            ?.takeIf { it.currentSong != null || it.queue.isNotEmpty() }
    }

    fun clear() {
        prefs.edit().remove(KEY_JSON).commit()
    }

    data class Snapshot(
        @SerializedName("currentSong") val currentSong: SongDto? = null,
        @SerializedName("positionMs") val positionMs: Long = 0L,
        @SerializedName("playWhenReady") val playWhenReady: Boolean = false,
        @SerializedName("queue") val queue: List<SongDto> = emptyList(),
        @SerializedName("history") val history: List<SongDto> = emptyList(),
        @SerializedName("viewMode") val viewMode: String = "RECENT"
    )

    /** URL / lyric are ephemeral; only identity + display fields are persisted. */
    data class SongDto(
        val id: String,
        val name: String,
        val artists: List<ArtistDto> = emptyList(),
        val album: AlbumDto = AlbumDto(),
        val duration: Long = 0L,
        val source: String = "netease"
    ) {
        fun toSong(): Song = Song(
            id = id,
            name = name,
            artists = artists.map { Artist(id = it.id, name = it.name) },
            album = Album(
                id = album.id,
                name = album.name,
                picUrl = album.picUrl
            ),
            duration = duration,
            url = null,
            source = source.ifBlank { "netease" },
            lyric = null
        )

        companion object {
            fun from(song: Song): SongDto = SongDto(
                id = song.id,
                name = song.name,
                artists = song.artists.map { ArtistDto(it.id, it.name) },
                album = AlbumDto(
                    id = song.album.id,
                    name = song.album.name,
                    picUrl = song.album.picUrl
                ),
                duration = song.duration,
                source = song.source
            )
        }
    }

    data class ArtistDto(
        val id: String = "",
        val name: String = ""
    )

    data class AlbumDto(
        val id: String = "",
        val name: String = "",
        val picUrl: String = ""
    )

    private companion object {
        private const val TAG = "PlaybackStateStore"
        private const val PREFS_NAME = "playback_session_v1"
        private const val KEY_JSON = "snapshot"
    }
}
