package com.music.player.ui.util

import android.content.Context
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Environment
import android.util.Log
import android.widget.Toast
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.data.settings.AppSettings
import com.music.player.ui.viewmodel.MusicViewModel
import java.io.File
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

object SongDownloader {

    private const val TAG = "SongDownloader"
    const val DOWNLOAD_SUBDIR = "DuckMusic"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val httpClient = OkHttpClient.Builder()
        .followRedirects(true)
        .followSslRedirects(true)
        .retryOnConnectionFailure(true)
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .callTimeout(10, TimeUnit.MINUTES)
        .build()

    fun download(context: Context, viewModel: MusicViewModel, song: Song) {
        val appContext = context.applicationContext
        viewModel.resolveSongUrl(song) { result ->
            result
                .onSuccess { url ->
                    val resolvedUrl = url.trim()
                    if (resolvedUrl.isBlank()) {
                        toast(appContext, appContext.getString(R.string.msg_song_download_unavailable))
                        return@onSuccess
                    }
                    downloadResolvedUrl(appContext, song, resolvedUrl)
                }
                .onFailure {
                    Log.w(TAG, "resolve url failed for ${song.name}", it)
                    toast(appContext, appContext.getString(R.string.msg_song_download_unavailable))
                }
        }
    }

    fun primaryDownloadDir(context: Context): File? {
        return context.applicationContext
            .getExternalFilesDir(Environment.DIRECTORY_MUSIC)
            ?.let { File(it, DOWNLOAD_SUBDIR) }
    }

    fun downloadDirs(context: Context): List<File> {
        val publicMusicRoot = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
        return listOfNotNull(
            primaryDownloadDir(context),
            File(publicMusicRoot, DOWNLOAD_SUBDIR),
            File(publicMusicRoot, "Duck Music")
        )
    }

    private fun downloadResolvedUrl(context: Context, song: Song, url: String) {
        val targetDir = primaryDownloadDir(context)
        if (targetDir == null) {
            toast(context, context.getString(R.string.msg_song_download_failed_reason, "找不到存储目录"))
            return
        }

        if (AppSettings.isDownloadWifiOnly(context) && isActiveNetworkMetered(context)) {
            toast(context, context.getString(R.string.msg_song_download_failed_reason, "当前设置仅允许 Wi-Fi 下载"))
            return
        }

        toast(context, context.getString(R.string.msg_song_download_started))
        scope.launch {
            runCatching {
                if (!targetDir.exists() && !targetDir.mkdirs()) {
                    throw IllegalStateException("无法创建下载目录")
                }

                val request = Request.Builder()
                    .url(url)
                    .header("Accept", "audio/*,*/*")
                    .header("User-Agent", "DuckMusic/1.0 Android")
                    .build()

                httpClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        throw IllegalStateException("服务器返回 ${response.code}")
                    }

                    val body = response.body ?: throw IllegalStateException("响应内容为空")
                    val extension = inferExtension(response.header("Content-Type"), url)
                    val targetFile = File(targetDir, "${buildBaseFileName(song)}.$extension")
                    val tempFile = File(targetDir, "${targetFile.name}.part")

                    if (tempFile.exists() && !tempFile.delete()) {
                        throw IllegalStateException("无法清理临时文件")
                    }

                    body.byteStream().use { input ->
                        tempFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }

                    if (targetFile.exists() && !targetFile.delete()) {
                        throw IllegalStateException("无法覆盖旧文件")
                    }
                    if (!tempFile.renameTo(targetFile)) {
                        throw IllegalStateException("无法保存下载文件")
                    }

                    targetFile
                }
            }.onSuccess { file ->
                Log.d(TAG, "download success file=${file.absolutePath}")
                toastOnMain(context, context.getString(R.string.msg_song_download_complete, file.name))
            }.onFailure { t ->
                Log.e(TAG, "download failed for ${song.name}", t)
                toastOnMain(
                    context,
                    context.getString(
                        R.string.msg_song_download_failed_reason,
                        t.message ?: "未知错误"
                    )
                )
            }
        }
    }

    private fun isActiveNetworkMetered(context: Context): Boolean {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        return manager?.isActiveNetworkMetered == true
    }

    private fun buildBaseFileName(song: Song): String {
        val artistNames = song.artists.joinToString(", ") { it.name }.ifBlank { "Unknown Artist" }
        val rawName = "${song.name} - $artistNames"
        return rawName
            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
            .trim()
            .take(120)
            .ifBlank { song.id }
    }

    private fun inferExtension(contentType: String?, url: String): String {
        val type = contentType.orEmpty().lowercase()
        return when {
            "flac" in type -> "flac"
            "mpeg" in type || "mp3" in type -> "mp3"
            "aac" in type -> "aac"
            "mp4" in type || "m4a" in type -> "m4a"
            "wav" in type -> "wav"
            "ogg" in type -> "ogg"
            else -> Uri.parse(url).lastPathSegment
                ?.substringAfterLast('.', missingDelimiterValue = "")
                ?.lowercase()
                ?.takeIf { it in setOf("mp3", "flac", "aac", "m4a", "wav", "ogg") }
                ?: "mp3"
        }
    }

    private suspend fun toastOnMain(context: Context, message: String) {
        withContext(Dispatchers.Main) { toast(context, message) }
    }

    private fun toast(context: Context, message: String) {
        Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
    }
}
