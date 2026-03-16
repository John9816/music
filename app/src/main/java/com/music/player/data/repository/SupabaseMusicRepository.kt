package com.music.player.data.repository

import android.content.Context
import android.content.SharedPreferences
import com.music.player.data.auth.MusicFavoriteInsert
import com.music.player.data.auth.MusicPlayHistoryInsert
import com.music.player.data.auth.MusicPlaylistInsert
import com.music.player.data.auth.MusicPlaylistSongInsert
import com.music.player.data.auth.SupabaseClient
import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.Song
import com.music.player.data.model.UserPlaylist
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class SupabaseMusicRepository(context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences("auth_prefs", Context.MODE_PRIVATE)
    private val authApi = SupabaseClient.authApi
    private val api = SupabaseClient.musicApi

    private fun getToken(): String? = prefs.getString("access_token", null)

    private fun getCachedUserId(): String? = prefs.getString("user_id", null)

    private fun cacheUserId(userId: String) {
        prefs.edit().putString("user_id", userId).apply()
    }

    private suspend fun requireSession(): Pair<String, String> {
        val token = getToken() ?: throw IllegalStateException("未登录")
        val cachedUserId = getCachedUserId()
        if (!cachedUserId.isNullOrBlank()) return token to cachedUserId

        val response = authApi.getUser("Bearer $token")
        val userId = response.body()?.id ?: throw IllegalStateException("获取用户信息失败")
        cacheUserId(userId)
        return token to userId
    }

    suspend fun listFavorites(): Result<List<Song>> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val response = api.listFavorites(
                token = "Bearer $token",
                userId = "eq.$userId"
            )
            if (!response.isSuccessful) throw IllegalStateException("获取收藏失败")
            response.body().orEmpty().map { row -> row.toSong() }
        }
    }

    suspend fun setFavorite(song: Song, isFavorite: Boolean): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            if (isFavorite) {
                val artistName = song.artists.joinToString(", ") { it.name }.ifBlank { "Unknown" }
                val insert = MusicFavoriteInsert(
                    userId = userId,
                    songId = song.id,
                    source = song.source,
                    songName = song.name,
                    artistName = artistName,
                    albumName = song.album.name.takeIf { it.isNotBlank() },
                    albumCover = song.album.picUrl.takeIf { it.isNotBlank() },
                    duration = song.duration.toIntSafely()
                )
                val response = api.insertFavorite("Bearer $token", favorite = insert)
                if (!response.isSuccessful) throw IllegalStateException("收藏失败")
            } else {
                val response = api.deleteFavorite(
                    token = "Bearer $token",
                    userId = "eq.$userId",
                    songId = "eq.${song.id}"
                )
                if (!response.isSuccessful) throw IllegalStateException("取消收藏失败")
            }
        }
    }

    suspend fun listPlayHistory(limit: Int = 100): Result<List<Song>> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, _) = requireSession()
            val response = api.listPlayHistory("Bearer $token", limit = limit)
            if (!response.isSuccessful) throw IllegalStateException("获取播放历史失败")
            response.body().orEmpty().map { row -> row.toSong() }
        }
    }

    suspend fun addPlayHistory(song: Song): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val artistName = song.artists.joinToString(", ") { it.name }.ifBlank { "Unknown" }
            val playedAt = isoUtcNow()
            val insert = MusicPlayHistoryInsert(
                userId = userId,
                songId = song.id,
                source = song.source,
                songName = song.name,
                artistName = artistName,
                albumName = song.album.name.takeIf { it.isNotBlank() },
                albumCover = song.album.picUrl.takeIf { it.isNotBlank() },
                duration = song.duration.toIntSafely(),
                playedAt = playedAt
            )
            val response = api.insertPlayHistory("Bearer $token", history = insert)
            if (!response.isSuccessful) throw IllegalStateException("记录播放历史失败")
        }
    }

    suspend fun clearPlayHistory(): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val response = api.clearPlayHistory("Bearer $token", userId = "eq.$userId")
            if (!response.isSuccessful) throw IllegalStateException("清空播放历史失败")
        }
    }

    suspend fun listUserPlaylists(): Result<List<UserPlaylist>> = withContext(Dispatchers.IO) {
        runCatching {
            requireSession()
            val response = retrofit2.Response.success(emptyList<com.music.player.data.auth.MusicPlaylistRow>())
            if (!response.isSuccessful) throw IllegalStateException("获取我的歌单失败")
            response.body().orEmpty().map { row ->
                UserPlaylist(
                    id = row.id,
                    name = row.name,
                    description = row.description,
                    coverUrl = row.coverUrl,
                    isPublic = row.isPublic,
                    createdAt = row.createdAt,
                    updatedAt = row.updatedAt
                )
            }
        }
    }

    suspend fun createPlaylist(name: String, description: String?): Result<UserPlaylist> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, userId) = requireSession()
            val response = api.insertPlaylist(
                token = "Bearer $token",
                playlist = MusicPlaylistInsert(
                    userId = userId,
                    name = name,
                    description = description?.takeIf { it.isNotBlank() },
                    coverUrl = null,
                    isPublic = false
                )
            )
            if (!response.isSuccessful) throw IllegalStateException("创建歌单失败")
            val row = response.body()?.firstOrNull() ?: throw IllegalStateException("创建歌单失败")
            UserPlaylist(
                id = row.id,
                name = row.name,
                description = row.description,
                coverUrl = row.coverUrl,
                isPublic = row.isPublic,
                createdAt = row.createdAt,
                updatedAt = row.updatedAt
            )
        }
    }

    suspend fun deletePlaylist(playlistId: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, _) = requireSession()
            val response = api.deletePlaylist("Bearer $token", playlistId = "eq.$playlistId")
            if (!response.isSuccessful) throw IllegalStateException("删除歌单失败")
        }
    }

    suspend fun listPlaylistSongs(playlistId: String): Result<List<Song>> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, _) = requireSession()
            val response = api.listPlaylistSongs("Bearer $token", playlistId = "eq.$playlistId")
            if (!response.isSuccessful) throw IllegalStateException("获取歌单歌曲失败")
            response.body().orEmpty().map { row ->
                minimalSong(
                    songId = row.songId,
                    songName = row.songName,
                    artistName = row.artistName,
                    albumCover = row.albumCover
                )
            }
        }
    }

    suspend fun addSongToPlaylist(playlistId: String, song: Song): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, _) = requireSession()
            val songId = song.id.toLongOrNull() ?: throw IllegalArgumentException("无效歌曲 ID")
            val artistName = song.artists.joinToString(", ") { it.name }.ifBlank { "Unknown" }
            val insert = MusicPlaylistSongInsert(
                playlistId = playlistId,
                songId = songId,
                songName = song.name,
                artistName = artistName,
                albumCover = song.album.picUrl.takeIf { it.isNotBlank() }
            )
            val response = api.insertPlaylistSong("Bearer $token", song = insert)
            if (!response.isSuccessful) throw IllegalStateException("添加到歌单失败")
        }
    }

    suspend fun removeSongFromPlaylist(playlistId: String, songId: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val (token, _) = requireSession()
            val id = songId.toLongOrNull() ?: throw IllegalArgumentException("无效歌曲 ID")
            val response = api.deletePlaylistSong(
                token = "Bearer $token",
                playlistId = "eq.$playlistId",
                songId = "eq.$id"
            )
            if (!response.isSuccessful) throw IllegalStateException("从歌单移除失败")
        }
    }

    private fun minimalSong(songId: Long, songName: String, artistName: String, albumCover: String?): Song {
        return Song(
            id = songId.toString(),
            name = songName,
            artists = listOf(Artist(id = "", name = artistName)),
            album = Album(id = "", name = "", picUrl = albumCover.orEmpty()),
            duration = 0L
        )
    }

    private fun com.music.player.data.auth.MusicFavoriteRow.toSong(): Song {
        val artist = artistName.orEmpty().ifBlank { "Unknown" }
        return Song(
            id = songId,
            name = songName.orEmpty().ifBlank { "(unknown)" },
            artists = listOf(Artist(id = "", name = artist)),
            album = Album(
                id = "",
                name = albumName.orEmpty(),
                picUrl = albumCover.orEmpty()
            ),
            duration = (duration ?: 0).toLong(),
            source = source ?: "netease"
        )
    }

    private fun com.music.player.data.auth.MusicPlayHistoryRow.toSong(): Song {
        val artist = artistName.orEmpty().ifBlank { "Unknown" }
        return Song(
            id = songId,
            name = songName.orEmpty().ifBlank { "(unknown)" },
            artists = listOf(Artist(id = "", name = artist)),
            album = Album(
                id = "",
                name = albumName.orEmpty(),
                picUrl = albumCover.orEmpty()
            ),
            duration = (duration ?: 0).toLong(),
            source = source ?: "netease"
        )
    }

    private fun isoUtcNow(): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date())
    }

    private fun Long.toIntSafely(): Int? {
        if (this <= 0L) return null
        return if (this > Int.MAX_VALUE.toLong()) Int.MAX_VALUE else this.toInt()
    }
}
