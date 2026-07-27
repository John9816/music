package com.music.player.ui.activity

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import com.bumptech.glide.Glide
import com.music.player.BuildConfig
import com.music.player.R
import com.music.player.data.settings.AppSettings
import com.music.player.data.video.VideoParseClient
import com.music.player.databinding.ActivityVideoParseBinding
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.util.applyEdgeToEdge
import com.music.player.ui.util.applyNavigationBarInsetPadding
import com.music.player.ui.util.applyStatusBarInsetPadding
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * 聚合短视频解析（抖音 / 快手 / 微博等），接口：yx520 jhjx。
 */
class VideoParseActivity : AppCompatActivity() {

    private lateinit var binding: ActivityVideoParseBinding
    private var parseJob: Job? = null
    private var downloadJob: Job? = null
    private var lastResult: VideoParseClient.ParseResult? = null
    private var downloadedFile: File? = null

    private val downloadClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.prepareActivity(this)
        super.onCreate(savedInstanceState)
        binding = ActivityVideoParseBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val lightBars = (resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) !=
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        applyEdgeToEdge(rootView = binding.root, lightSystemBars = lightBars)
        binding.toolbar.applyStatusBarInsetPadding()
        binding.scroll.applyNavigationBarInsetPadding()

        binding.toolbar.setNavigationOnClickListener { finish() }

        val savedKey = AppSettings.videoParseApiKey(this)
            .ifBlank { BuildConfig.VIDEO_PARSE_API_KEY }
        if (savedKey.isNotBlank()) {
            binding.etApiKey.setText(savedKey)
        }

