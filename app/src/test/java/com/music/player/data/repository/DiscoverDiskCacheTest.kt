package com.music.player.data.repository

import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.NewestAlbum
import com.music.player.data.model.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DiscoverDiskCacheTest {

    @Test
    fun snapshotRoundTripDtoMapping() {
        val daily = listOf(
            Song(
                id = "1",
                name = "Song A",
                artists = listOf(Artist("a1", "Artist")),
                album = Album("al1", "Album", "https://cover"),
                duration = 120_000L,
                source = "netease"
            )
        )
        val albums = listOf(
            NewestAlbum(
                album = Album("al2", "New", "https://n"),
                artistNames = "Foo"
            )
        )
        val snap = DiscoverDiskCache.Snapshot.from("netease", daily, emptyList(), albums)
            .sanitize()

        assertTrue(snap.hasContent())
        assertEquals(1, snap.dailySongs().size)
        assertEquals("Song A", snap.dailySongs().single().name)
        assertEquals("New", snap.newestAlbums().single().album.name)
        assertEquals("Foo", snap.newestAlbums().single().artistNames)
    }

    @Test
    fun freshnessWindow() {
        val now = 1_000_000L
        val fresh = DiscoverDiskCache.Snapshot(
            source = "netease",
            daily = listOf(
                LibraryDiskCache.SongDto(id = "1", name = "A")
            ),
            savedAtMs = now - 60_000L
        ).sanitize()
        assertTrue(fresh.isFresh(now, ttlMs = 5 * 60_000L))
        assertFalse(fresh.isFresh(now, ttlMs = 30_000L))
    }
}
