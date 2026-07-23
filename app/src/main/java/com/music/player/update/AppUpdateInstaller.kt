package com.music.player.update

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.util.Log
import android.webkit.URLUtil
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import com.music.player.BuildConfig
import com.music.player.R
import java.io.File
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.yield
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * In-app APK download + install handoff.
 *
 * Uses OkHttp (not [android.app.DownloadManager]) so completion stays in-process and we can
 * immediately validate the package and open the system installer — system downloads often
 * finish only in the notification shade with no install prompt.
 */
class AppUpdateInstaller(
    private val activity: ComponentActivity
) {

    companion object {
        private const val TAG = "AppUpdateInstaller"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val PREFS_NAME = "app_update_download"
        private const val KEY_DOWNLOAD_FILE = "download_file"
        private const val KEY_PENDING_INSTALL_FILE = "pending_install_file"
        private const val KEY_DOWNLOAD_VERSION = "download_version"
        private const val KEY_DOWNLOAD_URL = "download_url"
        private const val PROGRESS_TOAST_STEP_PERCENT = 25
    }

    private val prefs = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val httpClient = OkHttpClient.Builder()
        .followRedirects(true)
        .followSslRedirects(true)
        .retryOnConnectionFailure(true)
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .callTimeout(15, TimeUnit.MINUTES)
        .build()

    private var downloadJob: Job? = null
    private var activeCall: okhttp3.Call? = null
    private var pendingInstallFile: File? = null
    private val downloadInFlight = AtomicBoolean(false)

    private val installPermissionLauncher =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            val file = pendingInstallFile ?: return@registerForActivityResult
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                activity.packageManager.canRequestPackageInstalls()
            ) {
                launchInstaller(file)
            } else {
                toast(R.string.update_install_permission_denied)
            }
        }

    init {
        restorePendingState()
    }

    fun dispose() {
        cancelActiveDownload()
    }

    fun resumePendingWork() {
        val pending = pendingInstallFile
            ?: prefs.getString(KEY_PENDING_INSTALL_FILE, null)
                ?.let(::File)
                ?.takeIf(File::exists)
                ?.also { pendingInstallFile = it }
            ?: prefs.getString(KEY_DOWNLOAD_FILE, null)
                ?.let(::File)
                ?.takeIf { it.exists() && it.length() > 0L }
                ?.also { pendingInstallFile = it }

        if (pending != null && pending.exists()) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                activity.packageManager.canRequestPackageInstalls()
            ) {
                installDownloadedApk(pending)
            }
            return
        }

        // Incomplete in-app download: user can re-trigger from the update dialog.
        if (downloadJob?.isActive == true) return
    }

    fun downloadAndInstall(downloadUrl: String, versionName: String) {
        val url = downloadUrl.trim()
        if (url.isBlank()) {
            toast(R.string.update_no_url)
            return
        }
        val uri = runCatching { Uri.parse(url) }.getOrNull()
        if (uri == null || uri.scheme.isNullOrBlank()) {
            toast(R.string.update_no_url)
            return
        }

        if (!downloadInFlight.compareAndSet(false, true)) {
            toast(R.string.update_download_in_progress)
            return
        }

        val downloadsDir = activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        if (downloadsDir == null) {
            downloadInFlight.set(false)
            toast(R.string.update_download_failed)
            return
        }
        if (!downloadsDir.exists()) downloadsDir.mkdirs()

        val targetFile = File(downloadsDir, buildDownloadFileName(uri, versionName))
        val partFile = File(downloadsDir, "${targetFile.name}.part")

        cancelActiveDownload(keepInFlightFlag = true)
        if (partFile.exists()) partFile.delete()
        // Keep a previously finished good APK only if we are re-downloading the same path after failure.

        prefs.edit()
            .putString(KEY_DOWNLOAD_FILE, targetFile.absolutePath)
            .putString(KEY_DOWNLOAD_VERSION, versionName)
            .putString(KEY_DOWNLOAD_URL, url)
            .remove(KEY_PENDING_INSTALL_FILE)
            .apply()
        pendingInstallFile = null

        toast(R.string.update_start_download)

        downloadJob = activity.lifecycleScope.launch {
            try {
                val ok = withContext(Dispatchers.IO) {
                    downloadToFile(url, partFile, targetFile)
                }
                if (!ok) {
                    toast(R.string.update_download_failed)
                    return@launch
                }
                if (!targetFile.exists() || targetFile.length() <= 0L) {
                    toast(R.string.update_download_failed)
                    return@launch
                }
                toast(R.string.update_download_complete)
                installDownloadedApk(targetFile)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "in-app update download failed", e)
                toast(R.string.update_download_failed)
            } finally {
                activeCall = null
                downloadInFlight.set(false)
            }
        }
    }

    private suspend fun downloadToFile(url: String, partFile: File, targetFile: File): Boolean {
        if (partFile.exists()) partFile.delete()
        if (targetFile.exists()) targetFile.delete()

        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "DuckMusic/${BuildConfig.VERSION_NAME}")
            .get()
            .build()
        val call = httpClient.newCall(request)
        activeCall = call

        try {
            call.execute().use { response ->
                if (!response.isSuccessful) {
                    Log.w(TAG, "update HTTP ${response.code} for $url")
                    return false
                }
                val body = response.body ?: return false
                val total = body.contentLength()
                var downloaded = 0L
                var lastToastPercent = -PROGRESS_TOAST_STEP_PERCENT
                var chunks = 0

                partFile.outputStream().use { output ->
                    body.byteStream().use { input ->
                        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                        while (true) {
                            coroutineContext.ensureActive()
                            if (call.isCanceled()) return false
                            val read = input.read(buffer)
                            if (read < 0) break
                            output.write(buffer, 0, read)
                            downloaded += read
                            chunks++
                            // Yield occasionally so Job cancellation is observed promptly.
                            if (chunks % 32 == 0) yield()
                            if (total > 0L) {
                                val percent = ((downloaded * 100L) / total).toInt().coerceIn(0, 100)
                                if (percent >= lastToastPercent + PROGRESS_TOAST_STEP_PERCENT) {
                                    lastToastPercent =
                                        (percent / PROGRESS_TOAST_STEP_PERCENT) * PROGRESS_TOAST_STEP_PERCENT
                                    withContext(Dispatchers.Main.immediate) {
                                        Toast.makeText(
                                            activity,
                                            activity.getString(
                                                R.string.update_download_progress,
                                                lastToastPercent.coerceAtMost(100)
                                            ),
                                            Toast.LENGTH_SHORT
                                        ).show()
                                    }
                                }
                            }
                        }
                        output.flush()
                    }
                }
            }
        } catch (e: CancellationException) {
            partFile.delete()
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "download stream failed", e)
            partFile.delete()
            return false
        }

        if (call.isCanceled() || partFile.length() <= 0L) {
            partFile.delete()
            return false
        }
        if (targetFile.exists()) targetFile.delete()
        if (!partFile.renameTo(targetFile)) {
            partFile.copyTo(targetFile, overwrite = true)
            partFile.delete()
        }
        return targetFile.exists() && targetFile.length() > 0L
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
            Log.w(TAG, "FileProvider uri failed", it)
            toast(R.string.update_install_failed)
            return
        }
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, APK_MIME_TYPE)
            clipData = ClipData.newRawUri(file.name, apkUri)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        runCatching {
            activity.startActivity(installIntent)
            // Keep pending file until install succeeds / next launch; clear soft state only.
            clearPendingInstall()
        }.onFailure {
            Log.w(TAG, "start installer failed", it)
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

        val path = file.absolutePath
        val archiveInfo = activity.packageManager.getPackageArchiveInfo(path, flags)
            ?: return PackageValidationResult.InvalidApk
        // Required on many OEMs: otherwise archive signingInfo / resources stay empty.
        archiveInfo.applicationInfo?.let { appInfo ->
            appInfo.sourceDir = path
            appInfo.publicSourceDir = path
        }
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
        } catch (e: Exception) {
            Log.w(TAG, "failed to read installed package for signature check", e)
            return PackageValidationResult.InvalidApk
        }

        // Prefer current APK contents signers for archives: signingCertificateHistory is often
        // empty for getPackageArchiveInfo, which previously caused a false "invalid APK" toast.
        val archiveSigners = extractSignerDigests(archiveInfo, preferApkContents = true)
        val installedSigners = extractSignerDigests(installedInfo, preferApkContents = false)
        if (archiveSigners.isEmpty()) {
            Log.w(TAG, "archive has no readable signing certs path=$path size=${file.length()}")
            return PackageValidationResult.InvalidApk
        }
        if (installedSigners.isEmpty()) {
            Log.w(TAG, "installed app has no readable signing certs")
            return PackageValidationResult.InvalidApk
        }

        return if (archiveSigners.intersect(installedSigners).isNotEmpty()) {
            PackageValidationResult.Valid
        } else {
            Log.w(
                TAG,
                "signature mismatch archive=$archiveSigners installed=$installedSigners"
            )
            PackageValidationResult.SignatureMismatch
        }
    }

    private fun extractSignerDigests(
        packageInfo: PackageInfo,
        preferApkContents: Boolean
    ): Set<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = packageInfo.signingInfo ?: return emptySet()
            val primary = if (preferApkContents || signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
            val fallback = if (preferApkContents) {
                signingInfo.signingCertificateHistory
            } else {
                signingInfo.apkContentsSigners
            }
            val signers = when {
                !primary.isNullOrEmpty() -> primary
                !fallback.isNullOrEmpty() -> fallback
                else -> emptyArray()
            }
            signers.map(::digestSignature).toSet()
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
            "DuckMusic-v$versionName.apk"
        }
        return normalized.replace(Regex("[^A-Za-z0-9._-]"), "_")
    }

    private fun restorePendingState() {
        pendingInstallFile = prefs.getString(KEY_PENDING_INSTALL_FILE, null)
            ?.let(::File)
            ?.takeIf(File::exists)
        // Drop legacy DownloadManager ids if present.
        if (prefs.contains("download_id")) {
            prefs.edit().remove("download_id").apply()
        }
    }

    private fun cancelActiveDownload(keepInFlightFlag: Boolean = false) {
        downloadJob?.cancel()
        downloadJob = null
        activeCall?.cancel()
        activeCall = null
        if (!keepInFlightFlag) {
            downloadInFlight.set(false)
        }
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
