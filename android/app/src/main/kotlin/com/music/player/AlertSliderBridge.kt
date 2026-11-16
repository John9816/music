package com.music.player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 一加三段式拨杆（Alert Slider）的间接探测。
 *
 * 拨杆本身没有公开 API，但它在 ColorOS / OxygenOS 上最终落到系统铃音模式：
 * 静音 / 振动 / 响铃。这里只监听标准的 RINGER_MODE_CHANGED_ACTION，
 * 不读取任何厂商私有接口，也不主动改变系统状态。
 *
 * 监听是动态的：只在应用进程存活时有效，退出后由系统自动回收。
 */
object AlertSliderBridge {
    const val CHANNEL: String = "com.music.player/alert_slider"

    private var channel: MethodChannel? = null
    private var registered = false
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != AudioManager.RINGER_MODE_CHANGED_ACTION) return
            val value = when (intent.getIntExtra(AudioManager.EXTRA_RINGER_MODE, -1)) {
                AudioManager.RINGER_MODE_SILENT -> "silent"
                AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                AudioManager.RINGER_MODE_NORMAL -> "normal"
                else -> return
            }
            channel?.invokeMethod("onRingerModeChanged", mapOf("mode" to value), null)
        }
    }

    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        val methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "current" -> result.success(currentMode(app))
                "startListening" -> {
                    start(app)
                    result.success(true)
                }
                "stopListening" -> {
                    stop(app)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun currentMode(context: Context): String {
        val manager = context.getSystemService(AudioManager::class.java)
        return when (manager?.ringerMode) {
            AudioManager.RINGER_MODE_SILENT -> "silent"
            AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
            else -> "normal"
        }
    }

    @Suppress("UnspecifiedRegisterReceiverFlag")
    private fun start(context: Context) {
        if (registered) return
        val filter = IntentFilter(AudioManager.RINGER_MODE_CHANGED_ACTION)
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(receiver, filter)
            }
            registered = true
        } catch (_: Exception) {
            // 某些 ROM 会拒绝后台注册；静默降级，不影响播放。
            registered = false
        }
    }

    private fun stop(context: Context) {
        if (!registered) return
        try {
            context.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // 已被系统回收。
        }
        registered = false
    }
}
