package com.music.player.update

import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
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
import com.music.player.BuildConfig
import com.music.player.R
import java.io.File
import java.security.MessageDigest
import java.util.Locale

class AppUpdateInstaller(
    private val activity: ComponentActivity
) {

    companion object {
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }

    private val downloadManager = activity.getSystemService(DownloadManager::class.java)
    private var receiverRegistered = false
    private var activeDownloadId = -1L
    private var activeDownloadFile: File? = null
    private var pendingInstallFile: File? = null

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
            if (downloadId != activeDownloadId) return
            handleDownloadComplete(downloadId)
        }
    }

    init {
        registerReceiver()
    }

    fun dispose() {
        if (!receiverRegistered) return
        activity.unregisterReceiver(downloadReceiver)
        receiverRegistered = false
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

        if (activeDownloadId != -1L) {
            manager.remove(activeDownloadId)
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
        toast(R.string.update_start_download)
    }

    private fun handleDownloadComplete(downloadId: Long) {
        val manager = downloadManager ?: return
        val file = activeDownloadFile
        activeDownloadId = -1L
        activeDownloadFile = null

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
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !activity.packageManager.canRequestPackageInstalls()
                ) {
                    toast(R.string.update_install_permission_required)
                    val intent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activity.packageName}")
                    )
                    installPermissionLauncher.launch(intent)
                    return
                }
                launchInstaller(file)
            }
            PackageValidationResult.InvalidApk -> toast(R.string.update_invalid_apk)
            PackageValidationResult.PackageMismatch -> toast(R.string.update_package_mismatch)
            PackageValidationResult.SignatureMismatch -> toast(R.string.update_signature_mismatch)
        }
    }

    private fun launchInstaller(file: File) {
        val apkUri = FileProvider.getUriForFile(
            activity,
            "${BuildConfig.APPLICATION_ID}.fileprovider",
            file
        )
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, APK_MIME_TYPE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        runCatching {
            activity.startActivity(installIntent)
        }.onFailure {
            if (it is ActivityNotFoundException) {
                toast(R.string.update_install_failed)
            } else {
                toast(R.string.update_install_failed)
            }
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

        return if (archiveSigners == installedSigners) {
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
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        receiverRegistered = true
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
