package com.music.player.update

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.webkit.URLUtil
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import com.music.player.BuildConfig
import com.music.player.R
import java.io.File
import java.security.MessageDigest
import java.util.Locale
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class AppUpdateInstaller(
    private val activity: ComponentActivity
) {

    companion object {
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val PREFS_NAME = "app_update_download"
        private const val KEY_DOWNLOAD_ID = "download_id"
        private const val KEY_DOWNLOAD_FILE = "download_file"
        private const val KEY_PENDING_INSTALL_FILE = "pending_install_file"
        private const val DOWNLOAD_STATUS_POLL_INTERVAL_MS = 1_000L
    }

    private val downloadManager = activity.getSystemService(DownloadManager::class.java)
    private val prefs = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private var receiverRegistered = false
    private var activeDownloadId = -1L
    private var activeDownloadFile: File? = null
    private var pendingInstallFile: File? = null
    private var downloadMonitorJob: Job? = null

    private val installPermissionLauncher =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            val file = pendingInstallFile ?: return@registerForActivityResult
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity.packageManager.canRequestPackageInstalls()) {
                launchInstaller(file)
            } else {
                toast(R.string.update_install_permission_denied)
            }
        }

    private val downloadReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
            val downloadId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
            if (downloadId != prefs.getLong(KEY_DOWNLOAD_ID, -1L)) return
            activeDownloadId = downloadId
            activeDownloadFile = prefs.getString(KEY_DOWNLOAD_FILE, null)?.let(::File)
            handleDownloadComplete(downloadId)
        }
    }

    init {
        registerReceiver()
        restorePendingState()
    }

    fun dispose() {
        downloadMonitorJob?.cancel()
        downloadMonitorJob = null
        if (receiverRegistered) {
            activity.unregisterReceiver(downloadReceiver)
            receiverRegistered = false
        }
    }

    fun resumePendingWork() {
        val downloadId = prefs.getLong(KEY_DOWNLOAD_ID, activeDownloadId)
        if (downloadId != -1L) {
            activeDownloadId = downloadId
            activeDownloadFile = prefs.getString(KEY_DOWNLOAD_FILE, null)?.let(::File)
            if (!resumeDownloadIfFinished(downloadId)) {
                startDownloadMonitor(downloadId)
            }
        }

        val pending = pendingInstallFile
            ?: prefs.getString(KEY_PENDING_INSTALL_FILE, null)
                ?.let(::File)
                ?.takeIf(File::exists)
                ?.also { pendingInstallFile = it }
            ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()
        ) {
            launchInstaller(pending)
        }
    }

    fun downloadAndInstall(downloadUrl: String, versionName: String) {
        val manager = downloadManager
        if (manager == null) {
            toast(R.string.update_download_failed)
            return
        }

        val uri = runCatching { Uri.parse(downloadUrl.trim()) }.getOrNull()
        if (uri == null || uri.toString().isBlank()) {
            toast(R.string.update_no_url)
            return
        }

        val downloadsDir = activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        if (downloadsDir == null) {
            toast(R.string.update_download_failed)
            return
        }

        if (!downloadsDir.exists()) {
            downloadsDir.mkdirs()
        }

        val targetFileName = buildDownloadFileName(uri, versionName)
        val targetFile = File(downloadsDir, targetFileName)

        val previousDownloadId = prefs.getLong(KEY_DOWNLOAD_ID, activeDownloadId)
        if (previousDownloadId != -1L) {
            manager.remove(previousDownloadId)
        }
        if (targetFile.exists()) {
            targetFile.delete()
        }

        val request = DownloadManager.Request(uri)
            .setMimeType(APK_MIME_TYPE)
            .setTitle(activity.getString(R.string.update_title))
            .setDescription(activity.getString(R.string.update_downloading_description, versionName))
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationUri(Uri.fromFile(targetFile))
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)

        activeDownloadFile = targetFile
        activeDownloadId = manager.enqueue(request)
        prefs.edit()
            .putLong(KEY_DOWNLOAD_ID, activeDownloadId)
            .putString(KEY_DOWNLOAD_FILE, targetFile.absolutePath)
            .apply()
        startDownloadMonitor(activeDownloadId)
        toast(R.string.update_start_download)
    }

    private fun handleDownloadComplete(downloadId: Long) {
        val storedDownloadId = prefs.getLong(KEY_DOWNLOAD_ID, -1L)
        if (downloadId != storedDownloadId && downloadId != activeDownloadId) return

        val manager = downloadManager ?: return
        val file = activeDownloadFile
        clearActiveDownload()

        val query = DownloadManager.Query().setFilterById(downloadId)
        val cursor = manager.query(query)
        cursor.use {
            if (it == null || !it.moveToFirst()) {
                toast(R.string.update_download_failed)
                return
            }

            val statusIndex = it.getColumnIndex(DownloadManager.COLUMN_STATUS)
            val status = if (statusIndex >= 0) {
                it.getInt(statusIndex)
            } else {
                DownloadManager.STATUS_FAILED
            }
            if (status != DownloadManager.STATUS_SUCCESSFUL) {
                toast(R.string.update_download_failed)
                return
            }
        }

        if (file == null || !file.exists()) {
            toast(R.string.update_download_failed)
            return
        }

        toast(R.string.update_download_complete)
        installDownloadedApk(file)
    }

    private fun installDownloadedApk(file: File) {
        when (validateDownloadedPackage(file)) {
            PackageValidationResult.Valid -> {
                pendingInstallFile = file
                prefs.edit().putString(KEY_PENDING_INSTALL_FILE, file.absolutePath).apply()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !activity.packageManager.canRequestPackageInstalls()
                ) {
                    toast(R.string.update_install_permission_required)
                    openInstallPermissionSettings()
                    return
                }
                launchInstaller(file)
            }
            PackageValidationResult.InvalidApk -> toast(R.string.update_invalid_apk)
            PackageValidationResult.PackageMismatch -> toast(R.string.update_package_mismatch)
            PackageValidationResult.SignatureMismatch -> toast(R.string.update_signature_mismatch)
        }
    }

    private fun openInstallPermissionSettings() {
        val appSettingsIntent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${activity.packageName}")
        )
        val launched = runCatching {
            installPermissionLauncher.launch(appSettingsIntent)
        }.isSuccess || runCatching {
            installPermissionLauncher.launch(Intent(Settings.ACTION_SECURITY_SETTINGS))
        }.isSuccess
        if (!launched) {
            toast(R.string.update_install_failed)
        }
    }

    private fun launchInstaller(file: File) {
        if (!file.exists()) {
            clearPendingInstall()
            toast(R.string.update_install_failed)
            return
        }

        val apkUri = runCatching {
            FileProvider.getUriForFile(
                activity,
                "${BuildConfig.APPLICATION_ID}.fileprovider",
                file
            )
        }.getOrElse {
            toast(R.string.update_install_failed)
            return
        }
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, APK_MIME_TYPE)
            clipData = ClipData.newRawUri(file.name, apkUri)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        runCatching {
            activity.startActivity(installIntent)
            clearPendingInstall()
        }.onFailure {
            toast(R.string.update_install_failed)
        }
    }

    private fun validateDownloadedPackage(file: File): PackageValidationResult {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }

        val archiveInfo = activity.packageManager.getPackageArchiveInfo(file.absolutePath, flags)
            ?: return PackageValidationResult.InvalidApk
        if (archiveInfo.packageName != activity.packageName) {
            return PackageValidationResult.PackageMismatch
        }

        val installedInfo = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.packageManager.getPackageInfo(
                    activity.packageName,
                    PackageManager.PackageInfoFlags.of(flags.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                activity.packageManager.getPackageInfo(activity.packageName, flags)
            }
        } catch (_: Exception) {
            return PackageValidationResult.InvalidApk
        }

        val archiveSigners = extractSignerDigests(archiveInfo)
        val installedSigners = extractSignerDigests(installedInfo)
        if (archiveSigners.isEmpty() || installedSigners.isEmpty()) {
            return PackageValidationResult.InvalidApk
        }

        return if (archiveSigners.intersect(installedSigners).isNotEmpty()) {
            PackageValidationResult.Valid
        } else {
            PackageValidationResult.SignatureMismatch
        }
    }

    private fun extractSignerDigests(packageInfo: PackageInfo): Set<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = packageInfo.signingInfo ?: return emptySet()
            val signers = if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
            signers.orEmpty().map(::digestSignature).toSet()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.signatures.orEmpty().map(::digestSignature).toSet()
        }
    }

    private fun digestSignature(signature: Signature): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
        return digest.joinToString(separator = "") { byte ->
            String.format(Locale.US, "%02x", byte)
        }
    }

    private fun buildDownloadFileName(uri: Uri, versionName: String): String {
        val guessed = URLUtil.guessFileName(uri.toString(), null, APK_MIME_TYPE)
        val normalized = if (guessed.endsWith(".apk", ignoreCase = true)) {
            guessed
        } else {
            "duck-music-$versionName.apk"
        }
        return normalized.replace(Regex("[^A-Za-z0-9._-]"), "_")
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        ContextCompat.registerReceiver(
            activity,
            downloadReceiver,
            IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE),
            // DownloadManager sends this broadcast from another system process.
            ContextCompat.RECEIVER_EXPORTED
        )
        receiverRegistered = true
    }

    private fun restorePendingState() {
        pendingInstallFile = prefs.getString(KEY_PENDING_INSTALL_FILE, null)
            ?.let(::File)
            ?.takeIf(File::exists)

        activeDownloadId = prefs.getLong(KEY_DOWNLOAD_ID, -1L)
        activeDownloadFile = prefs.getString(KEY_DOWNLOAD_FILE, null)
            ?.let(::File)

        if (activeDownloadId != -1L) {
            if (!resumeDownloadIfFinished(activeDownloadId)) {
                startDownloadMonitor(activeDownloadId)
            }
            return
        }

    }

    private fun resumeDownloadIfFinished(downloadId: Long): Boolean {
        val manager = downloadManager ?: return false
        val cursor = manager.query(DownloadManager.Query().setFilterById(downloadId))
        cursor.use {
            if (it == null || !it.moveToFirst()) {
                clearActiveDownload()
                return true
            }
            val statusIndex = it.getColumnIndex(DownloadManager.COLUMN_STATUS)
            val status = if (statusIndex >= 0) it.getInt(statusIndex) else DownloadManager.STATUS_FAILED
            return when (status) {
                DownloadManager.STATUS_SUCCESSFUL -> {
                    handleDownloadComplete(downloadId)
                    true
                }
                DownloadManager.STATUS_FAILED -> {
                    clearActiveDownload()
                    toast(R.string.update_download_failed)
                    true
                }
                else -> false
            }
        }
    }

    private fun startDownloadMonitor(downloadId: Long) {
        downloadMonitorJob?.cancel()
        downloadMonitorJob = activity.lifecycleScope.launch {
            while (isActive && prefs.getLong(KEY_DOWNLOAD_ID, -1L) == downloadId) {
                if (resumeDownloadIfFinished(downloadId)) {
                    return@launch
                }
                delay(DOWNLOAD_STATUS_POLL_INTERVAL_MS)
            }
        }
    }

    private fun clearActiveDownload() {
        downloadMonitorJob?.cancel()
        downloadMonitorJob = null
        activeDownloadId = -1L
        activeDownloadFile = null
        prefs.edit().remove(KEY_DOWNLOAD_ID).remove(KEY_DOWNLOAD_FILE).apply()
    }

    private fun clearPendingInstall() {
        pendingInstallFile = null
        prefs.edit().remove(KEY_PENDING_INSTALL_FILE).apply()
    }

    private fun toast(messageRes: Int) {
        Toast.makeText(activity, messageRes, Toast.LENGTH_SHORT).show()
    }
}

private sealed interface PackageValidationResult {
    data object Valid : PackageValidationResult
    data object InvalidApk : PackageValidationResult
    data object PackageMismatch : PackageValidationResult
    data object SignatureMismatch : PackageValidationResult
}
