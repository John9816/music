package com.music.player

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min

/** Playback-session FFT only. No AudioRecord, microphone samples or file output. */
class AudioSpectrumBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "duckmusic/audio_spectrum")
    private val events = EventChannel(messenger, "duckmusic/audio_spectrum/frames")
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var visualizer: Visualizer? = null
    private var pendingStart: StartRequest? = null
    private var activeRequestId: Long? = null
    private var latestRequestId = 0L
    private var permissionRequestInFlight = false
    private var resumed = false
    private var disposed = false
    @Volatile private var captureGeneration = 0L

    private data class StartRequest(
        val sessionId: Int,
        val requestId: Long,
        val result: MethodChannel.Result,
    )

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call, result)
            "stop" -> {
                val id = call.argument<Number>("requestId")?.toLong() ?: latestRequestId
                if (id >= latestRequestId) {
                    latestRequestId = id
                    cancelPending()
                    releaseCapture()
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("requestId")?.toLong() ?: 0L
        if (disposed || id < latestRequestId) {
            reply(result, "idle")
            return
        }
        latestRequestId = id
        cancelPending()
        releaseCapture()
        val sessionId = call.argument<Number>("sessionId")?.toInt() ?: 0
        // Session zero captures the output mix and must never be used here.
        if (sessionId <= 0) {
            reply(result, "unavailable", "当前音频会话尚未就绪")
            return
        }
        val request = StartRequest(sessionId, id, result)
        if (!hasPermission()) {
            if (call.argument<Boolean>("requestPermission") != true) {
                reply(result, "permissionRequired", "启用频谱需要读取播放音频的权限")
                return
            }
            pendingStart = request
            if (!permissionRequestInFlight) {
                try {
                    permissionRequestInFlight = true
                    activity.requestPermissions(
                        arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST_CODE,
                    )
                } catch (_: Exception) {
                    permissionRequestInFlight = false
                    pendingStart = null
                    reply(result, "permissionRequired", "无法请求音频频谱权限")
                }
            }
            return
        }
        if (!resumed) {
            pendingStart = request
            return
        }
        attach(request)
    }

    private fun attach(request: StartRequest) {
        if (disposed || request.requestId != latestRequestId || !resumed) {
            reply(request.result, "idle")
            return
        }
        try {
            val created = Visualizer(request.sessionId)
            visualizer = created
            val range = Visualizer.getCaptureSizeRange()
            check(created.setCaptureSize(1024.coerceIn(range[0], range[1])) == Visualizer.SUCCESS)
            val generation = ++captureGeneration
            val queued = AtomicBoolean(false)
            var lastFrameTime = 0L
            val listener = object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(v: Visualizer, data: ByteArray, rate: Int) = Unit

                override fun onFftDataCapture(v: Visualizer, fft: ByteArray, samplingRate: Int) {
                    if (generation != captureGeneration) return
                    val now = SystemClock.elapsedRealtime()
                    if (now - lastFrameTime < FRAME_INTERVAL_MS || !queued.compareAndSet(false, true)) return
                    lastFrameTime = now
                    val bands = AudioSpectrumFft.bands(fft, samplingRate)
                    // At most one delivery waits on the platform thread. Raw FFT
                    // bytes never cross the bridge, only 32 normalized doubles.
                    mainHandler.post {
                        queued.set(false)
                        if (generation == captureGeneration && !disposed) {
                            sink?.success(mapOf("requestId" to request.requestId, "bands" to bands))
                        }
                    }
                }
            }
            check(created.setDataCaptureListener(
                listener, min(25_000, Visualizer.getMaxCaptureRate()), false, true,
            ) == Visualizer.SUCCESS)
            check(created.setEnabled(true) == Visualizer.SUCCESS)
            activeRequestId = request.requestId
            reply(request.result, "active")
        } catch (_: SecurityException) {
            releaseCapture()
            reply(request.result, "permissionRequired", "需要授权后才能读取播放音频频谱")
        } catch (_: RuntimeException) {
            releaseCapture()
            reply(request.result, "unavailable", "当前设备或音频输出不支持频谱采集")
        } catch (_: LinkageError) {
            releaseCapture()
            reply(request.result, "unavailable", "当前设备未提供音频频谱组件")
        }
    }

    private fun hasPermission(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
        activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        permissionRequestInFlight = false
        val request = pendingStart ?: return true
        if (!hasPermission()) {
            pendingStart = null
            reply(request.result, "permissionRequired", "未获得音频权限，可再次点击启用频谱")
        } else if (resumed) {
            pendingStart = null
            attach(request)
        }
        // Permission dialogs pause the activity. Complete after onResume if needed.
        return true
    }

    fun onResume() {
        resumed = true
        val request = pendingStart ?: return
        if (hasPermission() && !permissionRequestInFlight) {
            pendingStart = null
            attach(request)
        }
    }

    fun onPause() {
        resumed = false
        val id = activeRequestId
        releaseCapture()
        if (id != null) sink?.success(mapOf("requestId" to id, "status" to "idle"))
    }

    fun onStop() {
        cancelPending()
        releaseCapture()
    }

    private fun cancelPending() {
        val request = pendingStart
        pendingStart = null
        if (request != null) reply(request.result, "idle")
    }

    private fun releaseCapture() {
        ++captureGeneration
        activeRequestId = null
        val previous = visualizer
        visualizer = null
        try {
            previous?.setEnabled(false)
            previous?.setDataCaptureListener(null, 0, false, false)
        } catch (_: RuntimeException) {
            // Session may already have been removed by ExoPlayer.
        } finally {
            try {
                previous?.release()
            } catch (_: RuntimeException) {
                // Best effort when Android's effect implementation has died.
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        // Flutter subscribes after start succeeds; onPause may have released
        // capture before this listener arrived. Publish that current state.
        if (pendingStart == null) {
            events.success(mapOf(
                "requestId" to latestRequestId,
                "status" to if (activeRequestId != null) "active" else "idle",
            ))
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        cancelPending()
        releaseCapture()
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        cancelPending()
        releaseCapture()
        sink = null
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        mainHandler.removeCallbacksAndMessages(null)
    }

    private fun reply(result: MethodChannel.Result, status: String, message: String = "") {
        try {
            result.success(mapOf("status" to status, "message" to message))
        } catch (_: RuntimeException) {
            // Activity or Flutter engine may disappear during a permission prompt.
        }
    }

    companion object {
        private const val PERMISSION_REQUEST_CODE = 7512
        // Requested capture rate is 25 Hz. Leave scheduling jitter tolerance
        // instead of discarding alternating callbacks that arrive at 39 ms.
        private const val FRAME_INTERVAL_MS = 33L
    }
}

/** Android FFT bytes are signed real/imaginary pairs; sampling rate is in mHz. */
internal object AudioSpectrumFft {
    fun bands(fft: ByteArray, samplingRateMilliHz: Int): List<Double> {
        val output = DoubleArray(32)
        if (fft.size < 4 || fft.size % 2 != 0 || samplingRateMilliHz <= 0) return output.toList()
        val sampleRate = samplingRateMilliHz / 1000.0
        val maxHz = min(20_000.0, sampleRate / 2)
        val minHz = 40.0
        if (maxHz <= minHz) return output.toList()
        val logRange = ln(maxHz / minHz)
        // FFT byte 0 is DC, byte 1 is Nyquist. Neither is a complex pair.
        for (bin in 1 until fft.size / 2) {
            val frequency = bin * sampleRate / fft.size
            if (frequency < minHz || frequency > maxHz) continue
            val band = floor(ln(frequency / minHz) / logRange * output.size)
                .toInt().coerceIn(0, output.lastIndex)
            val magnitude = hypot(fft[2 * bin].toDouble(), fft[2 * bin + 1].toDouble())
            // A fixed dB range preserves silence and actual signal dynamics;
            // frame-by-frame normalization would invent motion in quiet audio.
            val level = if (magnitude <= 0) 0.0 else
                ((20 * log10(magnitude / 128.0) + 48) / 48).coerceIn(0.0, 1.0)
            output[band] = max(output[band], level)
        }
        return output.toList()
    }
}
