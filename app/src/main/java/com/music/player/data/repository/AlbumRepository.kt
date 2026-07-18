package com.music.player.data.repository

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.music.player.data.api.RetrofitClient
import com.music.player.data.common.RequestCoalescer
import com.music.player.data.common.TimedMemoryCache
import com.music.player.data.model.Album
import com.music.player.data.model.NewestAlbum
import com.music.player.data.settings.MusicSourcePreferences

class AlbumRepository {

    private val api = RetrofitClient.musicApi

    companion object {
        private const val NEWEST_ALBUMS_TTL_MS = 10 * 60 * 1000L
        private val newestAlbumsCache = TimedMemoryCache<String, List<NewestAlbum>>()
        private val newestAlbumRequests = RequestCoalescer<String, Result<List<NewestAlbum>>>()

        fun clearCaches() {
            newestAlbumsCache.clear()
        }
    }

    suspend fun getNewestAlbums(
        device: String = "mobile",
        forceRefresh: Boolean = false
    ): Result<List<NewestAlbum>> {
        val source = MusicSourcePreferences.activeSource().storageValue
        val cacheKey = "newest_albums|$source|$device"
        if (!forceRefresh) {
            newestAlbumsCache.get(cacheKey, NEWEST_ALBUMS_TTL_MS)?.let { return Result.success(it) }
        }

        return newestAlbumRequests.run(cacheKey) {
            if (!forceRefresh) {
                newestAlbumsCache.get(cacheKey, NEWEST_ALBUMS_TTL_MS)?.let { return@run Result.success(it) }
            }

            try {
                val response = api.getNewestAlbums(source = source, pageSize = 12)
                if (!response.isSuccessful) {
                    return@run Result.failure(Exception("获取最新专辑失败"))
                }

                val albums = parseAlbumsFromNewSongs(response.body()?.string().orEmpty())
                newestAlbumsCache.put(cacheKey, albums)
                Result.success(albums)
            } catch (e: Exception) {
                Result.failure(e)
            }
        }
    }
}

private fun parseAlbumsFromNewSongs(raw: String): List<NewestAlbum> {
    if (raw.isBlank()) return emptyList()
    val root = runCatching { JsonParser.parseString(raw).asJsonObject }.getOrNull() ?: return emptyList()
    if (root.int("code", -1) != 0) return emptyList()
    val list = root.obj("data")?.asJsonObjectOrNull()?.obj("list")?.takeIf { it.isJsonArray } ?: return emptyList()
    return list.asJsonArray.mapNotNull { element ->
        val item = element.asJsonObjectOrNull() ?: return@mapNotNull null
        val id = item.str("albumId").ifBlank { item.str("id") }
        val name = item.str("album").ifBlank { item.str("name") }
        if (id.isBlank() || name.isBlank()) return@mapNotNull null
        NewestAlbum(
            album = Album(
                id = id,
                name = name,
                picUrl = item.str("coverUrl")
            ),
            artistNames = item.str("artist")
        )
    }.distinctBy { it.album.id }
}

private fun com.google.gson.JsonElement.asJsonObjectOrNull(): JsonObject? =
    takeIf { it.isJsonObject }?.asJsonObject

private fun JsonObject.obj(name: String): com.google.gson.JsonElement? =
    get(name)?.takeUnless { it.isJsonNull }

private fun JsonObject.str(name: String): String =
    obj(name)?.let { runCatching { it.asString }.getOrNull() }.orEmpty().trim()

private fun JsonObject.int(name: String, default: Int = 0): Int =
    obj(name)?.let { runCatching { it.asInt }.getOrNull() } ?: default
