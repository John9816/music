package com.music.player.ui.util

import android.content.Context
import com.music.player.data.repository.AlbumRepository
import com.music.player.data.repository.MusicRepository
import com.music.player.data.settings.MusicSourcePreferences
import com.music.player.playback.PlaybackCoordinator
import com.music.player.ui.viewmodel.MusicViewModel

/**
 * Single path for switching 红源/绿源/橙源 from Settings, Search chips, or Main resume.
 * Always clears repository / URL caches; optionally pins [MusicViewModel] when available.
 */
object MusicSourceSwitcher {

    fun apply(
        context: Context,
        source: MusicSourcePreferences.Source,
        musicViewModel: MusicViewModel? = null
    ) {
        MusicSourcePreferences.setActiveSource(context, source)
        MusicRepository.clearCaches()
        AlbumRepository.clearCaches()
        PlaybackCoordinator.clearResolvedUrlCache()
        musicViewModel?.forceActiveSource(source.storageValue)
        musicViewModel?.clearSourceDependentState()
    }
}
