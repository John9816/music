package com.music.player.data.repository

import org.junit.Assert.assertEquals
import org.junit.Test

class SearchCatalogParserTest {

    @Test
    fun readsArtistsWhenGenericListIsEmpty() {
        val raw = """
            {
              "code": 0,
              "data": {
                "list": [],
                "artists": [
                  {
                    "id": "3684",
                    "source": "netease",
                    "name": "林俊杰",
                    "coverUrl": "https://example.com/artist.jpg",
                    "trackCount": 598
                  }
                ]
              }
            }
        """.trimIndent()

        val artists = parseArtistsFromEnvelope(raw, fallbackSource = "netease")

        assertEquals(1, artists.size)
        assertEquals("林俊杰", artists.single().name)
        assertEquals(598, artists.single().songCount)
        assertEquals("https://example.com/artist.jpg", artists.single().avatarUrl)
    }

    @Test
    fun readsPlaylistsWhenGenericListIsEmpty() {
        val raw = """
            {
              "code": 0,
              "data": {
                "list": [],
                "playlists": [
                  {
                    "id": "7694176632",
                    "source": "netease",
                    "name": "听·林俊杰热门精选",
                    "coverUrl": "https://example.com/playlist.jpg",
                    "trackCount": 40,
                    "playCount": 48685284
                  }
                ]
              }
            }
        """.trimIndent()

        val playlists = parsePlaylistsFromSearchEnvelope(raw, fallbackSource = "netease")

        assertEquals(1, playlists.size)
        assertEquals("听·林俊杰热门精选", playlists.single().name)
        assertEquals(40, playlists.single().trackCount)
        assertEquals(48_685_284L, playlists.single().playCount)
    }
}
