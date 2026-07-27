package com.music.player

import android.app.Application
import com.music.player.data.api.NetworkRuntime
import com.music.player.playback.PlaybackCoordinator
import com.music.player.ui.util.AppShortcuts
import com.music.player.ui.util.LegacyRenderingCompat

class MusicApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        LegacyRenderingCompat.install(this)
        NetworkRuntime.init(this)
        PlaybackCoordinator.init(this)
        AppShortcuts.publish(this)
    }
}
