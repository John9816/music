package com.music.player.data.api

import retrofit2.Response
import retrofit2.http.GET
import retrofit2.http.Query

interface LyricsApiService {

    @GET("api/wangyi/lyrics")
    suspend fun getLyrics(@Query("id") id: String): Response<LyricsResponse>
}

data class LyricsResponse(
    val code: Int,
    val data: LyricsData?
)

data class LyricsData(
    val lyric: String?
)
