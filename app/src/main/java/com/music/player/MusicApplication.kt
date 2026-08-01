package com.music.player

import android.app.Application
import android.os.Handler
import android.os.Looper
import com.music.player.data.api.NetworkRuntime
import com.music.player.data.api.RetrofitClient
import com.music.player.data.repository.MusicRepository
import com.music.player.playback.PlaybackCoordinator
import com.music.player.ui.util.AppShortcuts
import com.music.player.ui.util.LegacyRenderingCompat

class MusicApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Critical path only: rendering + network + playback. Defer launcher shortcuts.
        LegacyRenderingCompat.install(this)
        NetworkRuntime.init(this)
        MusicRepository.setApplicationContext(this)
        PlaybackCoordinator.init(this)
        // Pre-open a pooled TLS connection so the first tap does not pay DNS + TLS on the play path.
        RetrofitClient.warmUpMusicHost()
        Handler(Looper.getMainLooper()).post {
            AppShortcuts.publish(this@MusicApplication)
        }
    }
}
