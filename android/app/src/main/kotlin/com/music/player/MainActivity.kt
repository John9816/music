package com.music.player

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private var pendingApkPath: String? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var audioSpectrumBridge: AudioSpectrumBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioSpectrumBridge?.dispose()
        audioSpectrumBridge = AudioSpectrumBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        val legacyAuthStore = LegacyAuthSessionStore.fromContext(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LEGACY_AUTH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readLegacyAuthSession" -> result.success(legacyAuthStore.read()?.toMap())
                    "clearLegacyAuthSession" -> {
                        legacyAuthStore.clear()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path.isNullOrBlank() || !File(path).isFile) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !packageManager.canRequestPackageInstalls()
                ) {
                    pendingApkPath = path
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success(true)
                    return@setMethodCallHandler
                }
                result.success(openPackageInstaller(path))
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAST_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCast" -> result.success(
                        mapOf(
                            "supported" to false,
                            "connected" to false,
                            "message" to "Android 暂未配置 Google Cast 接收端，请使用外部播放页投屏",
                        ),
                    )
                    "stopCast" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            if (pendingNotificationPermissionResult != null) {
                                result.error("REQUEST_IN_PROGRESS", "通知权限请求正在处理中", null)
                                return@setMethodCallHandler
                            }
                            pendingNotificationPermissionResult = result
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                NOTIFICATION_PERMISSION_REQUEST_CODE,
                            )
                        } else {
                            result.success(true)
                        }
                    }
                    "areNotificationsEnabled" -> {
                        val enabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            getSystemService(NotificationManager::class.java)
                                .areNotificationsEnabled()
                        } else {
                            true
                        }
                        result.success(enabled)
                    }
                    "openNotificationSettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                },
                            )
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (audioSpectrumBridge?.onRequestPermissionsResult(requestCode) == true) return
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST_CODE) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pendingNotificationPermissionResult?.success(granted)
        pendingNotificationPermissionResult = null
    }

    override fun onDestroy() {
        audioSpectrumBridge?.dispose()
        audioSpectrumBridge = null
        // 权限弹窗期间 Activity 可能被系统回收，此时 onRequestPermissionsResult
        // 不会再触发。若不在这里兜底回调，Dart 侧的 await 会永久挂起，
        // 导致通知权限再也不会被请求第二次。
        pendingNotificationPermissionResult?.let { result ->
            val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            try {
                result.success(granted)
            } catch (_: Exception) {
                // 引擎可能已断开，忽略即可。
            }
        }
        pendingNotificationPermissionResult = null
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        audioSpectrumBridge?.onResume()
        val path = pendingApkPath ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
        ) {
            pendingApkPath = null
            openPackageInstaller(path)
        }
    }

    override fun onPause() {
        audioSpectrumBridge?.onPause()
        super.onPause()
    }

    override fun onStop() {
        audioSpectrumBridge?.onStop()
        super.onStop()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        audioSpectrumBridge?.dispose()
        audioSpectrumBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun openPackageInstaller(path: String): Boolean {
        return try {
            val file = File(path)
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.update_file_provider",
                file,
            )
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    companion object {
        private const val UPDATE_CHANNEL = "duckmusic/update"
        private const val CAST_CHANNEL = "com.751152.duckmusic/cast"
        private const val NOTIFICATION_CHANNEL =
            "com.751152.duckmusic/notifications"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 7511
        private const val LEGACY_AUTH_CHANNEL = "duckmusic/legacy_auth_session"
    }
}
