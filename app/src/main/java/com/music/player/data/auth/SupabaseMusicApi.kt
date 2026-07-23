package com.music.player.data.auth

import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

interface SupabaseMusicApi {

    @GET("api/user/music/favorites")
    suspend fun listFavorites(
        @Header("Authorization") token: String,
        @Query("page") page: Int = 0,
        @Query("size") size: Int = 100
    ): Response<ResponseBody>

    @POST("api/user/music/favorites")
    suspend fun saveFavorite(
        @Header("Authorization") token: String,
        @Body favorite: MusicFavoriteRequest
    ): Response<ResponseBody>

    @DELETE("api/user/music/favorites")
    suspend fun deleteFavorite(
        @Header("Authorization") token: String,
        @Query("source") source: String,
        @Query("songId") songId: String
    ): Response<ResponseBody>

    @GET("api/user/music/history")
    suspend fun listPlayHistory(
        @Header("Authorization") token: String,
        @Query("page") page: Int = 0,
        @Query("size") size: Int = 100
    ): Response<ResponseBody>

    @DELETE("api/user/music/history/{id}")
    suspend fun deletePlayHistoryItem(
        @Header("Authorization") token: String,
        @Path("id") id: Long
    ): Response<ResponseBody>

    @GET("api/user/music/playlists")
    suspend fun listUserPlaylists(
        @Header("Authorization") token: String,
        @Query("page") page: Int = 0,
        @Query("size") size: Int = 100
    ): Response<ResponseBody>

    @POST("api/user/music/playlists")
    suspend fun createPlaylist(
        @Header("Authorization") token: String,
        @Body request: PlaylistCreateRequest
    ): Response<ResponseBody>

    @POST("api/user/music/playlists/import")
    suspend fun importPlaylist(
        @Header("Authorization") token: String,
        @Body request: PlaylistImportRequest
    ): Response<ResponseBody>

    @GET("api/user/music/playlists/{id}")
    suspend fun playlistDetail(
        @Header("Authorization") token: String,
        @Path("id") id: Long,
        @Query("page") page: Int = 0,
        @Query("size") size: Int = 100
    ): Response<ResponseBody>

    @PATCH("api/user/music/playlists/{id}")
    suspend fun renamePlaylist(
        @Header("Authorization") token: String,
        @Path("id") id: Long,
        @Body request: PlaylistRenameRequest
    ): Response<ResponseBody>

    @DELETE("api/user/music/playlists/{id}")
    suspend fun deletePlaylist(
        @Header("Authorization") token: String,
        @Path("id") id: Long
    ): Response<ResponseBody>

    @DELETE("api/user/music/playlists/{id}/items/{itemId}")
    suspend fun deletePlaylistItem(
        @Header("Authorization") token: String,
        @Path("id") id: Long,
        @Path("itemId") itemId: Long
    ): Response<ResponseBody>

    @POST("api/user/music/playlists/{id}/items")
    suspend fun addPlaylistItem(
        @Header("Authorization") token: String,
        @Path("id") id: Long,
        @Body request: PlaylistItemRequest
    ): Response<ResponseBody>
}

data class MusicFavoriteRequest(
    @com.google.gson.annotations.SerializedName("source") val source: String,
    @com.google.gson.annotations.SerializedName("songId") val songId: String,
    @com.google.gson.annotations.SerializedName("name") val name: String,
    @com.google.gson.annotations.SerializedName("artist") val artist: String?,
    @com.google.gson.annotations.SerializedName("album") val album: String?,
    @com.google.gson.annotations.SerializedName("coverUrl") val coverUrl: String?,
    @com.google.gson.annotations.SerializedName("durationSec") val durationSec: Int?
)

data class PlaylistImportRequest(
    @com.google.gson.annotations.SerializedName("url") val url: String
)

data class PlaylistCreateRequest(
    @com.google.gson.annotations.SerializedName("name") val name: String,
    @com.google.gson.annotations.SerializedName("description") val description: String? = null,
    @com.google.gson.annotations.SerializedName("coverUrl") val coverUrl: String? = null
)

data class PlaylistRenameRequest(
    @com.google.gson.annotations.SerializedName("name") val name: String
)

data class PlaylistItemRequest(
    @com.google.gson.annotations.SerializedName("source") val source: String,
    @com.google.gson.annotations.SerializedName("songId") val songId: String,
    @com.google.gson.annotations.SerializedName("name") val name: String,
    @com.google.gson.annotations.SerializedName("artist") val artist: String?,
    @com.google.gson.annotations.SerializedName("album") val album: String?,
    @com.google.gson.annotations.SerializedName("coverUrl") val coverUrl: String?,
    @com.google.gson.annotations.SerializedName("durationSec") val durationSec: Int?
)
