package com.music.player.data.api

import retrofit2.Response
import retrofit2.http.GET
import retrofit2.http.Query

interface ChkSzApiService {

    @GET("api/163_music")
    suspend fun getSongUrl(
        @Query("id") id: String,
        @Query("level") level: String = "jymaster"
    ): Response<ChkSzSongUrlResponse>
}

data class ChkSzSongUrlResponse(
    val code: Int?,
    val msg: String?,
    val data: ChkSzSongUrlData?
)

data class ChkSzSongUrlData(
    val id: Long?,
    val url: String?,
    val br: Int?,
    val level: String?,
    val size: Long?,
    val md5: String?,
    val name: String?,
    val artist: String?,
    val album: String?,
    val picUrl: String?
)
