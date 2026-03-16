package com.music.player.playback

import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.Player

internal class QueueAwarePlayer(player: Player) : ForwardingPlayer(player) {

    // Keep actions visible on the notification card; coordinator decides what to do.
    override fun hasNextMediaItem(): Boolean = true

    override fun hasPreviousMediaItem(): Boolean = true

    override fun isCommandAvailable(command: Int): Boolean {
        return when (command) {
            Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
            Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
            Player.COMMAND_SEEK_TO_NEXT,
            Player.COMMAND_SEEK_TO_PREVIOUS -> true
            else -> super.isCommandAvailable(command)
        }
    }

    override fun seekToNextMediaItem() {
        PlaybackCoordinator.skipNext()
    }

    override fun seekToPreviousMediaItem() {
        PlaybackCoordinator.skipPrevious()
    }

    override fun seekToNext() = seekToNextMediaItem()

    override fun seekToPrevious() = seekToPreviousMediaItem()

    override fun getAvailableCommands(): Player.Commands {
        val builder = super.getAvailableCommands().buildUpon()
        builder.add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
        builder.add(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
        builder.add(Player.COMMAND_SEEK_TO_NEXT)
        builder.add(Player.COMMAND_SEEK_TO_PREVIOUS)
        return builder.build()
    }
}
