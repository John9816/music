package com.music.player.data.api

import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.GET
import retrofit2.http.Query

interface GdStudioApiService {

    @GET("api.php")
    suspend fun getSongUrl(
        @Query("types") types: String = "url",
        @Query("source") source: String = "netease",
        @Query("id") id: String,
        @Query("br") bitRate: Int = 320
    ): Response<ResponseBody>
}