        intent?.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }?.let {
            binding.etUrl.setText(it)
        }

        binding.btnPaste.setOnClickListener { pasteFromClipboard() }
        binding.btnParse.setOnClickListener { runParse() }
        binding.btnCopy.setOnClickListener { copyMediaUrl() }
        binding.btnOpen.setOnClickListener { openMediaUrl() }
        binding.btnDownload.setOnClickListener { downloadMedia() }
        binding.btnShare.setOnClickListener { shareMedia() }
    }

    override fun onDestroy() {
        parseJob?.cancel()
        downloadJob?.cancel()
        super.onDestroy()
    }

    private fun resolveApiKey(): String {
        val typed = binding.etApiKey.text?.toString()?.trim().orEmpty()
        if (typed.isNotBlank()) {
            AppSettings.setVideoParseApiKey(this, typed)
            return typed
        }
        return AppSettings.videoParseApiKey(this)
            .ifBlank { BuildConfig.VIDEO_PARSE_API_KEY.trim() }
    }

    private fun pasteFromClipboard() {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = cm.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString().orEmpty()
        if (text.isBlank()) {
            Toast.makeText(this, R.string.video_parse_clipboard_empty, Toast.LENGTH_SHORT).show()
            return
        }
        binding.etUrl.setText(text)
        Toast.makeText(this, R.string.video_parse_pasted, Toast.LENGTH_SHORT).show()
    }

    private fun runParse() {
        val share = binding.etUrl.text?.toString().orEmpty()
        val key = resolveApiKey()
        if (key.isBlank()) {
            Toast.makeText(this, R.string.video_parse_need_apikey, Toast.LENGTH_LONG).show()
            binding.etApiKey.requestFocus()
            return
        }
        parseJob?.cancel()
        setLoading(true, getString(R.string.video_parse_loading))
        binding.cardResult.visibility = View.GONE
        parseJob = lifecycleScope.launch {
            val result = VideoParseClient.parse(share, key)
            setLoading(false, null)
            result.onSuccess { parsed ->
                lastResult = parsed
                downloadedFile = null
                bindResult(parsed)
                Toast.makeText(this@VideoParseActivity, R.string.video_parse_success, Toast.LENGTH_SHORT).show()
            }.onFailure { e ->
                lastResult = null
                binding.cardResult.visibility = View.GONE
                setStatus(e.message ?: getString(R.string.video_parse_failed), isError = true)
                Toast.makeText(
                    this@VideoParseActivity,
                    e.message ?: getString(R.string.video_parse_failed),
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }

    private fun bindResult(parsed: VideoParseClient.ParseResult) {
        binding.cardResult.visibility = View.VISIBLE
        val title = parsed.title.ifBlank { getString(R.string.video_parse_untitled) }
        binding.tvTitle.text = title

        val primary = primaryMediaUrl(parsed)
        binding.tvVideoUrl.text = primary ?: getString(R.string.video_parse_no_direct_url)

        val cover = parsed.coverUrl
        if (!cover.isNullOrBlank()) {
            binding.ivCover.visibility = View.VISIBLE
            Glide.with(this).load(cover).centerCrop().into(binding.ivCover)
        } else {
            binding.ivCover.visibility = View.GONE
            Glide.with(this).clear(binding.ivCover)
        }

        val hasUrl = !primary.isNullOrBlank()
        binding.btnCopy.isEnabled = hasUrl
        binding.btnOpen.isEnabled = hasUrl
        binding.btnDownload.isEnabled = hasUrl
        binding.btnShare.isEnabled = hasUrl

        setStatus(
            when {
                !parsed.videoUrl.isNullOrBlank() -> getString(R.string.video_parse_got_video)
                parsed.imageUrls.isNotEmpty() -> getString(
                    R.string.video_parse_got_images,
                    parsed.imageUrls.size
                )
                !parsed.audioUrl.isNullOrBlank() -> getString(R.string.video_parse_got_audio)
                else -> getString(R.string.video_parse_success)
            },
            isError = false
        )
    }

    private fun primaryMediaUrl(parsed: VideoParseClient.ParseResult? = lastResult): String? {
        val p = parsed ?: return null
        return p.videoUrl?.takeIf { it.isNotBlank() }
            ?: p.imageUrls.firstOrNull()
            ?: p.audioUrl?.takeIf { it.isNotBlank() }
    }

    private fun copyMediaUrl() {
        val url = primaryMediaUrl() ?: return
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("media", url))
        Toast.makeText(this, R.string.video_parse_copied, Toast.LENGTH_SHORT).show()
    }

    private fun openMediaUrl() {
        val url = primaryMediaUrl() ?: return
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }.onFailure {
            Toast.makeText(this, R.string.video_parse_open_failed, Toast.LENGTH_SHORT).show()
        }
    }

    private fun shareMedia() {
        val file = downloadedFile
        if (file != null && file.exists()) {
            val uri = FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )
            val share = Intent(Intent.ACTION_SEND).apply {
                type = guessMime(file.name)
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                lastResult?.title?.takeIf { it.isNotBlank() }?.let {
                    putExtra(Intent.EXTRA_SUBJECT, it)
                }
            }
            startActivity(Intent.createChooser(share, getString(R.string.video_parse_share)))
            return
        }
        val url = primaryMediaUrl() ?: return
        val share = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, url)
        }
        startActivity(Intent.createChooser(share, getString(R.string.video_parse_share)))
    }

    private fun downloadMedia() {
        val url = primaryMediaUrl() ?: return
        downloadJob?.cancel()
        setLoading(true, getString(R.string.video_parse_downloading))
        downloadJob = lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { saveUrlToFile(url) }
            }
            setLoading(false, null)
            result.onSuccess { file ->
                downloadedFile = file
                setStatus(getString(R.string.video_parse_downloaded, file.name), isError = false)
                Toast.makeText(
                    this@VideoParseActivity,
                    getString(R.string.video_parse_downloaded, file.absolutePath),
                    Toast.LENGTH_LONG
                ).show()
            }.onFailure { e ->
                setStatus(e.message ?: getString(R.string.video_parse_download_failed), isError = true)
                Toast.makeText(
                    this@VideoParseActivity,
                    e.message ?: getString(R.string.video_parse_download_failed),
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }

    private fun saveUrlToFile(url: String): File {
        val ext = guessExtension(url)
        val dir = getExternalFilesDir(Environment.DIRECTORY_MOVIES)
            ?: File(filesDir, "video_parse").also { it.mkdirs() }
        if (!dir.exists()) dir.mkdirs()
        val name = "vp_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(6)}.$ext"
        val target = File(dir, name)

        val request = Request.Builder()
            .url(url)
            .get()
            .header("User-Agent", "Mozilla/5.0 (Linux; Android 13) MusicPlayer/1.0")
            .header("Referer", runCatching { URL(url).protocol + "://" + URL(url).host }.getOrDefault(""))
            .build()

        downloadClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("下载失败 HTTP ${response.code}")
            val body = response.body ?: error("空响应")
            FileOutputStream(target).use { out ->
                body.byteStream().use { input -> input.copyTo(out) }
            }
        }
        if (!target.exists() || target.length() == 0L) {
            target.delete()
            error("下载文件为空")
        }
        return target
    }

    private fun guessExtension(url: String): String {
        val path = url.substringBefore('?').lowercase()
        return when {
            path.endsWith(".mp4") -> "mp4"
            path.endsWith(".m3u8") -> "m3u8"
            path.endsWith(".flv") -> "flv"
            path.endsWith(".mov") -> "mov"
            path.endsWith(".webm") -> "webm"
            path.endsWith(".mp3") -> "mp3"
            path.endsWith(".m4a") -> "m4a"
            path.endsWith(".jpg") || path.endsWith(".jpeg") -> "jpg"
            path.endsWith(".png") -> "png"
            path.endsWith(".webp") -> "webp"
            lastResult?.imageUrls?.isNotEmpty() == true && lastResult?.videoUrl.isNullOrBlank() -> "jpg"
            lastResult?.audioUrl != null && lastResult?.videoUrl.isNullOrBlank() -> "mp3"
            else -> "mp4"
        }
    }

    private fun guessMime(name: String): String {
        val n = name.lowercase()
        return when {
            n.endsWith(".mp4") || n.endsWith(".mov") || n.endsWith(".webm") || n.endsWith(".flv") -> "video/*"
            n.endsWith(".mp3") || n.endsWith(".m4a") -> "audio/*"
            n.endsWith(".jpg") || n.endsWith(".jpeg") || n.endsWith(".png") || n.endsWith(".webp") -> "image/*"
            else -> "*/*"
        }
    }

    private fun setLoading(loading: Boolean, message: String?) {
        binding.progress.visibility = if (loading) View.VISIBLE else View.GONE
        binding.btnParse.isEnabled = !loading
        binding.btnPaste.isEnabled = !loading
        if (message != null) setStatus(message, isError = false)
    }

    private fun setStatus(text: String, isError: Boolean) {
        binding.tvStatus.visibility = View.VISIBLE
        binding.tvStatus.text = text
        binding.tvStatus.setTextColor(
            if (isError) {
                getColor(android.R.color.holo_red_light)
            } else {
                // Use theme secondary via resources attribute resolution
                val ta = obtainStyledAttributes(intArrayOf(R.attr.textSecondary))
                val color = ta.getColor(0, getColor(android.R.color.darker_gray))
                ta.recycle()
                color
            }
        )
    }

    companion object {
        fun intent(context: Context): Intent = Intent(context, VideoParseActivity::class.java)
    }
}
