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
 *
 * All DTO fields use [@SerializedName] so R8/minify cannot break Gson round-trips.
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
            .onFailure {
                Log.w(TAG, "load playback state failed, clearing", it)
                clear()
            }
            .getOrNull()
            ?.sanitize()
            ?.takeIf { it.currentSong != null || !it.queue.isNullOrEmpty() }
    }

    fun clear() {
        runCatching { prefs.edit().remove(KEY_JSON).commit() }
    }

    data class Snapshot(
        @SerializedName("currentSong") val currentSong: SongDto? = null,
        @SerializedName("positionMs") val positionMs: Long = 0L,
        @SerializedName("playWhenReady") val playWhenReady: Boolean = false,
        @SerializedName("queue") val queue: List<SongDto>? = emptyList(),
        @SerializedName("history") val history: List<SongDto>? = emptyList(),
        @SerializedName("viewMode") val viewMode: String? = "RECENT"
    ) {
        fun sanitize(): Snapshot {
            val safeQueue = queue.orEmpty().mapNotNull { it.sanitizeOrNull() }
            val safeHistory = history.orEmpty().mapNotNull { it.sanitizeOrNull() }
            return copy(
                currentSong = currentSong?.sanitizeOrNull(),
                positionMs = positionMs.coerceAtLeast(0L),
                queue = safeQueue,
                history = safeHistory,
                viewMode = viewMode?.takeIf { it.isNotBlank() } ?: "RECENT"
            )
        }
    }

    /** URL / lyric are ephemeral; only identity + display fields are persisted. */
    data class SongDto(
        @SerializedName("id") val id: String? = null,
        @SerializedName("name") val name: String? = null,
        @SerializedName("artists") val artists: List<ArtistDto>? = emptyList(),
        @SerializedName("album") val album: AlbumDto? = null,
        @SerializedName("duration") val duration: Long = 0L,
        @SerializedName("source") val source: String? = "netease"
    ) {
        fun sanitizeOrNull(): SongDto? {
            val safeId = id?.trim().orEmpty()
            if (safeId.isBlank()) return null
            return SongDto(
                id = safeId,
                name = name?.trim().orEmpty().ifBlank { "Unknown" },
                artists = artists.orEmpty().mapNotNull { it.sanitizeOrNull() },
                album = album?.sanitize() ?: AlbumDto(),
                duration = duration.coerceAtLeast(0L),
                source = source?.trim().orEmpty().ifBlank { "netease" }
            )
        }

        fun toSong(): Song {
            val safe = sanitizeOrNull()
                ?: SongDto(id = "unknown", name = "Unknown", artists = emptyList(), album = AlbumDto())
            return Song(
                id = safe.id.orEmpty(),
                name = safe.name.orEmpty(),
                artists = safe.artists.orEmpty().map {
                    Artist(id = it.id.orEmpty(), name = it.name.orEmpty().ifBlank { "Unknown" })
                },
                album = Album(
                    id = safe.album?.id.orEmpty(),
                    name = safe.album?.name.orEmpty(),
                    picUrl = safe.album?.picUrl.orEmpty()
                ),
                duration = safe.duration,
                url = null,
                source = safe.source.orEmpty().ifBlank { "netease" },
                lyric = null
            )
        }

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
        @SerializedName("id") val id: String? = null,
        @SerializedName("name") val name: String? = null
    ) {
        fun sanitizeOrNull(): ArtistDto? {
            val n = name?.trim().orEmpty()
            if (n.isBlank() && id.isNullOrBlank()) return null
            return ArtistDto(id = id.orEmpty(), name = n.ifBlank { "Unknown" })
        }
    }

    data class AlbumDto(
        @SerializedName("id") val id: String? = null,
        @SerializedName("name") val name: String? = null,
        @SerializedName("picUrl") val picUrl: String? = null
    ) {
        fun sanitize(): AlbumDto = AlbumDto(
            id = id.orEmpty(),
            name = name.orEmpty(),
            picUrl = picUrl.orEmpty()
        )
    }

    private companion object {
        private const val TAG = "PlaybackStateStore"
        private const val PREFS_NAME = "playback_session_v1"
        private const val KEY_JSON = "snapshot"
    }
}
