package com.music.player.data.repository

import com.music.player.data.api.RetrofitClient
import com.music.player.data.model.Album
import com.music.player.data.model.NewestAlbum

class AlbumRepository {

    private val api = RetrofitClient.musicApi

    suspend fun getNewestAlbums(device: String = "mobile"): Result<List<NewestAlbum>> {
        return try {
            val response = api.getNewestAlbums(
                timestamp = System.currentTimeMillis(),
                device = device
            )
            if (!response.isSuccessful || response.body()?.code != 200) {
                return Result.failure(Exception("获取最新专辑失败"))
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

            Result.success(albums)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}

