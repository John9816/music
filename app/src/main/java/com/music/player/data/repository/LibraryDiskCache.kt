package com.music.player.data.repository

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.Song
import com.music.player.data.model.UserPlaylist

/**
 * Disk snapshot of the user's library (favorites / history / playlists).
 *
 * Pattern used by large music apps:
 * 1. Cold start → paint UI from last snapshot immediately (0 network).
 * 2. Background → refresh from API and rewrite snapshot.
 * 3. Mutations → optimistic UI + write-through snapshot.
 */
class LibraryDiskCache(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val gson = Gson()

    fun load(userId: String?): Snapshot? {
        val key = keyFor(userId) ?: return null
        val raw = prefs.getString(key, null)?.trim().orEmpty()
        if (raw.isBlank()) return null
        return runCatching { gson.fromJson(raw, Snapshot::class.java) }
            .onFailure {
                Log.w(TAG, "load library snapshot failed", it)
                prefs.edit().remove(key).apply()
            }
            .getOrNull()
            ?.sanitize()
    }

    fun save(userId: String?, snapshot: Snapshot) {
        val key = keyFor(userId) ?: return
        runCatching {
            prefs.edit()
                .putString(key, gson.toJson(snapshot.sanitize()))
                .apply()
        }.onFailure { Log.w(TAG, "save library snapshot failed", it) }
    }

    fun clear(userId: String?) {
        val key = keyFor(userId) ?: return
        prefs.edit().remove(key).apply()
    }

    private fun keyFor(userId: String?): String? {
        val id = userId?.trim().orEmpty()
        if (id.isBlank()) return null
        return "$KEY_PREFIX$id"
    }

    data class Snapshot(
        @SerializedName("favorites") val favorites: List<SongDto>? = emptyList(),
        @SerializedName("history") val history: List<SongDto>? = emptyList(),
        @SerializedName("playlists") val playlists: List<PlaylistDto>? = emptyList(),
        @SerializedName("savedAtMs") val savedAtMs: Long = 0L
    ) {
        fun sanitize(): Snapshot = copy(
            favorites = favorites.orEmpty().mapNotNull { it.sanitizeOrNull() },
            history = history.orEmpty().mapNotNull { it.sanitizeOrNull() },
            playlists = playlists.orEmpty().mapNotNull { it.sanitizeOrNull() },
            savedAtMs = savedAtMs.coerceAtLeast(0L)
        )

        fun toBootstrap(): MusicLibraryBootstrap = MusicLibraryBootstrap(
            favorites = favorites.orEmpty().mapNotNull { it.sanitizeOrNull()?.toSong() },
            history = history.orEmpty().mapNotNull { it.sanitizeOrNull()?.toSong() },
            playlists = playlists.orEmpty().mapNotNull { it.sanitizeOrNull()?.toPlaylist() },
            savedAtMs = savedAtMs.coerceAtLeast(0L)
        )

        companion object {
            fun from(
                favorites: List<Song>,
                history: List<Song>,
                playlists: List<UserPlaylist>
            ): Snapshot = Snapshot(
                favorites = favorites.map(SongDto::from),
                history = history.map(SongDto::from),
                playlists = playlists.map(PlaylistDto::from),
                savedAtMs = System.currentTimeMillis()
            )
        }
    }

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

    data class PlaylistDto(
        @SerializedName("id") val id: String? = null,
        @SerializedName("name") val name: String? = null,
        @SerializedName("description") val description: String? = null,
        @SerializedName("coverUrl") val coverUrl: String? = null,
        @SerializedName("source") val source: String? = null,
        @SerializedName("sourceId") val sourceId: String? = null,
        @SerializedName("sourceUrl") val sourceUrl: String? = null,
        @SerializedName("creatorName") val creatorName: String? = null,
        @SerializedName("trackCount") val trackCount: Int = 0,
        @SerializedName("isPublic") val isPublic: Boolean = false,
        @SerializedName("createdAt") val createdAt: String? = null,
        @SerializedName("updatedAt") val updatedAt: String? = null
    ) {
        fun sanitizeOrNull(): PlaylistDto? {
            val safeId = id?.trim().orEmpty()
            if (safeId.isBlank()) return null
            return copy(
                id = safeId,
                name = name?.trim().orEmpty().ifBlank { "歌单" },
                trackCount = trackCount.coerceAtLeast(0)
            )
        }

        fun toPlaylist(): UserPlaylist = UserPlaylist(
            id = id.orEmpty(),
            name = name.orEmpty().ifBlank { "歌单" },
            description = description,
            coverUrl = coverUrl,
            source = source,
            sourceId = sourceId,
            sourceUrl = sourceUrl,
            creatorName = creatorName,
            trackCount = trackCount.coerceAtLeast(0),
            isPublic = isPublic,
            createdAt = createdAt,
            updatedAt = updatedAt
        )

        companion object {
            fun from(playlist: UserPlaylist): PlaylistDto = PlaylistDto(
                id = playlist.id,
                name = playlist.name,
                description = playlist.description,
                coverUrl = playlist.coverUrl,
                source = playlist.source,
                sourceId = playlist.sourceId,
                sourceUrl = playlist.sourceUrl,
                creatorName = playlist.creatorName,
                trackCount = playlist.trackCount,
                isPublic = playlist.isPublic,
                createdAt = playlist.createdAt,
                updatedAt = playlist.updatedAt
            )
        }
    }

    private companion object {
        private const val TAG = "LibraryDiskCache"
        private const val PREFS_NAME = "library_disk_cache_v1"
        private const val KEY_PREFIX = "snap|"
    }
}
