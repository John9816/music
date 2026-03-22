package com.music.player.data.repository

import com.music.player.data.api.RetrofitClient
import com.music.player.data.common.RequestCoalescer
import com.music.player.data.common.TimedMemoryCache
import com.music.player.data.model.Album
import com.music.player.data.model.NewestAlbum

class AlbumRepository {

    private val api = RetrofitClient.musicApi

    private companion object {
        private const val NEWEST_ALBUMS_TTL_MS = 10 * 60 * 1000L
        private val newestAlbumsCache = TimedMemoryCache<String, List<NewestAlbum>>()
        private val newestAlbumRequests = RequestCoalescer<String, Result<List<NewestAlbum>>>()
    }

    suspend fun getNewestAlbums(
        device: String = "mobile",
        forceRefresh: Boolean = false
    ): Result<List<NewestAlbum>> {
        val cacheKey = "newest_albums|$device"
        if (!forceRefresh) {
            newestAlbumsCache.get(cacheKey, NEWEST_ALBUMS_TTL_MS)?.let { return Result.success(it) }
        }

        return newestAlbumRequests.run(cacheKey) {
            if (!forceRefresh) {
                newestAlbumsCache.get(cacheKey, NEWEST_ALBUMS_TTL_MS)?.let { return@run Result.success(it) }
            }

            try {
                val response = api.getNewestAlbums(
                    timestamp = if (forceRefresh) System.currentTimeMillis() else null,
                    device = device
                )
                if (!response.isSuccessful || response.body()?.code != 200) {
                    return@run Result.failure(Exception("获取最新专辑失败"))
                }

                val albums = response.body()
                    ?.albums
                    .orEmpty()
                    .mapNotNull { item ->
                        val id = item.id?.toString().orEmpty()
                        val name = item.name?.trim().orEmpty()
                        val picUrl = (item.picUrl ?: item.blurPicUrl).orEmpty().trim()
                        if (id.isBlank() || name.isBlank()) return@mapNotNull null

                        val artists = item.artists
                            ?.mapNotNull { it.name?.trim() }
                            ?.filter { it.isNotBlank() }
                            ?.takeIf { it.isNotEmpty() }
                            ?.joinToString(", ")
                            ?: item.artist?.name?.trim().orEmpty()

                        NewestAlbum(
                            album = Album(
                                id = id,
                                name = name,
                                picUrl = picUrl
                            ),
                            artistNames = artists
                        )
                    }

                newestAlbumsCache.put(cacheKey, albums)
                Result.success(albums)
            } catch (e: Exception) {
                Result.failure(e)
            }
        }
    }
}
