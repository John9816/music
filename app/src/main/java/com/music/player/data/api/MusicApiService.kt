package com.music.player.data.api

import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Query

interface MusicApiService {

    @GET("api/v1/music/new")
    suspend fun getDailyRecommend(
        @Query("source") source: String = "netease",
        @Query("page") page: Int = 1,
        @Query("pageSize") pageSize: Int = 30
    ): Response<ResponseBody>

    @GET("api/v1/music/toplist")
    suspend fun getTopLists(@Query("source") source: String = "netease"): Response<ResponseBody>

    @GET("api/v1/music/playlist")
    suspend fun getTopPlaylists(
        @Query("source") source: String = "netease",
        @Query("cat") category: String? = null,
        @Query("category") websiteCategory: String? = category,
        @Query("order") order: String? = "hot",
        @Query("page") page: Int = 1,
        @Query("pageSize") pageSize: Int = 20
    ): Response<ResponseBody>

    @GET("api/v1/music/playlist")
    suspend fun getPlaylistCatlist(
        @Query("source") source: String = "netease",
        @Query("page") page: Int = 1,
        @Query("pageSize") pageSize: Int = 1
    ): Response<ResponseBody>

    @GET("api/v1/music/playlist/detail")
    suspend fun getPlaylistDetail(
        @Query("source") source: String = "netease",
        @Query("id") id: String,
        @Query("page") page: Int = 1,
        @Query("pageSize") pageSize: Int = 300
    ): Response<ResponseBody>

    @GET("api/v1/music/toplist/detail")
    suspend fun getTopListDetail(
        @Query("source") source: String = "qq",
        @Query("id") id: String,
        @Query("page") page: Int = 1,
        @Query("pageSize") pageSize: Int = 300
    ): Response<ResponseBody>

    @GET("api/v1/music/search")
    suspend fun searchSongs(
        @Query("source") source: String = "netease",
        @Query("keyword") keyword: String,
        @Query("type") type: String? = null,
        @Query("page") page: Int = 1,
        @Query("pageSize") pageSize: Int = 30
    ): Response<ResponseBody>

    @GET("api/v1/music/search")
    suspend fun getSongDetail(
        @Query("source") source: String = "netease",
        @Query("keyword") ids: String,
        @Query("page") page: Int = 1,
        @Query("pageSize") pageSize: Int = 30
    ): Response<ResponseBody>

    @GET("api/v1/music/lyric")
    suspend fun getLyric(
        @Query("source") source: String = "netease",
        @Query("id") id: String,
        @Query("timestamp") timestamp: Long? = null
    ): Response<ResponseBody>

    @GET("api/v1/music/play")
    suspend fun getSongUrl(
        @Header("Authorization") authorization: String? = null,
        @Query("source") source: String = "netease",
        @Query("id") id: String,
        @Query("quality") level: String = "flac"
    ): Response<ResponseBody>

    @GET("api/v1/music/new")
    suspend fun getWeeklyHotNewSongs(
        @Query("source") source: String = "netease",
        @Query("page") page: Int = 1,
        @Query("pageSize") pageSize: Int = 10
    ): Response<ResponseBody>

    @GET("api/v1/music/new")
    suspend fun getNewestAlbums(
        @Query("source") source: String = "netease",
        @Query("page") page: Int = 1,
        @Query("pageSize") pageSize: Int = 10
    ): Response<ResponseBody>
}
