package com.music.player.data.auth

import com.google.gson.annotations.SerializedName
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Query

interface SupabaseMusicApi {

    @GET("rest/v1/liked_songs")
    suspend fun listFavorites(
        @Header("Authorization") token: String,
        @Query("select") select: String = "song_id,source,name,artist,album,cover_url,duration,created_at",
        @Query("user_id") userId: String,
        @Query("order") order: String = "created_at.desc",
        @Query("limit") limit: Int = 200
    ): Response<List<MusicFavoriteRow>>

    @POST("rest/v1/liked_songs")
    suspend fun insertFavorite(
        @Header("Authorization") token: String,
        @Header("Prefer") prefer: String = "return=minimal",
        @Body favorite: MusicFavoriteInsert
    ): Response<Unit>

    @DELETE("rest/v1/liked_songs")
    suspend fun deleteFavorite(
        @Header("Authorization") token: String,
        @Query("user_id") userId: String,
        @Query("song_id") songId: String
    ): Response<Unit>

    // daohangv2 schema: music_history
    @GET("rest/v1/music_history")
    suspend fun listPlayHistory(
        @Header("Authorization") token: String,
        @Query("select") select: String = "song_id,source,name,artist,album,cover_url,duration,played_at",
        @Query("order") order: String = "played_at.desc",
        @Query("limit") limit: Int = 100
    ): Response<List<MusicPlayHistoryRow>>

    @POST("rest/v1/music_history")
    suspend fun insertPlayHistory(
        @Header("Authorization") token: String,
        // Upsert on (user_id, song_id) so repeat plays update played_at.
        @Header("Prefer") prefer: String = "resolution=merge-duplicates,return=minimal",
        @Query("on_conflict") onConflict: String = "user_id,song_id",
        @Body history: MusicPlayHistoryInsert
    ): Response<Unit>

    @DELETE("rest/v1/music_history")
    suspend fun clearPlayHistory(
        @Header("Authorization") token: String,
        @Query("user_id") userId: String
    ): Response<Unit>

    @POST("rest/v1/music_playlists")
    suspend fun insertPlaylist(
        @Header("Authorization") token: String,
        @Header("Prefer") prefer: String = "return=representation",
        @Query("select") select: String = "id,name,description,cover_url,is_public,created_at,updated_at",
        @Body playlist: MusicPlaylistInsert
    ): Response<List<MusicPlaylistRow>>

    @PATCH("rest/v1/music_playlists")
    suspend fun updatePlaylist(
        @Header("Authorization") token: String,
        @Header("Prefer") prefer: String = "return=minimal",
        @Query("id") playlistId: String,
        @Body updates: Map<String, Any?>
    ): Response<Unit>

    @DELETE("rest/v1/music_playlists")
    suspend fun deletePlaylist(
        @Header("Authorization") token: String,
        @Query("id") playlistId: String
    ): Response<Unit>

    @GET("rest/v1/music_playlist_songs")
    suspend fun listPlaylistSongs(
        @Header("Authorization") token: String,
        @Query("playlist_id") playlistId: String,
        @Query("select") select: String = "song_id,song_name,artist_name,album_cover,sort_order,added_at",
        @Query("order") order: String = "sort_order.asc,added_at.desc"
    ): Response<List<MusicPlaylistSongRow>>

    @POST("rest/v1/music_playlist_songs")
    suspend fun insertPlaylistSong(
        @Header("Authorization") token: String,
        @Header("Prefer") prefer: String = "return=minimal",
        @Body song: MusicPlaylistSongInsert
    ): Response<Unit>

    @DELETE("rest/v1/music_playlist_songs")
    suspend fun deletePlaylistSong(
        @Header("Authorization") token: String,
        @Query("playlist_id") playlistId: String,
        @Query("song_id") songId: String
    ): Response<Unit>
}

data class MusicFavoriteRow(
    @SerializedName("song_id") val songId: String,
    @SerializedName("source") val source: String?,
    @SerializedName("name") val songName: String?,
    @SerializedName("artist") val artistName: String?,
    @SerializedName("album") val albumName: String?,
    @SerializedName("cover_url") val albumCover: String?,
    @SerializedName("duration") val duration: Int?,
    @SerializedName("created_at") val createdAt: String?
)

data class MusicFavoriteInsert(
    @SerializedName("user_id") val userId: String,
    @SerializedName("song_id") val songId: String,
    @SerializedName("source") val source: String,
    @SerializedName("name") val songName: String,
    @SerializedName("artist") val artistName: String,
    @SerializedName("album") val albumName: String?,
    @SerializedName("cover_url") val albumCover: String?,
    @SerializedName("duration") val duration: Int?
)

data class MusicPlayHistoryRow(
    @SerializedName("song_id") val songId: String,
    @SerializedName("source") val source: String?,
    @SerializedName("name") val songName: String?,
    @SerializedName("artist") val artistName: String?,
    @SerializedName("album") val albumName: String?,
    @SerializedName("cover_url") val albumCover: String?,
    @SerializedName("duration") val duration: Int?,
    @SerializedName("played_at") val playedAt: String?
)

data class MusicPlayHistoryInsert(
    @SerializedName("user_id") val userId: String,
    @SerializedName("song_id") val songId: String,
    @SerializedName("source") val source: String,
    @SerializedName("name") val songName: String,
    @SerializedName("artist") val artistName: String,
    @SerializedName("album") val albumName: String?,
    @SerializedName("cover_url") val albumCover: String?,
    @SerializedName("duration") val duration: Int?,
    @SerializedName("played_at") val playedAt: String
)

data class MusicPlaylistRow(
    @SerializedName("id") val id: String,
    @SerializedName("name") val name: String,
    @SerializedName("description") val description: String?,
    @SerializedName("cover_url") val coverUrl: String?,
    @SerializedName("is_public") val isPublic: Boolean,
    @SerializedName("created_at") val createdAt: String?,
    @SerializedName("updated_at") val updatedAt: String?
)

data class MusicPlaylistInsert(
    @SerializedName("user_id") val userId: String,
    @SerializedName("name") val name: String,
    @SerializedName("description") val description: String?,
    @SerializedName("cover_url") val coverUrl: String?,
    @SerializedName("is_public") val isPublic: Boolean = false
)

data class MusicPlaylistSongRow(
    @SerializedName("song_id") val songId: Long,
    @SerializedName("song_name") val songName: String,
    @SerializedName("artist_name") val artistName: String,
    @SerializedName("album_cover") val albumCover: String?,
    @SerializedName("sort_order") val sortOrder: Int?,
    @SerializedName("added_at") val addedAt: String?
)

data class MusicPlaylistSongInsert(
    @SerializedName("playlist_id") val playlistId: String,
    @SerializedName("song_id") val songId: Long,
    @SerializedName("song_name") val songName: String,
    @SerializedName("artist_name") val artistName: String,
    @SerializedName("album_cover") val albumCover: String?,
    @SerializedName("sort_order") val sortOrder: Int = 0
)
