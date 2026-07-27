package com.music.player.playback

import android.content.Context
import android.media.audiofx.Equalizer
import android.util.Log
import com.music.player.data.settings.AppSettings

/**
 * Lightweight system [Equalizer] bridge with named presets.
 * Session is rebound whenever ExoPlayer attaches with a new audio session id.
 */
object AudioEqualizerController {

    private const val TAG = "AudioEqualizer"

    enum class Preset(val storageValue: String, val gainsDb: FloatArray) {
        OFF("off", floatArrayOf()),
        FLAT("flat", floatArrayOf(0f, 0f, 0f, 0f, 0f)),
        POP("pop", floatArrayOf(-1.5f, 2.5f, 3.5f, 1.5f, -1f)),
        ROCK("rock", floatArrayOf(4f, 2.5f, -1.5f, 2f, 4.5f)),
        JAZZ("jazz", floatArrayOf(3f, 1.5f, -1f, 1.5f, 3f)),
        CLASSICAL("classical", floatArrayOf(3.5f, 2f, -1.5f, 2.5f, 3f)),
        BASS_BOOST("bass", floatArrayOf(6f, 4f, 1f, 0f, -1f)),
        TREBLE_BOOST("treble", floatArrayOf(-1.5f, 0f, 1.5f, 3.5f, 5.5f));

        companion object {
            fun fromStorage(value: String?): Preset =
                entries.firstOrNull { it.storageValue == value } ?: OFF
        }
    }

    @Volatile
    private var equalizer: Equalizer? = null

    @Volatile
    private var sessionId: Int = 0

    fun attachSession(context: Context, audioSessionId: Int) {
        if (audioSessionId == 0) return
        if (sessionId == audioSessionId && equalizer != null) {
            applyPreset(AppSettings.equalizerPreset(context))
            return
        }
        release()
        sessionId = audioSessionId
        runCatching {
            equalizer = Equalizer(0, audioSessionId).also { it.enabled = true }
            applyPreset(AppSettings.equalizerPreset(context))
        }.onFailure {
            Log.w(TAG, "equalizer attach failed session=$audioSessionId", it)
            equalizer = null
        }
    }

    fun applyPreset(preset: Preset) {
        val eq = equalizer ?: return
        if (preset == Preset.OFF || preset.gainsDb.isEmpty()) {
            runCatching { eq.enabled = false }
            return
        }
        runCatching {
            eq.enabled = true
            val bands = eq.numberOfBands.toInt().coerceAtLeast(1)
            val range = eq.bandLevelRange
            val min = range[0].toInt()
            val max = range[1].toInt()
            for (i in 0 until bands) {
                val gainIndex = (i * preset.gainsDb.size) / bands
                val gainDb = preset.gainsDb.getOrElse(gainIndex) { 0f }
                // millibels
                val level = (gainDb * 100f).toInt().coerceIn(min, max)
                eq.setBandLevel(i.toShort(), level.toShort())
            }
        }.onFailure {
            Log.w(TAG, "apply preset ${preset.storageValue} failed", it)
        }
    }

    fun setPreset(context: Context, preset: Preset) {
        AppSettings.setEqualizerPreset(context, preset)
        applyPreset(preset)
    }

    fun release() {
        runCatching { equalizer?.release() }
        equalizer = null
        sessionId = 0
    }
}
