package com.music.player

import android.app.Application
import com.music.player.data.api.NetworkRuntime

class MusicApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        NetworkRuntime.init(this)
    }
}
