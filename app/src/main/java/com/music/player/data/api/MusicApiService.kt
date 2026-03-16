package com.music.player.data.api

import retrofit2.Response
import com.google.gson.annotations.SerializedName
import retrofit2.http.GET
import retrofit2.http.Query

interface MusicApiService {

    @GET("api/recommend/songs")
    suspend fun getDailyRecommend(): Response<DailyRecommendResponse>

    @GET("api/toplist")
    suspend fun getTopLists(): Response<TopListResponse>

    @GET("api/top/playlist")
    suspend fun getTopPlaylists(
        @Query("cat") category: String? = null,
        @Query("limit") limit: Int = 42,
        @Query("offset") offset: Int = 0,
        @Query("timestamp") timestamp: Long? = null,
        @Query("device") device: String? = null
    ): Response<PlaylistResponse>

    @GET("api/playlist/catlist")
    suspend fun getPlaylistCatlist(
        @Query("timestamp") timestamp: Long? = null,
        @Query("device") device: String? = null
    ): Response<PlaylistCatlistResponse>

    @GET("api/playlist/detail")
    suspend fun getPlaylistDetail(@Query("id") id: String): Response<PlaylistDetailResponse>

    @GET("api/cloudsearch")
    suspend fun searchSongs(
        @Query("keywords") keywords: String,
        @Query("type") type: Int = 1,
        @Query("limit") limit: Int = 30,
        @Query("offset") offset: Int = 0
    ): Response<SearchResponse>

    @GET("api/song/detail")
    suspend fun getSongDetail(@Query("ids") ids: String): Response<SongDetailResponse>

    @GET("api/lyric")
    suspend fun getLyric(
        @Query("id") id: String,
        @Query("timestamp") timestamp: Long? = null
    ): Response<LyricResponse>

    @GET("api/personalized/newsong")
    suspend fun getWeeklyHotNewSongs(
        @Query("limit") limit: Int = 10,
        @Query("timestamp") timestamp: Long? = null,
        @Query("device") device: String? = null
    ): Response<WeeklyHotNewSongResponse>

    @GET("api/album/newest")
    suspend fun getNewestAlbums(
        @Query("timestamp") timestamp: Long? = null,
        @Query("device") device: String? = null
    ): Response<NewestAlbumResponse>
}

data class DailyRecommendResponse(
    val code: Int,
    val data: DailyRecommendData?
)

data class DailyRecommendData(
    val dailySongs: List<SongData>?
)

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
