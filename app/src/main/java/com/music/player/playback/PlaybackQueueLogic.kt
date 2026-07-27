package com.music.player.playback

import com.music.player.data.model.Song

/**
 * Pure queue helpers extracted from [PlaybackCoordinator] for testability.
 * No Android dependencies — only list transforms.
 */
object PlaybackQueueLogic {

    fun upcomingFromList(
        songs: List<Song>,
        current: Song,
        mode: PlaybackMode
    ): List<Song> {
        val distinct = songs.distinctBy { it.id }
        val index = distinct.indexOfFirst { it.id == current.id }
        return if (mode == PlaybackMode.SHUFFLE) {
            distinct.filterNot { it.id == current.id }.shuffled()
        } else if (index >= 0) {
            distinct.drop(index + 1).filterNot { it.id == current.id }
        } else {
            distinct.filterNot { it.id == current.id }
        }
    }

    fun enqueue(queue: List<Song>, song: Song): List<Song> =
        queue.filterNot { it.id == song.id } + song

    fun enqueueNext(queue: List<Song>, song: Song): List<Song> =
        listOf(song) + queue.filterNot { it.id == song.id }

    data class NextPick(val song: Song?, val remainingQueue: List<Song>)

    fun takeNext(queue: List<Song>, mode: PlaybackMode): NextPick {
        if (queue.isEmpty()) return NextPick(null, emptyList())
        return if (mode == PlaybackMode.SHUFFLE) {
            val pick = queue.random()
            NextPick(pick, queue.filterNot { it.id == pick.id })
        } else {
            NextPick(queue.first(), queue.drop(1))
        }
    }

    /**
     * Rebuild cycle from history + current when up-next is empty.
     * @return next song to play and remaining queue, or null if only one track.
     */
    fun rebuildLoopQueue(
        history: List<Song>,
        current: Song,
        mode: PlaybackMode
    ): Pair<Song, List<Song>>? {
        val cycle = (history + current).distinctBy { it.id }
        if (cycle.size <= 1) return null
        val ordered = if (mode == PlaybackMode.SHUFFLE) {
            cycle.shuffled()
        } else {
            val idx = cycle.indexOfFirst { it.id == current.id }.coerceAtLeast(0)
            cycle.drop(idx + 1) + cycle.take(idx)
        }
        val head = ordered.firstOrNull() ?: return null
        return head to ordered.drop(1)
    }
}
