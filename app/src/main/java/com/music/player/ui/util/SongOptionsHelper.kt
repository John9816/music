package com.music.player.ui.util

import android.content.Context
import android.widget.Toast
import androidx.fragment.app.FragmentManager
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.playback.PlaybackCoordinator
import com.music.player.ui.fragment.SongOption
import com.music.player.ui.fragment.SongOptionsBottomSheet
import com.music.player.ui.viewmodel.MusicViewModel

/**
 * Shared song overflow actions so list screens stay consistent.
 */
object SongOptionsHelper {

    data class Config(
        val includePlayNext: Boolean = true,
        val includeAddToQueue: Boolean = true,
        val includeAddToPlaylist: Boolean = true,
        val includeDownload: Boolean = true,
        val isFavorite: Boolean? = null,
        val onToggleFavorite: (() -> Unit)? = null,
        val favoriteLabels: Pair<Int, Int> = R.string.action_unfavorite to R.string.action_favorite,
        val extraLeading: List<SongOption> = emptyList(),
        val extraTrailing: List<SongOption> = emptyList()
    )

    fun show(
        context: Context,
        fragmentManager: FragmentManager,
        song: Song,
        musicViewModel: MusicViewModel,
        onAddToPlaylist: (Song) -> Unit,
        config: Config = Config()
    ) {
        if (PlaybackCoordinator.isRadioSong(song)) {
            Toast.makeText(context, R.string.radio_action_unavailable, Toast.LENGTH_SHORT).show()
            return
        }
        val options = mutableListOf<SongOption>()
        options += config.extraLeading

        val fav = config.isFavorite
        val onFav = config.onToggleFavorite
        if (fav != null && onFav != null) {
            val labelRes = if (fav) config.favoriteLabels.first else config.favoriteLabels.second
            options += SongOption(context.getString(labelRes), onFav)
        }

        if (config.includePlayNext) {
            options += SongOption(context.getString(R.string.action_play_next)) {
                PlaybackCoordinator.enqueueNext(song)
                Toast.makeText(context, R.string.msg_added_to_queue_next, Toast.LENGTH_SHORT).show()
            }
        }
        if (config.includeAddToQueue) {
            options += SongOption(context.getString(R.string.action_add_to_queue)) {
                PlaybackCoordinator.enqueue(song)
                Toast.makeText(context, R.string.msg_added_to_queue, Toast.LENGTH_SHORT).show()
            }
        }
        if (config.includeAddToPlaylist) {
            options += SongOption(context.getString(R.string.action_add_to_playlist)) {
                onAddToPlaylist(song)
            }
        }
        if (config.includeDownload && !song.id.startsWith("local:")) {
            options += SongOption(context.getString(R.string.action_download_song)) {
                SongDownloader.download(context, musicViewModel, song)
            }
        }
        options += config.extraTrailing
        SongOptionsBottomSheet.show(fragmentManager, song, options)
    }

    /** Convenience: standard queue / playlist / download menu. */
    fun showStandard(
        context: Context,
        fragmentManager: FragmentManager,
        song: Song,
        musicViewModel: MusicViewModel,
        onAddToPlaylist: (Song) -> Unit,
        isFavorite: Boolean? = null,
        onToggleFavorite: (() -> Unit)? = null,
        includeDownload: Boolean = true
    ) {
        show(
            context = context,
            fragmentManager = fragmentManager,
            song = song,
            musicViewModel = musicViewModel,
            onAddToPlaylist = onAddToPlaylist,
            config = Config(
                includeDownload = includeDownload,
                isFavorite = isFavorite,
                onToggleFavorite = onToggleFavorite
            )
        )
    }
}
