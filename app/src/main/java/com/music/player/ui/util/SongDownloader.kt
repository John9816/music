package com.music.player.ui.util

import android.content.Context
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Environment
import android.util.Log
import android.widget.Toast
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.data.repository.MusicRepository
import com.music.player.data.settings.AppSettings
import com.music.player.ui.viewmodel.MusicViewModel
import java.io.File
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.OkHttpClient
import okhttp3.Request

object SongDownloader {

    private const val TAG = "SongDownloader"
    const val DOWNLOAD_SUBDIR = "DuckMusic"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _progress = MutableStateFlow<List<DownloadProgress>>(emptyList())
    val progress: StateFlow<List<DownloadProgress>> = _progress.asStateFlow()
    private val gson = Gson()
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

    /**
     * Resolve a playable local URI for a catalog song that was previously downloaded.
     * Matches metadata `id` first, then falls back to the download filename pattern.
     */
    fun findLocalAudioFile(context: Context, song: Song): File? {
        val songId = song.id.trim()
        if (songId.isBlank() || songId.startsWith("local:")) return null

        val dirs = downloadDirs(context)
        val byId = dirs.asSequence()
            .flatMap { dir -> dir.listFiles().orEmpty().asSequence() }
            .filter { it.isFile && isAudioFile(it) && it.length() > 0L }
            .firstOrNull { file ->
                readMetadataId(file)?.trim() == songId
            }
        if (byId != null) return byId

        val baseName = buildBaseFileName(song)
        return dirs.asSequence()
            .flatMap { dir -> dir.listFiles().orEmpty().asSequence() }
            .filter { it.isFile && isAudioFile(it) && it.length() > 0L }
            .firstOrNull { it.nameWithoutExtension.equals(baseName, ignoreCase = true) }
    }

    fun localPlaybackUri(context: Context, song: Song): String? {
        val file = findLocalAudioFile(context, song) ?: return null
        return Uri.fromFile(file).toString()
    }

    fun isLocalFileUrl(url: String): Boolean {
        val value = url.trim()
        if (value.isEmpty()) return false
        return value.startsWith("file:", ignoreCase = true) ||
            value.startsWith("/") ||
            value.startsWith("content:", ignoreCase = true)
    }

    fun isPlayableLocalUrl(url: String): Boolean {
        val value = url.trim()
        if (value.isEmpty()) return false
        return when {
            value.startsWith("content:", ignoreCase = true) -> true
            value.startsWith("file:", ignoreCase = true) -> {
                runCatching { File(Uri.parse(value).path ?: return false).isFile }.getOrDefault(false)
            }
            value.startsWith("/") -> File(value).isFile
            else -> false
        }
    }

    private fun isAudioFile(file: File): Boolean {
        if (file.name.endsWith(".part", ignoreCase = true)) return false
        return file.extension.lowercase() in AUDIO_EXTENSIONS
    }

    private fun readMetadataId(audioFile: File): String? = runCatching {
        val metaFile = File(audioFile.parentFile, "${audioFile.name}.json")
        if (!metaFile.isFile) return@runCatching null
        val root = gson.fromJson(metaFile.readText(Charsets.UTF_8), JsonObject::class.java)
        root?.get("id")?.asString
    }.getOrNull()

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
                    val totalBytes = body.contentLength()
                    updateProgress(targetFile, 0L, totalBytes)

                    if (tempFile.exists() && !tempFile.delete()) {
                        throw IllegalStateException("无法清理临时文件")
                    }

                    body.byteStream().use { input ->
                        tempFile.outputStream().use { output ->
                            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                            var downloadedBytes = 0L
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                output.write(buffer, 0, count)
                                downloadedBytes += count
                                updateProgress(targetFile, downloadedBytes, totalBytes)
                            }
                        }
                    }

                    if (targetFile.exists() && !targetFile.delete()) {
                        throw IllegalStateException("无法覆盖旧文件")
                    }
                    if (!tempFile.renameTo(targetFile)) {
                        throw IllegalStateException("无法保存下载文件")
                    }

                    val metadataSong = if (song.lyric.isNullOrBlank()) {
                        song.copy(
                            lyric = runCatching {
                                MusicRepository().getLyrics(song.id, source = song.source).getOrNull()
                            }.getOrNull()
                        )
                    } else song
                    writeMetadata(targetFile, metadataSong)
                    downloadCover(targetFile, metadataSong.album.picUrl)
                    removeProgress(targetFile)

                    targetFile
                }
            }.onSuccess { file ->
                Log.d(TAG, "download success file=${file.absolutePath}")
                toastOnMain(context, context.getString(R.string.msg_song_download_complete, file.name))
            }.onFailure { t ->
                removeProgress(File(targetDir, "${buildBaseFileName(song)}.mp3"))
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

    private fun writeMetadata(file: File, song: Song) {
        val metadata = JsonObject().apply {
            addProperty("id", song.id)
            addProperty("title", song.name)
            addProperty("artist", song.artists.joinToString(", ") { it.name })
            addProperty("album", song.album.name)
            addProperty("coverUrl", song.album.picUrl)
            addProperty("lyric", song.lyric.orEmpty())
            addProperty("duration", song.duration)
            addProperty("source", song.source)
        }
        File(file.parentFile, "${file.name}.json").writeText(gson.toJson(metadata), Charsets.UTF_8)
    }

    private fun downloadCover(audioFile: File, coverUrl: String) {
        val normalized = coverUrl.trim()
        if (normalized.isBlank()) return
        runCatching {
            val request = Request.Builder().url(normalized).header("User-Agent", "DuckMusic/1.0 Android").build()
            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return
                val body = response.body ?: return
                File(audioFile.parentFile, "${audioFile.name}.cover").outputStream().use { output ->
                    body.byteStream().use { input -> input.copyTo(output) }
                }
            }
        }.onFailure { Log.w(TAG, "cover download failed for ${audioFile.name}", it) }
    }

    private fun updateProgress(file: File, downloadedBytes: Long, totalBytes: Long) {
        val item = DownloadProgress(file.absolutePath, downloadedBytes, totalBytes)
        _progress.value = (_progress.value.filterNot { it.filePath == item.filePath } + item)
    }

    private fun removeProgress(file: File) {
        _progress.value = _progress.value.filterNot {
            it.filePath == file.absolutePath || it.filePath.startsWith(file.absolutePath.substringBeforeLast('.', file.absolutePath))
        }
    }

    data class DownloadProgress(
        val filePath: String,
        val downloadedBytes: Long,
        val totalBytes: Long
    ) {
        val percent: Int
            get() = if (totalBytes > 0L) ((downloadedBytes * 100L) / totalBytes).toInt().coerceIn(0, 100) else 0
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

    private val AUDIO_EXTENSIONS = setOf("mp3", "flac", "aac", "m4a", "wav", "ogg")
}
