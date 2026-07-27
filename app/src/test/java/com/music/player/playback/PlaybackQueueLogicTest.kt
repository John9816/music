package com.music.player.playback

import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackQueueLogicTest {

    private fun song(id: String) = Song(
        id = id,
        name = id,
        artists = listOf(Artist("", "a")),
        album = Album("", "al", ""),
        duration = 1L
    )

    @Test
    fun upcomingFromListKeepsOrderAfterCurrent() {
        val list = listOf(song("1"), song("2"), song("3"), song("4"))
        val upcoming = PlaybackQueueLogic.upcomingFromList(list, song("2"), PlaybackMode.REPEAT_ALL)
        assertEquals(listOf("3", "4"), upcoming.map { it.id })
    }

    @Test
    fun enqueueNextPutsSongFirst() {
        val q = listOf(song("a"), song("b"))
        val next = PlaybackQueueLogic.enqueueNext(q, song("x"))
        assertEquals(listOf("x", "a", "b"), next.map { it.id })
    }

    @Test
    fun enqueueDedupesAndAppends() {
        val q = listOf(song("a"), song("b"))
        val next = PlaybackQueueLogic.enqueue(q, song("a"))
        assertEquals(listOf("b", "a"), next.map { it.id })
    }

    @Test
    fun takeNextSequential() {
        val pick = PlaybackQueueLogic.takeNext(listOf(song("1"), song("2")), PlaybackMode.REPEAT_ALL)
        assertEquals("1", pick.song?.id)
        assertEquals(listOf("2"), pick.remainingQueue.map { it.id })
    }

    @Test
    fun rebuildLoopRotatesPastCurrent() {
        val history = listOf(song("1"), song("2"))
        val result = PlaybackQueueLogic.rebuildLoopQueue(history, song("3"), PlaybackMode.REPEAT_ALL)
        requireNotNull(result)
        assertEquals("1", result.first.id)
        assertEquals(listOf("2"), result.second.map { it.id })
    }

    @Test
    fun rebuildLoopSingleTrackReturnsNull() {
        assertNull(PlaybackQueueLogic.rebuildLoopQueue(emptyList(), song("1"), PlaybackMode.REPEAT_ALL))
    }

    @Test
    fun shuffleUpcomingContainsAllExceptCurrent() {
        val list = listOf(song("1"), song("2"), song("3"))
        val upcoming = PlaybackQueueLogic.upcomingFromList(list, song("2"), PlaybackMode.SHUFFLE)
        assertEquals(2, upcoming.size)
        assertTrue(upcoming.none { it.id == "2" })
    }
}
