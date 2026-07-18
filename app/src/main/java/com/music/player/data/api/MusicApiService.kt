package com.music.player.data.api

import okhttp3.ResponseBody
import retrofit2.Response
import com.google.gson.annotations.SerializedName
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

data class PlaylistResponse(
    val code: Int,
    val playlists: List<PlaylistData>?
)

data class TopListResponse(
    val code: Int,
    val list: List<PlaylistData>?
)

data class PlaylistCatlistResponse(
    val code: Int,
    val categories: Map<String, String>?,
    val sub: List<PlaylistCategoryData>?,
    val all: PlaylistCategoryData?
)

data class PlaylistCategoryData(
    val name: String?,
    val category: Int?,
    val hot: Boolean?
)

data class PlaylistDetailResponse(
    val code: Int,
    val playlist: PlaylistDetailData?
)

data class PlaylistDetailData(
    val id: Long,
    val name: String,
    val coverImgUrl: String?,
    val description: String?,
    val trackCount: Int,
    val playCount: Long,
    val tracks: List<SongData>?,
    val trackIds: List<TrackIdData>?
)

data class TrackIdData(
    val id: Long
)

data class SearchResponse(
    val code: Int,
    val result: SearchResult?
)

data class SearchResult(
    val songs: List<SongData>?
)

data class SongDetailResponse(
    val code: Int,
    val songs: List<SongData>?
)

data class LyricResponse(
    val code: Int,
    val lrc: LyricData?,
    val tlyric: LyricData?
)

data class LyricData(
    val lyric: String?
)

data class WeeklyHotNewSongResponse(
    val code: Int,
    val result: List<WeeklyHotNewSongItem>?
)

data class WeeklyHotNewSongItem(
    val id: Long?,
    val name: String?,
    val picUrl: String?,
    val song: SongData?
)

data class NewestAlbumResponse(
    val code: Int,
    val albums: List<NewestAlbumItem>?
)

data class NewestAlbumItem(
    val id: Long?,
    val name: String?,
    val picUrl: String?,
    val blurPicUrl: String?,
    val artist: NewestAlbumArtist?,
    val artists: List<NewestAlbumArtist>?
)

data class NewestAlbumArtist(
    val id: Long?,
    val name: String?
)

data class SongData(
    val id: Long,
    val name: String,
    val ar: List<ArtistData>?,
    @SerializedName("artists")
    val artists: List<ArtistData>? = null,
    val al: AlbumData?,
    val dt: Long
)

data class ArtistData(
    val id: Long,
    val name: String
)

data class AlbumData(
    val id: Long,
    val name: String,
    val picUrl: String?
)

data class PlaylistData(
    val id: Long,
    val name: String,
    val coverImgUrl: String?,
    val description: String?,
    val trackCount: Int,
    val playCount: Long
)
