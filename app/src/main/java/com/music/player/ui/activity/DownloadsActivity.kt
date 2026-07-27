package com.music.player.ui.activity

import android.content.Intent
import android.graphics.Color
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.Menu
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.snackbar.Snackbar
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.music.player.R
import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.Song
import com.music.player.databinding.ActivityDownloadsBinding
import com.music.player.playback.PlaybackCoordinator
import com.music.player.playback.PlaybackMode
import com.music.player.ui.adapter.DownloadedSongAdapter
import com.music.player.ui.fragment.CreatePlaylistBottomSheet
import com.music.player.ui.fragment.SongOption
import com.music.player.ui.fragment.SongOptionsBottomSheet
import com.music.player.ui.util.FileSizeFormatter
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.SongDownloader
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.util.applyEdgeToEdge
import com.music.player.ui.util.applyNavigationBarInsetPadding
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.viewmodel.LibraryViewModel
import java.io.File
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class DownloadsActivity : AppCompatActivity() {

    private lateinit var binding: ActivityDownloadsBinding
    private lateinit var adapter: DownloadedSongAdapter
    private lateinit var libraryViewModel: LibraryViewModel
    private lateinit var insetsController: WindowInsetsControllerCompat

    private var loadJob: Job? = null
    private var allDownloads: List<DownloadInfo> = emptyList()
    private var sortMode: SortMode = SortMode.DATE_DESC
    private var searchQuery: String = ""
    private var selectionMode: Boolean = false
    private val selectedIds = linkedSetOf<String>()
    private var lastScanSignature: Long = Long.MIN_VALUE
    private var hasLoadedOnce: Boolean = false
    private var searchVisible: Boolean = false
    private var pendingDeleteItems: List<DownloadInfo> = emptyList()
    private var pendingDeleteSnackbar: Snackbar? = null
    private var lightSystemBarsDefault: Boolean = true

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.prepareActivity(this)
        super.onCreate(savedInstanceState)
        binding = ActivityDownloadsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        lightSystemBarsDefault = (resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) !=
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        insetsController = applyEdgeToEdge(
            rootView = binding.root,
            lightSystemBars = false
        )
        binding.toolbar.applyStatusBarInsetPadding()
        binding.recyclerView.applyNavigationBarInsetPadding()

        libraryViewModel = ViewModelProvider(this)[LibraryViewModel::class.java]

        setupToolbar()
        setupRecyclerView()
        setupActions()
        setupSearch()
        setupSwipeDelete()
        setupBackHandler()
        observePlaybackAndDownloads()
        loadDownloads(force = true, showLoading = true)
    }

    override fun onResume() {
        super.onResume()
        loadDownloads(force = false, showLoading = false)
        adapter.setCurrentPlayingId(PlaybackCoordinator.currentSong.value?.id)
    }

    override fun onPause() {
        commitPendingDeletes()
        super.onPause()
    }

    override fun onDestroy() {
        commitPendingDeletes()
        loadJob?.cancel()
        super.onDestroy()
    }

    private fun setupBackHandler() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                when {
                    selectionMode -> exitSelectionMode()
                    searchVisible && searchQuery.isNotBlank() -> binding.etSearch.setText("")
                    searchVisible -> toggleSearch(false)
                    else -> {
                        isEnabled = false
                        onBackPressedDispatcher.onBackPressed()
                        isEnabled = true
                    }
                }
            }
        })
    }

    private fun setupToolbar() {
        binding.toolbar.setNavigationOnClickListener {
            when {
                selectionMode -> exitSelectionMode()
                searchVisible -> toggleSearch(false)
                else -> finish()
            }
        }
        binding.toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_search -> {
                    toggleSearch(!searchVisible)
                    true
                }
                R.id.action_sort -> {
                    showSortDialog()
                    true
                }
                R.id.action_select -> {
                    enterSelectionMode()
                    true
                }
                R.id.action_storage_info -> {
                    showStorageInfo()
                    true
                }
                R.id.action_delete_all -> {
                    showDeleteAllConfirmation()
                    true
                }
                R.id.action_select_all -> {
                    toggleSelectAll()
                    true
                }
                R.id.action_delete_selected -> {
                    deleteSelected()
                    true
                }
                else -> false
            }
        }
        binding.appBar.addOnOffsetChangedListener { appBar, verticalOffset ->
            val collapsed = -verticalOffset >= appBar.totalScrollRange - 8
            val light = collapsed && lightSystemBarsDefault
            insetsController.isAppearanceLightStatusBars = light
            val iconTint = if (collapsed) {
                resolveAttrColor(R.attr.textPrimary)
            } else {
                Color.WHITE
            }
            binding.toolbar.navigationIcon?.setTint(iconTint)
            binding.toolbar.setTitleTextColor(
                if (collapsed) resolveAttrColor(R.attr.textPrimary) else Color.WHITE
            )
            for (i in 0 until binding.toolbar.menu.size()) {
                binding.toolbar.menu.getItem(i).icon?.setTint(iconTint)
            }
            if (selectionMode) return@addOnOffsetChangedListener
            binding.toolbar.title = if (collapsed && allDownloads.isNotEmpty()) {
                getString(R.string.downloads_title)
            } else {
                ""
            }
        }
    }

    private fun resolveAttrColor(attr: Int): Int {
        val typed = obtainStyledAttributes(intArrayOf(attr))
        val color = typed.getColor(0, Color.WHITE)
        typed.recycle()
        return color
    }

    private fun setupRecyclerView() {
        adapter = DownloadedSongAdapter(
            onPlay = { playDownload(it) },
            onMore = { showItemOptions(it) },
            onLongPress = { download ->
                if (!selectionMode) {
                    enterSelectionMode(download.songId)
                } else {
                    toggleSelection(download)
                }
            },
            onToggleSelect = { toggleSelection(it) }
        )
        binding.recyclerView.layoutManager = LinearLayoutManager(this)
        binding.recyclerView.adapter = adapter
        binding.recyclerView.setHasFixedSize(true)
        binding.recyclerView.itemAnimator = null
    }

    private fun setupActions() {
        binding.btnPlayAll.bindPressFeedback(PressFeedback.Style.BUTTON)
        binding.btnShuffle.bindPressFeedback(PressFeedback.Style.BUTTON)
        binding.btnPlayAll.setOnClickListener { playAll(shuffle = false) }
        binding.btnShuffle.setOnClickListener { playAll(shuffle = true) }
    }

    private fun setupSearch() {
        binding.etSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) {
                searchQuery = s?.toString().orEmpty().trim()
                publishVisibleList()
            }
        })
    }

    private fun setupSwipeDelete() {
        val helper = ItemTouchHelper(object : ItemTouchHelper.SimpleCallback(0, ItemTouchHelper.LEFT) {
            override fun onMove(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder,
                target: RecyclerView.ViewHolder
            ): Boolean = false

            override fun getSwipeDirs(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder
            ): Int {
                if (selectionMode) return 0
                return super.getSwipeDirs(recyclerView, viewHolder)
            }

            override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) {
                val position = viewHolder.bindingAdapterPosition
                if (position == RecyclerView.NO_POSITION) return
                val item = adapter.currentList.getOrNull(position) ?: return
                scheduleDeleteWithUndo(listOf(item))
            }
        })
        helper.attachToRecyclerView(binding.recyclerView)
    }

    private fun observePlaybackAndDownloads() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch {
                    SongDownloader.progress.collect { renderDownloadProgress(it) }
                }
                launch {
                    SongDownloader.events.collect { event ->
                        when (event) {
                            is SongDownloader.DownloadEvent.Completed ->
                                loadDownloads(force = true, showLoading = false)
                            is SongDownloader.DownloadEvent.Failed -> Unit
                        }
                    }
                }
                launch {
                    PlaybackCoordinator.currentSong.collect { song ->
                        adapter.setCurrentPlayingId(song?.id)
                    }
                }
            }
        }
    }

    private fun loadDownloads(force: Boolean, showLoading: Boolean) {
        loadJob?.cancel()
        loadJob = lifecycleScope.launch {
            if (showLoading && !hasLoadedOnce) {
                binding.loadingIndicator.visibility = View.VISIBLE
            }
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val signature = computeScanSignature()
                    if (!force && signature == lastScanSignature && allDownloads.isNotEmpty()) {
                        return@runCatching allDownloads to signature
                    }
                    val list = queryDownloads()
                    list to signature
                }
            }
            binding.loadingIndicator.visibility = View.GONE
            result.onSuccess { (downloads, signature) ->
                lastScanSignature = signature
                hasLoadedOnce = true
                allDownloads = downloads
                // Drop selections for missing items
                selectedIds.retainAll(downloads.map { it.songId }.toSet())
                updateHeader(downloads)
                publishVisibleList()
            }.onFailure {
                Toast.makeText(
                    this@DownloadsActivity,
                    R.string.msg_song_download_failed,
                    Toast.LENGTH_SHORT
                ).show()
            }
        }
    }

    private fun computeScanSignature(): Long {
        var signature = 0L
        SongDownloader.downloadDirs(this).forEach { dir ->
            if (!dir.isDirectory) return@forEach
            val files = dir.listFiles().orEmpty()
            signature = signature * 31 + files.size
            files.forEach { file ->
                signature = signature * 31 + file.lastModified()
                signature = signature * 31 + file.length()
            }
        }
        return signature
    }

    private fun publishVisibleList() {
        val filtered = filterAndSort(allDownloads)
        val pendingIds = pendingDeleteItems.map { it.songId }.toSet()
        val visible = filtered.filterNot { it.songId in pendingIds }
        adapter.submitList(visible) {
            adapter.setCurrentPlayingId(PlaybackCoordinator.currentSong.value?.id)
            adapter.setSelectionState(selectionMode, selectedIds)
        }

        val emptyAll = allDownloads.isEmpty()
        val emptyVisible = visible.isEmpty()
        binding.actionRow.visibility = if (emptyAll || selectionMode) View.GONE else View.VISIBLE
        binding.btnPlayAll.isEnabled = !emptyVisible
        binding.btnShuffle.isEnabled = !emptyVisible

        if (emptyVisible) {
            binding.layoutEmpty.visibility = View.VISIBLE
            binding.recyclerView.visibility = View.GONE
            if (emptyAll) {
                binding.tvEmptyTitle.setText(R.string.downloads_empty)
                binding.tvEmptyHint.setText(R.string.downloads_empty_hint)
            } else {
                binding.tvEmptyTitle.setText(R.string.downloads_empty_search)
                binding.tvEmptyHint.setText(R.string.downloads_no_results_hint)
            }
        } else {
            binding.layoutEmpty.visibility = View.GONE
            binding.recyclerView.visibility = View.VISIBLE
        }

        binding.tvCountChip.text = getString(R.string.downloads_count_chip, visible.size)
        refreshMenuVisibility()
        if (selectionMode) {
            binding.toolbar.title = getString(R.string.downloads_select_count, selectedIds.size)
        }
    }

    private fun filterAndSort(source: List<DownloadInfo>): List<DownloadInfo> {
        val q = searchQuery.lowercase(Locale.getDefault())
        val filtered = if (q.isBlank()) {
            source
        } else {
            source.filter {
                it.title.lowercase(Locale.getDefault()).contains(q) ||
                    it.artist.lowercase(Locale.getDefault()).contains(q) ||
                    it.format.lowercase(Locale.getDefault()).contains(q)
            }
        }
        return when (sortMode) {
            SortMode.DATE_DESC -> filtered.sortedByDescending { it.lastModified }
            SortMode.NAME -> filtered.sortedBy { it.title.lowercase(Locale.getDefault()) }
            SortMode.ARTIST -> filtered.sortedBy { it.artist.lowercase(Locale.getDefault()) }
            SortMode.SIZE -> filtered.sortedByDescending { it.size }
            SortMode.DURATION -> filtered.sortedByDescending { it.duration }
        }
    }

    private fun updateHeader(downloads: List<DownloadInfo>) {
        val totalSize = downloads.sumOf { it.size }
        binding.tvHeaderSubtitle.text = if (downloads.isEmpty()) {
            getString(R.string.downloads_empty)
        } else {
            getString(
                R.string.downloads_header_subtitle,
                downloads.size,
                FileSizeFormatter.format(totalSize)
            )
        }
        val primary = SongDownloader.primaryDownloadDir(this)?.absolutePath.orEmpty()
        binding.tvStorageHint.text = if (primary.isNotBlank()) {
            getString(R.string.downloads_storage_path, shortenPath(primary))
        } else {
            getString(R.string.downloads_storage_private)
        }

        val cover = downloads.firstOrNull { !it.coverPath.isNullOrBlank() }?.coverPath
        if (cover != null) {
            binding.ivHeaderCover.imageTintList = null
            binding.ivHeaderBackdrop.imageTintList = null
            Glide.with(this)
                .load(File(cover))
                .centerCrop()
                .into(binding.ivHeaderCover)
            Glide.with(this)
                .load(File(cover))
                .centerCrop()
                .into(binding.ivHeaderBackdrop)
        } else {
            Glide.with(this).clear(binding.ivHeaderCover)
            Glide.with(this).clear(binding.ivHeaderBackdrop)
            binding.ivHeaderCover.setImageResource(R.drawable.ic_music_note_24)
            binding.ivHeaderCover.imageTintList =
                android.content.res.ColorStateList.valueOf(resolveAttrColor(R.attr.brandPrimary))
            binding.ivHeaderBackdrop.setImageResource(R.drawable.bg_header_default)
        }
    }

    private fun shortenPath(path: String): String {
        val marker = "/Android/data/"
        val idx = path.indexOf(marker)
        return if (idx >= 0) "…${path.substring(idx)}" else path.takeLast(42)
    }

    private fun renderDownloadProgress(progress: List<SongDownloader.DownloadProgress>) {
        val active = progress.firstOrNull()
        binding.downloadProgress.visibility = if (active == null) View.GONE else View.VISIBLE
        if (active == null) return

        binding.downloadProgressBar.isIndeterminate = active.totalBytes <= 0L
        binding.downloadProgressBar.progress = active.percent

        val label = when {
            progress.size > 1 -> getString(R.string.downloads_progress_queue, progress.size)
            active.songName.isNotBlank() -> active.songName
            else -> getString(R.string.downloads_progress_label)
        }
        binding.tvDownloadLabel.text = label

        binding.tvDownloadProgress.text = when {
            active.totalBytes > 0L -> getString(
                R.string.downloads_progress_bytes,
                FileSizeFormatter.format(active.downloadedBytes),
                FileSizeFormatter.format(active.totalBytes)
            )
            else -> getString(R.string.downloads_progress_label)
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
            .map { file -> buildDownloadInfo(file) }
            .sortedByDescending { it.lastModified }
    }

    private fun buildDownloadInfo(file: File): DownloadInfo {
        val rawTitle = file.nameWithoutExtension
        val metadata = readMetadata(file)
        val hasArtist = " - " in rawTitle
        var title = metadata?.get("title")?.asString?.takeIf { it.isNotBlank() }
            ?: if (hasArtist) rawTitle.substringBeforeLast(" - ") else rawTitle
        var artist = metadata?.get("artist")?.asString?.takeIf { it.isNotBlank() }
            ?: if (hasArtist) rawTitle.substringAfterLast(" - ") else ""
        var duration = metadata?.get("duration")?.asLong ?: 0L
        var coverPath = File(file.parentFile, "${file.name}.cover")
            .takeIf { it.isFile }
            ?.absolutePath
        val remoteId = metadata?.get("id")?.asString?.takeIf {
            it.isNotBlank() && !it.startsWith("local:")
        }.orEmpty()
        val lyric = metadata?.get("lyric")?.asString.orEmpty()

        if (duration <= 0L || coverPath == null) {
            enrichFromEmbedded(file, duration <= 0L, coverPath == null)?.let { embedded ->
                if (duration <= 0L) duration = embedded.duration
                if (coverPath == null) coverPath = embedded.coverPath
            }
        }

        return DownloadInfo(
            id = file.absolutePath.hashCode().toLong(),
            songId = localSongId(file),
            remoteSongId = remoteId,
            title = title,
            artist = artist,
            filePath = file.absolutePath,
            size = file.length().coerceAtLeast(0L),
            coverPath = coverPath,
            lyric = lyric,
            duration = duration,
            format = file.extension.lowercase(),
            lastModified = file.lastModified(),
            storageLabel = storageLabelFor(file)
        )
    }

    private data class EmbeddedMeta(val duration: Long, val coverPath: String?)

    private fun enrichFromEmbedded(
        file: File,
        needDuration: Boolean,
        needCover: Boolean
    ): EmbeddedMeta? = runCatching {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            val duration = if (needDuration) {
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull()
                    ?: 0L
            } else {
                0L
            }
            var coverPath: String? = null
            if (needCover) {
                val picture = retriever.embeddedPicture
                if (picture != null && picture.isNotEmpty()) {
                    val coverFile = File(file.parentFile, "${file.name}.cover")
                    if (!coverFile.exists()) {
                        coverFile.writeBytes(picture)
                    }
                    if (coverFile.isFile) coverPath = coverFile.absolutePath
                }
            }
            EmbeddedMeta(duration, coverPath)
        } finally {
            runCatching { retriever.release() }
        }
    }.getOrNull()

    private fun storageLabelFor(file: File): String {
        val primary = SongDownloader.primaryDownloadDir(this)?.absolutePath.orEmpty()
        return if (primary.isNotBlank() && file.absolutePath.startsWith(primary)) {
            getString(R.string.downloads_storage_private)
        } else {
            getString(R.string.downloads_storage_public)
        }
    }

    private fun readMetadata(file: File): JsonObject? = runCatching {
        File(file.parentFile, "${file.name}.json")
            .takeIf { it.isFile }
            ?.let { JsonParser.parseString(it.readText(Charsets.UTF_8)).asJsonObject }
    }.getOrNull()

    private fun playAll(shuffle: Boolean) {
        val list = adapter.currentList.mapNotNull { toLocalSong(it) }
        if (list.isEmpty()) return
        if (shuffle) {
            PlaybackCoordinator.setPlaybackMode(PlaybackMode.SHUFFLE)
            val start = list.random()
            PlaybackCoordinator.playFromList(list, start)
        } else {
            PlaybackCoordinator.playFromList(list, list.first())
        }
    }

    private fun playDownload(download: DownloadInfo) {
        val file = File(download.filePath)
        if (!file.isFile) {
            Toast.makeText(this, R.string.downloads_file_missing, Toast.LENGTH_SHORT).show()
            loadDownloads(force = true, showLoading = false)
            return
        }

        val all = adapter.currentList.mapNotNull { toLocalSong(it) }
        val target = all.firstOrNull { it.id == download.songId }
            ?: toLocalSong(download)
            ?: return
        if (all.size > 1) {
            PlaybackCoordinator.playFromList(all, target)
        } else {
            PlaybackCoordinator.playStandaloneSong(target)
        }
    }

    private fun localSongId(file: File): String = "local:${file.absolutePath.hashCode()}"

    private fun toLocalSong(download: DownloadInfo): Song? {
        val file = File(download.filePath)
        if (!file.isFile) return null
        return Song(
            id = download.songId,
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
    }

    private fun showItemOptions(download: DownloadInfo) {
        val song = toLocalSong(download) ?: return
        val options = mutableListOf<SongOption>()
        options += SongOption(getString(R.string.downloads_play_next)) {
            PlaybackCoordinator.enqueueNext(song)
            Toast.makeText(this, R.string.msg_added_to_queue_next, Toast.LENGTH_SHORT).show()
        }
        options += SongOption(getString(R.string.downloads_add_queue)) {
            PlaybackCoordinator.enqueue(song)
            Toast.makeText(this, R.string.msg_added_to_queue, Toast.LENGTH_SHORT).show()
        }
        options += SongOption(getString(R.string.action_add_to_playlist)) {
            showAddToPlaylistDialog(song)
        }
        options += SongOption(getString(R.string.downloads_share)) {
            shareDownload(download)
        }
        options += SongOption(getString(R.string.downloads_open_folder)) {
            Toast.makeText(this, download.storageLabel + "\n" + download.filePath, Toast.LENGTH_LONG).show()
        }
        options += SongOption(getString(R.string.downloads_delete)) {
            scheduleDeleteWithUndo(listOf(download))
        }
        SongOptionsBottomSheet().apply {
            songName = download.title
            this.options = options
        }.show(supportFragmentManager, "download_options")
    }

    private fun showAddToPlaylistDialog(song: Song) {
        val playlists = libraryViewModel.playlists.value.orEmpty()
        if (playlists.isEmpty()) {
            MaterialAlertDialogBuilder(this)
                .setTitle(R.string.user_playlist_pick_title)
                .setMessage(R.string.user_playlist_create_first)
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.user_playlist_create_title) { _, _ ->
                    CreatePlaylistBottomSheet().apply {
                        onConfirm = { name, desc -> libraryViewModel.createPlaylist(name, desc) }
                    }.show(supportFragmentManager, "create_playlist")
                }
                .show()
            return
        }

        val names = playlists.map { playlist ->
            val count = resources.getQuantityString(
                R.plurals.user_playlist_track_count,
                playlist.trackCount,
                playlist.trackCount
            )
            "${playlist.name} · $count"
        }.toTypedArray()

        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.user_playlist_pick_title)
            .setItems(names) { _, which ->
                libraryViewModel.addSongToPlaylist(playlists[which].id, song)
            }
            .setNeutralButton(R.string.user_playlist_create_title) { _, _ ->
                CreatePlaylistBottomSheet().apply {
                    onConfirm = { name, desc -> libraryViewModel.createPlaylist(name, desc) }
                }.show(supportFragmentManager, "create_playlist")
            }
            .show()
    }

    private fun shareDownload(download: DownloadInfo) {
        val file = File(download.filePath)
        if (!file.isFile) {
            Toast.makeText(this, R.string.downloads_file_missing, Toast.LENGTH_SHORT).show()
            return
        }
        val uri = runCatching {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        }.getOrNull()
        if (uri == null) {
            Toast.makeText(this, R.string.downloads_share_failed, Toast.LENGTH_SHORT).show()
            return
        }
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "audio/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, download.title)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, getString(R.string.downloads_share)))
    }

    private fun scheduleDeleteWithUndo(items: List<DownloadInfo>) {
        if (items.isEmpty()) return
        commitPendingDeletes()
        pendingDeleteItems = items
        selectedIds.removeAll(items.map { it.songId }.toSet())
        publishVisibleList()

        pendingDeleteSnackbar = Snackbar.make(
            binding.root,
            getString(R.string.downloads_deleted_snackbar, items.size),
            Snackbar.LENGTH_LONG
        ).setAction(R.string.downloads_undo) {
            pendingDeleteItems = emptyList()
            publishVisibleList()
        }.addCallback(object : Snackbar.Callback() {
            override fun onDismissed(transientBottomBar: Snackbar?, event: Int) {
                if (event != DISMISS_EVENT_ACTION) {
                    commitPendingDeletes()
                }
            }
        }).also { it.show() }
    }

    private fun commitPendingDeletes() {
        val items = pendingDeleteItems
        if (items.isEmpty()) return
        pendingDeleteItems = emptyList()
        items.forEach { deleteDownloadFiles(File(it.filePath)) }
        lastScanSignature = Long.MIN_VALUE
        allDownloads = allDownloads.filterNot { pending -> items.any { it.songId == pending.songId } }
        updateHeader(allDownloads)
        publishVisibleList()
    }

    private fun showDeleteAllConfirmation() {
        val downloads = allDownloads
        if (downloads.isEmpty()) return

        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.downloads_delete_all_confirm)
            .setPositiveButton(R.string.downloads_delete) { _, _ ->
                scheduleDeleteWithUndo(downloads)
                exitSelectionMode()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun deleteDownloadFiles(audioFile: File): Boolean {
        val deletedAudio = runCatching { audioFile.delete() }.getOrDefault(false)
        runCatching { File(audioFile.parentFile, "${audioFile.name}.json").delete() }
        runCatching { File(audioFile.parentFile, "${audioFile.name}.cover").delete() }
        return deletedAudio
    }

    private fun showSortDialog() {
        val labels = arrayOf(
            getString(R.string.downloads_sort_date),
            getString(R.string.downloads_sort_name),
            getString(R.string.downloads_sort_artist),
            getString(R.string.downloads_sort_size),
            getString(R.string.downloads_sort_duration)
        )
        val modes = SortMode.entries.toTypedArray()
        val checked = modes.indexOf(sortMode).coerceAtLeast(0)
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.downloads_sort)
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                sortMode = modes[which]
                publishVisibleList()
                dialog.dismiss()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showStorageInfo() {
        val primary = SongDownloader.primaryDownloadDir(this)?.absolutePath
            ?: getString(R.string.downloads_storage_private)
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.downloads_open_folder)
            .setMessage(
                getString(R.string.downloads_storage_info) + "\n\n" + primary
            )
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    private fun toggleSearch(show: Boolean) {
        searchVisible = show
        binding.searchBar.visibility = if (show) View.VISIBLE else View.GONE
        if (show) {
            binding.etSearch.requestFocus()
            val imm = getSystemService(InputMethodManager::class.java)
            imm?.showSoftInput(binding.etSearch, InputMethodManager.SHOW_IMPLICIT)
        } else {
            binding.etSearch.setText("")
            searchQuery = ""
            hideKeyboard()
            publishVisibleList()
        }
    }

    private fun hideKeyboard() {
        val imm = getSystemService(InputMethodManager::class.java)
        imm?.hideSoftInputFromWindow(binding.etSearch.windowToken, 0)
        binding.etSearch.clearFocus()
    }

    private fun enterSelectionMode(preselectId: String? = null) {
        if (allDownloads.isEmpty()) return
        selectionMode = true
        selectedIds.clear()
        preselectId?.let { selectedIds.add(it) }
        binding.toolbar.menu.clear()
        binding.toolbar.inflateMenu(R.menu.menu_downloads_selection)
        binding.toolbar.title = getString(R.string.downloads_select_count, selectedIds.size)
        binding.toolbar.contentDescription = getString(R.string.downloads_selection_mode_cd)
        binding.actionRow.visibility = View.GONE
        binding.searchBar.visibility = View.GONE
        adapter.setSelectionState(true, selectedIds)
        publishVisibleList()
    }

    private fun exitSelectionMode() {
        if (!selectionMode) return
        selectionMode = false
        selectedIds.clear()
        binding.toolbar.menu.clear()
        binding.toolbar.inflateMenu(R.menu.menu_downloads)
        binding.toolbar.title = ""
        binding.toolbar.contentDescription = null
        if (searchVisible) binding.searchBar.visibility = View.VISIBLE
        adapter.setSelectionState(false, emptySet())
        publishVisibleList()
    }

    private fun toggleSelection(download: DownloadInfo) {
        if (download.songId in selectedIds) {
            selectedIds.remove(download.songId)
        } else {
            selectedIds.add(download.songId)
        }
        adapter.setSelectionState(true, selectedIds.toSet())
        binding.toolbar.title = getString(R.string.downloads_select_count, selectedIds.size)
    }

    private fun toggleSelectAll() {
        val visibleIds = adapter.currentList.map { it.songId }
        if (selectedIds.containsAll(visibleIds) && visibleIds.isNotEmpty()) {
            selectedIds.removeAll(visibleIds.toSet())
        } else {
            selectedIds.addAll(visibleIds)
        }
        adapter.setSelectionState(true, selectedIds.toSet())
        binding.toolbar.title = getString(R.string.downloads_select_count, selectedIds.size)
    }

    private fun deleteSelected() {
        if (selectedIds.isEmpty()) return
        val items = allDownloads.filter { it.songId in selectedIds }
        MaterialAlertDialogBuilder(this)
            .setTitle(getString(R.string.downloads_delete_selected_confirm, items.size))
            .setPositiveButton(R.string.downloads_delete) { _, _ ->
                exitSelectionMode()
                scheduleDeleteWithUndo(items)
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun refreshMenuVisibility() {
        if (selectionMode) return
        val menu: Menu = binding.toolbar.menu
        val hasItems = allDownloads.isNotEmpty()
        menu.findItem(R.id.action_delete_all)?.isVisible = hasItems
        menu.findItem(R.id.action_select)?.isVisible = hasItems
        menu.findItem(R.id.action_sort)?.isVisible = hasItems
        menu.findItem(R.id.action_search)?.isVisible = hasItems
    }

    data class DownloadInfo(
        val id: Long,
        val songId: String,
        val remoteSongId: String,
        val title: String,
        val artist: String,
        val filePath: String,
        val size: Long,
        val coverPath: String?,
        val lyric: String,
        val duration: Long,
        val format: String,
        val lastModified: Long,
        val storageLabel: String
    )

    private enum class SortMode {
        DATE_DESC, NAME, ARTIST, SIZE, DURATION
    }

    private companion object {
        private val AUDIO_EXTENSIONS = setOf("mp3", "flac", "aac", "m4a", "wav", "ogg")
    }
}
