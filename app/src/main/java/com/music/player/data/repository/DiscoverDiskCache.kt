package com.music.player.data.repository

import android.content.Context
import android.util.Log
import com.google.gson.annotations.SerializedName
import com.music.player.data.common.GsonProvider
import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.NewestAlbum
import com.music.player.data.model.Song

/**
 * Disk snapshot of the Discover homepage (daily / weekly / newest albums).
 *
 * Cold start paints UI from the last snapshot (0 network), then soft-refreshes.
 */
class DiscoverDiskCache(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val gson = GsonProvider.gson

    fun load(source: String): Snapshot? {
        val key = keyFor(source) ?: return null
        val raw = prefs.getString(key, null)?.trim().orEmpty()
        if (raw.isBlank()) return null
        return runCatching { gson.fromJson(raw, Snapshot::class.java) }
            .onFailure {
                Log.w(TAG, "load discover snapshot failed", it)
                prefs.edit().remove(key).apply()
            }
            .getOrNull()
            ?.sanitize()
            ?.takeIf { it.hasContent() }
    }

    fun save(source: String, snapshot: Snapshot) {
        val key = keyFor(source) ?: return
        val clean = snapshot.sanitize()
        if (!clean.hasContent()) return
        runCatching {
            prefs.edit()
                .putString(key, gson.toJson(clean))
                .apply()
        }.onFailure { Log.w(TAG, "save discover snapshot failed", it) }
    }

    fun clear(source: String? = null) {
        if (source == null) {
            // Only remove keys with the known prefix — never wipe unrelated SharedPreferences entries.
            val keysToRemove = prefs.all.keys.filter { it.startsWith(KEY_PREFIX) }
            if (keysToRemove.isNotEmpty()) {
                val editor = prefs.edit()
                keysToRemove.forEach { editor.remove(it) }
                editor.apply()
            }
            return
        }
        val key = keyFor(source) ?: return
        prefs.edit().remove(key).apply()
    }

    private fun keyFor(source: String?): String? {
        val id = source?.trim().orEmpty()
        if (id.isBlank()) return null
        return "$KEY_PREFIX$id"
    }

    data class Snapshot(
        @SerializedName("source") val source: String? = null,
        @SerializedName("daily") val daily: List<LibraryDiskCache.SongDto>? = emptyList(),
        @SerializedName("weekly") val weekly: List<LibraryDiskCache.SongDto>? = emptyList(),
        @SerializedName("albums") val albums: List<AlbumDto>? = emptyList(),
        @SerializedName("savedAtMs") val savedAtMs: Long = 0L
    ) {
        fun sanitize(): Snapshot = copy(
            source = source?.trim().orEmpty(),
            daily = daily.orEmpty().mapNotNull { it.sanitizeOrNull() },
            weekly = weekly.orEmpty().mapNotNull { it.sanitizeOrNull() },
            albums = albums.orEmpty().mapNotNull { it.sanitizeOrNull() },
            savedAtMs = savedAtMs.coerceAtLeast(0L)
        )

        fun hasContent(): Boolean =
            daily.orEmpty().isNotEmpty() ||
                weekly.orEmpty().isNotEmpty() ||
                albums.orEmpty().isNotEmpty()

        fun isFresh(nowMs: Long = System.currentTimeMillis(), ttlMs: Long = DEFAULT_FRESH_MS): Boolean =
            hasContent() && savedAtMs > 0L && nowMs - savedAtMs in 0 until ttlMs

        fun dailySongs(): List<Song> = daily.orEmpty().mapNotNull { it.sanitizeOrNull()?.toSong() }
        fun weeklySongs(): List<Song> = weekly.orEmpty().mapNotNull { it.sanitizeOrNull()?.toSong() }
        fun newestAlbums(): List<NewestAlbum> =
            albums.orEmpty().mapNotNull { it.sanitizeOrNull()?.toNewestAlbum() }

        companion object {
            fun from(
                source: String,
                daily: List<Song>,
                weekly: List<Song>,
                albums: List<NewestAlbum>
            ): Snapshot = Snapshot(
                source = source,
                daily = daily.map(LibraryDiskCache.SongDto::from),
                weekly = weekly.map(LibraryDiskCache.SongDto::from),
                albums = albums.map(AlbumDto::from),
                savedAtMs = System.currentTimeMillis()
            )
        }
    }

    data class AlbumDto(
        @SerializedName("id") val id: String? = null,
        @SerializedName("name") val name: String? = null,
        @SerializedName("picUrl") val picUrl: String? = null,
        @SerializedName("artistNames") val artistNames: String? = null
    ) {
        fun sanitizeOrNull(): AlbumDto? {
            val safeId = id?.trim().orEmpty()
            val safeName = name?.trim().orEmpty()
            if (safeId.isBlank() || safeName.isBlank()) return null
            return AlbumDto(
                id = safeId,
                name = safeName,
                picUrl = picUrl.orEmpty(),
                artistNames = artistNames.orEmpty()
            )
        }

        fun toNewestAlbum(): NewestAlbum = NewestAlbum(
            album = Album(
                id = id.orEmpty(),
                name = name.orEmpty(),
                picUrl = picUrl.orEmpty()
            ),
            artistNames = artistNames.orEmpty()
        )

        companion object {
            fun from(item: NewestAlbum): AlbumDto = AlbumDto(
                id = item.album.id,
                name = item.album.name,
                picUrl = item.album.picUrl,
                artistNames = item.artistNames
            )
        }
    }

    companion object {
        private const val TAG = "DiscoverDiskCache"
        private const val PREFS_NAME = "discover_disk_cache_v1"
        private const val KEY_PREFIX = "snap|"

        /** Skip soft network refresh when disk is this fresh. Aligned with MusicRepository.DISCOVER_TTL_MS. */
        const val DEFAULT_FRESH_MS: Long = 3L * 60L * 1000L
    }
}
