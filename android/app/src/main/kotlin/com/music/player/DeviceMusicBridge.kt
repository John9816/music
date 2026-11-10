package com.music.player

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Audio-only MediaStore index; device files are never copied or deleted. */
class DeviceMusicBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val methods = MethodChannel(messenger, "duckmusic/device_music")
    private val events = EventChannel(messenger, "duckmusic/device_music_changes")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var permissionResult: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null
    private var observing = false
    @Volatile private var disposed = false
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { sink?.success(null) }
    }
    private val permission: String
        get() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
        else Manifest.permission.READ_EXTERNAL_STORAGE
    private fun granted() = Build.VERSION.SDK_INT < 23 ||
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    init {
        methods.setMethodCallHandler { call, result ->
            if (call.method != "scan") { result.notImplemented(); return@setMethodCallHandler }
            if (granted()) query(result)
            else if (call.argument<Boolean>("requestPermission") == true && Build.VERSION.SDK_INT >= 23) {
                if (permissionResult != null) result.error("BUSY", "音乐授权正在进行", null)
                else {
                    permissionResult = result
                    activity.requestPermissions(arrayOf(permission), PERMISSION_REQUEST)
                }
            } else result.success(mapOf("granted" to false, "tracks" to emptyList<Any>()))
        }
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                sink = eventSink
                observeIfPermitted()
            }
            override fun onCancel(arguments: Any?) { sink = null; stopObserving() }
        })
    }

    private fun observeIfPermitted() {
        if (!observing && sink != null && granted()) {
            activity.contentResolver.registerContentObserver(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, true, observer)
            observing = true
        }
    }
    private fun stopObserving() {
        if (observing) activity.contentResolver.unregisterContentObserver(observer)
        observing = false
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val result = permissionResult
        permissionResult = null
        if (result != null) {
            if (granted()) query(result)
            else result.success(mapOf("granted" to false, "tracks" to emptyList<Any>()))
        }
        return true
    }

    private fun query(result: MethodChannel.Result) {
        observeIfPermitted()
        worker.execute {
            try {
                val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                val columns = arrayOf(MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE,
                    MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM,
                    MediaStore.Audio.Media.DURATION, MediaStore.Audio.Media.SIZE)
                val tracks = ArrayList<Map<String, Any>>()
                // Include audio downloads even when their IS_MUSIC tag is unset.
                val selection = "${MediaStore.Audio.Media.SIZE}>0 AND ${MediaStore.Audio.Media.DURATION}>0"
                activity.contentResolver.query(uri, columns, selection, null,
                    "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC")?.use { cursor ->
                    while (cursor.moveToNext() && !disposed) {
                        tracks.add(mapOf(
                            "uri" to ContentUris.withAppendedId(uri, cursor.getLong(0)).toString(),
                            "title" to (cursor.getString(1) ?: "未知歌曲"),
                            "artist" to (cursor.getString(2) ?: "未知歌手"),
                            "album" to (cursor.getString(3) ?: "本地音乐"),
                            "durationMs" to cursor.getLong(4),
                            "sizeBytes" to cursor.getLong(5)))
                    }
                } ?: throw IllegalStateException("MediaStore query unavailable")
                main.post { if (!disposed) result.success(mapOf("granted" to true, "tracks" to tracks)) }
            } catch (_: SecurityException) {
                main.post { if (!disposed) result.success(mapOf("granted" to false, "tracks" to emptyList<Any>())) }
            } catch (_: Exception) {
                main.post { if (!disposed) result.error("SCAN_FAILED", "无法读取设备音乐", null) }
            }
        }
    }

    fun dispose() {
        disposed = true
        permissionResult?.error("INTERRUPTED", "音乐授权已中断", null)
        permissionResult = null
        stopObserving()
        sink = null
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        worker.shutdownNow()
    }
    companion object { private const val PERMISSION_REQUEST = 7412 }
}
