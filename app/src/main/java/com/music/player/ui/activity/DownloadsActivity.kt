package com.music.player.ui.activity

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.Lifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.Song
import com.music.player.databinding.ActivityDownloadsBinding
import com.music.player.playback.PlaybackCoordinator
import com.music.player.ui.adapter.DownloadedSongAdapter
import com.music.player.ui.util.SongDownloader
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class DownloadsActivity : AppCompatActivity() {

    private lateinit var binding: ActivityDownloadsBinding
    private lateinit var adapter: DownloadedSongAdapter
    private var loadJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityDownloadsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupEdgeToEdge()
        setupToolbar()
        setupRecyclerView()
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                SongDownloader.progress.collect { renderDownloadProgress(it) }
            }
        }
        loadDownloads()
    }

    override fun onResume() {
        super.onResume()
        loadDownloads()
    }

    private fun setupEdgeToEdge() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= 29) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
        val isNightMode = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val controller = WindowInsetsControllerCompat(window, binding.root)
        controller.isAppearanceLightStatusBars = !isNightMode
        controller.isAppearanceLightNavigationBars = !isNightMode
        controller.show(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }

    private fun setupToolbar() {
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_delete_all -> {
                    showDeleteAllConfirmation()
                    true
                }
                else -> false
            }
        }
    }

    private fun setupRecyclerView() {
        adapter = DownloadedSongAdapter(
            onPlay = { download -> playDownload(download) },
            onDelete = { download -> deleteDownload(download) }
        )
        binding.recyclerView.layoutManager = LinearLayoutManager(this)
        binding.recyclerView.adapter = adapter
    }

    private fun loadDownloads() {
        loadJob?.cancel()
        loadJob = lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) { runCatching(::queryDownloads) }
            result.onSuccess(::renderDownloads)
                .onFailure {
                    Toast.makeText(
                        this@DownloadsActivity,
                        R.string.msg_song_download_failed,
                        Toast.LENGTH_SHORT
                    ).show()
                }
        }
    }

    private fun renderDownloads(downloads: List<DownloadInfo>) {
        adapter.submitList(downloads)

        if (downloads.isEmpty()) {
            binding.layoutEmpty.visibility = View.VISIBLE
            binding.recyclerView.visibility = View.GONE
            binding.tvSummary.visibility = View.GONE
        } else {
            binding.layoutEmpty.visibility = View.GONE
            binding.recyclerView.visibility = View.VISIBLE
            binding.tvSummary.visibility = View.VISIBLE

            val totalSize = downloads.sumOf { it.size }
            binding.tvSummary.text = getString(
                R.string.downloads_total_size,
                downloads.size,
                formatSize(totalSize)
            )
        }
    }

    private fun renderDownloadProgress(progress: List<SongDownloader.DownloadProgress>) {
        val active = progress.firstOrNull()
        binding.downloadProgress.visibility = if (active == null) View.GONE else View.VISIBLE
        if (active != null) {
            binding.downloadProgressBar.isIndeterminate = active.totalBytes <= 0L
            binding.downloadProgressBar.progress = active.percent
            binding.tvDownloadProgress.text = if (active.totalBytes > 0L) "${active.percent}%" else "下载中"
        }
    }

    private fun queryDownloads(): List<DownloadInfo> {
        return SongDownloader.downloadDirs(this)
            .flatMap { dir -> dir.listFiles().orEmpty().toList() }
            .filter { file ->
                file.isFile &&
                    !file.name.endsWith(".part", ignoreCase = true) &&
                    file.extension.lowercase() in AUDIO_EXTENSIONS
            }
            .distinctBy { it.absolutePath }
            .sortedByDescending { it.lastModified() }
            .map { file ->
                val rawTitle = file.nameWithoutExtension
                val metadata = readMetadata(file)
                val hasArtist = " - " in rawTitle
                DownloadInfo(
                    id = file.absolutePath.hashCode().toLong(),
                    title = metadata?.get("title")?.asString?.takeIf { it.isNotBlank() }
                        ?: if (hasArtist) rawTitle.substringBeforeLast(" - ") else rawTitle,
                    artist = metadata?.get("artist")?.asString?.takeIf { it.isNotBlank() }
                        ?: if (hasArtist) rawTitle.substringAfterLast(" - ") else "",
                    filePath = file.absolutePath,
                    size = file.length().coerceAtLeast(0L),
                    coverPath = File(file.parentFile, "${file.name}.cover").takeIf { it.isFile }?.absolutePath,
                    lyric = metadata?.get("lyric")?.asString.orEmpty(),
                    duration = metadata?.get("duration")?.asLong ?: 0L
                )
            }
    }

    private fun readMetadata(file: File): JsonObject? = runCatching {
        File(file.parentFile, "${file.name}.json")
            .takeIf { it.isFile }
            ?.let { JsonParser.parseString(it.readText(Charsets.UTF_8)).asJsonObject }
    }.getOrNull()

    override fun onDestroy() {
        loadJob?.cancel()
        super.onDestroy()
    }

    private fun playDownload(download: DownloadInfo) {
        val file = File(download.filePath)
        if (!file.isFile) {
            Toast.makeText(this, R.string.downloads_file_missing, Toast.LENGTH_SHORT).show()
            loadDownloads()
            return
        }

        val localSong = Song(
            id = "local:${file.absolutePath.hashCode()}",
            name = download.title,
            artists = download.artist
                .takeIf { it.isNotBlank() }
                ?.let { listOf(Artist(id = "", name = it)) }
                .orEmpty(),
            album = Album(
                id = "",
                name = getString(R.string.downloads_title),
                picUrl = download.coverPath.orEmpty()
            ),
            duration = download.duration,
            url = Uri.fromFile(file).toString(),
            source = "local",
            lyric = download.lyric.takeIf { it.isNotBlank() }
        )
        PlaybackCoordinator.playStandaloneSong(localSong)
        Toast.makeText(this, getString(R.string.downloads_playing, download.title), Toast.LENGTH_SHORT).show()
    }

    private fun deleteDownload(download: DownloadInfo) {
        MaterialAlertDialogBuilder(this)
            .setTitle(getString(R.string.downloads_delete_confirm, download.title))
            .setPositiveButton(R.string.downloads_delete) { _, _ ->
                val deleted = deleteDownloadFiles(File(download.filePath))
                Toast.makeText(
                    this,
                    if (deleted) getString(R.string.downloads_deleted, download.title)
                    else getString(R.string.downloads_delete_failed, download.title),
                    Toast.LENGTH_SHORT
                ).show()
                loadDownloads()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showDeleteAllConfirmation() {
        val downloads = adapter.currentList
        if (downloads.isEmpty()) return

        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.downloads_delete_all_confirm)
            .setPositiveButton(R.string.downloads_delete) { _, _ ->
                val deletedCount = downloads.count { download ->
                    deleteDownloadFiles(File(download.filePath))
                }
                Toast.makeText(
                    this,
                    getString(R.string.downloads_deleted_all, deletedCount),
                    Toast.LENGTH_SHORT
                ).show()
                loadDownloads()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun formatSize(bytes: Long): String {
        return when {
            bytes >= 1024 * 1024 * 1024 -> String.format("%.1f GB", bytes / (1024.0 * 1024 * 1024))
            bytes >= 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024))
            bytes >= 1024 -> String.format("%.1f KB", bytes / 1024.0)
            else -> "$bytes B"
        }
    }

    private fun deleteDownloadFiles(audioFile: File): Boolean {
        val deletedAudio = runCatching { audioFile.delete() }.getOrDefault(false)
        runCatching { File(audioFile.parentFile, "${audioFile.name}.json").delete() }
        runCatching { File(audioFile.parentFile, "${audioFile.name}.cover").delete() }
        return deletedAudio
    }

    data class DownloadInfo(
        val id: Long,
        val title: String,
        val artist: String,
        val filePath: String,
        val size: Long,
        val coverPath: String?,
        val lyric: String,
        val duration: Long
    )

    private companion object {
        private val AUDIO_EXTENSIONS = setOf("mp3", "flac", "aac", "m4a", "wav", "ogg")
    }
}
