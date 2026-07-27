package com.music.player.ui.adapter

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.music.player.R
import com.music.player.databinding.ItemDownloadedSongBinding
import com.music.player.ui.activity.DownloadsActivity
import com.music.player.ui.util.FileSizeFormatter
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.util.resolveThemeColor
import com.music.player.ui.util.resolveThemeColorStateList
import java.io.File
import java.util.Locale
import java.util.concurrent.TimeUnit

class DownloadedSongAdapter(
    private val onPlay: (DownloadsActivity.DownloadInfo) -> Unit,
    private val onMore: (DownloadsActivity.DownloadInfo) -> Unit,
    private val onLongPress: (DownloadsActivity.DownloadInfo) -> Unit,
    private val onToggleSelect: (DownloadsActivity.DownloadInfo) -> Unit
) : ListAdapter<DownloadsActivity.DownloadInfo, DownloadedSongAdapter.ViewHolder>(Diff) {

    private var currentPlayingId: String? = null
    private var selectionMode: Boolean = false
    private var selectedIds: Set<String> = emptySet()

    fun setCurrentPlayingId(songId: String?) {
        if (currentPlayingId == songId) return
        val previousId = currentPlayingId
        currentPlayingId = songId
        currentList.forEachIndexed { index, item ->
            val id = item.songId
            if (id == previousId || id == songId) {
                notifyItemChanged(index, PAYLOAD_PLAYING)
            }
        }
    }

    fun setSelectionState(enabled: Boolean, selected: Set<String>) {
        val modeChanged = selectionMode != enabled
        selectionMode = enabled
        selectedIds = selected
        if (modeChanged) {
            notifyItemRangeChanged(0, itemCount, PAYLOAD_SELECTION)
        } else {
            currentList.forEachIndexed { index, item ->
                notifyItemChanged(index, PAYLOAD_SELECTION)
            }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val binding = ItemDownloadedSongBinding.inflate(
            LayoutInflater.from(parent.context),
            parent,
            false
        )
        return ViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.bind(getItem(position), position, currentPlayingId, selectionMode, selectedIds)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int, payloads: MutableList<Any>) {
        if (payloads.isEmpty()) {
            super.onBindViewHolder(holder, position, payloads)
            return
        }
        val item = getItem(position)
        if (payloads.contains(PAYLOAD_PLAYING)) {
            holder.bindPlayingState(item, currentPlayingId, selectionMode)
        }
        if (payloads.contains(PAYLOAD_SELECTION)) {
            holder.bindSelection(item, selectionMode, selectedIds, currentPlayingId)
        }
    }

    override fun onViewRecycled(holder: ViewHolder) {
        holder.recycle()
        super.onViewRecycled(holder)
    }

    inner class ViewHolder(
        private val binding: ItemDownloadedSongBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        private var bound: DownloadsActivity.DownloadInfo? = null

        init {
            binding.root.bindPressFeedback(PressFeedback.Style.ROW)
            binding.btnMore.bindPressFeedback(PressFeedback.Style.ICON)
            binding.root.setOnClickListener {
                val item = bound ?: return@setOnClickListener
                if (selectionMode) onToggleSelect(item) else onPlay(item)
            }
            binding.root.setOnLongClickListener {
                bound?.let(onLongPress)
                true
            }
            binding.btnMore.setOnClickListener {
                if (selectionMode) {
                    bound?.let(onToggleSelect)
                } else {
                    bound?.let(onMore)
                }
            }
        }

        fun bind(
            download: DownloadsActivity.DownloadInfo,
            position: Int,
            playingId: String?,
            selection: Boolean,
            selected: Set<String>
        ) {
            bound = download
            val context = binding.root.context
            binding.tvIndex.text = (position + 1).toString()
            binding.tvTitle.text = download.title
            binding.tvMeta.text = buildMetaLine(download)

            if (download.duration > 0L) {
                binding.tvDuration.visibility = View.VISIBLE
                binding.tvDuration.text = formatDuration(download.duration)
            } else {
                binding.tvDuration.visibility = View.GONE
            }

            val coverFile = download.coverPath?.let(::File)?.takeIf { it.isFile }
            if (coverFile == null) {
                Glide.with(binding.ivCover).clear(binding.ivCover)
                binding.ivCover.setImageResource(R.drawable.ic_music_note_24)
                binding.ivCover.imageTintList = context.resolveThemeColorStateList(R.attr.brandPrimary)
            } else {
                binding.ivCover.imageTintList = null
                Glide.with(binding.ivCover)
                    .load(coverFile)
                    .placeholder(R.drawable.ic_music_note_24)
                    .error(R.drawable.ic_music_note_24)
                    .diskCacheStrategy(DiskCacheStrategy.NONE)
                    .override(COVER_DECODE_SIZE_PX, COVER_DECODE_SIZE_PX)
                    .centerCrop()
                    .dontAnimate()
                    .into(binding.ivCover)
            }
            bindSelection(download, selection, selected, playingId)
            bindPlayingState(download, playingId, selection)
            binding.root.contentDescription = buildContentDescription(download, playingId)
        }

        fun bindSelection(
            download: DownloadsActivity.DownloadInfo,
            selection: Boolean,
            selected: Set<String>,
            playingId: String?
        ) {
            if (selection) {
                binding.checkSelect.visibility = View.VISIBLE
                binding.tvIndex.visibility = View.GONE
                binding.btnMore.visibility = View.INVISIBLE
                binding.checkSelect.isChecked = download.songId in selected
                binding.playingIndicator.visibility = View.GONE
            } else {
                binding.checkSelect.visibility = View.GONE
                binding.btnMore.visibility = View.VISIBLE
                bindPlayingState(download, playingId, selectionMode = false)
            }
        }

        fun bindPlayingState(
            download: DownloadsActivity.DownloadInfo,
            playingId: String?,
            selectionMode: Boolean
        ) {
            val context = binding.root.context
            val isPlaying = !selectionMode && playingId != null && download.songId == playingId
            val titleColor = if (isPlaying) {
                context.resolveThemeColor(R.attr.brandPrimary)
            } else {
                context.resolveThemeColor(R.attr.textPrimary)
            }
            val metaColor = if (isPlaying) {
                context.resolveThemeColor(R.attr.brandPrimary)
            } else {
                context.resolveThemeColor(R.attr.textSecondary)
            }
            binding.tvTitle.setTextColor(titleColor)
            binding.tvMeta.setTextColor(metaColor)
            binding.tvIndex.setTextColor(metaColor)
            binding.tvDuration.setTextColor(metaColor)
            binding.root.isSelected = isPlaying
            if (!selectionMode) {
                binding.playingIndicator.visibility = if (isPlaying) View.VISIBLE else View.GONE
                binding.tvIndex.visibility = if (isPlaying) View.INVISIBLE else View.VISIBLE
            }
            binding.root.contentDescription = buildContentDescription(download, playingId)
        }

        fun recycle() {
            bound = null
            Glide.with(binding.ivCover).clear(binding.ivCover)
        }

        private fun buildMetaLine(download: DownloadsActivity.DownloadInfo): String {
            val artist = download.artist.trim().ifBlank {
                binding.root.context.getString(R.string.downloads_unknown_artist)
            }
            val size = FileSizeFormatter.format(download.size)
            val format = download.format.uppercase(Locale.US)
            val catalog = if (download.remoteSongId.isNotBlank()) {
                binding.root.context.getString(R.string.downloads_catalog_linked)
            } else {
                null
            }
            return listOfNotNull(artist, size, format, catalog)
                .filter { it.isNotBlank() }
                .joinToString(" · ")
        }

        private fun buildContentDescription(
            download: DownloadsActivity.DownloadInfo,
            playingId: String?
        ): String {
            val context = binding.root.context
            val artist = download.artist.ifBlank {
                context.getString(R.string.downloads_unknown_artist)
            }
            return if (playingId != null && download.songId == playingId) {
                context.getString(R.string.downloads_item_playing_cd, download.title, artist)
            } else {
                context.getString(R.string.downloads_item_cd, download.title, artist)
            }
        }
    }

    private object Diff : DiffUtil.ItemCallback<DownloadsActivity.DownloadInfo>() {
        override fun areItemsTheSame(
            oldItem: DownloadsActivity.DownloadInfo,
            newItem: DownloadsActivity.DownloadInfo
        ): Boolean = oldItem.id == newItem.id

        override fun areContentsTheSame(
            oldItem: DownloadsActivity.DownloadInfo,
            newItem: DownloadsActivity.DownloadInfo
        ): Boolean = oldItem == newItem
    }

    private companion object {
        const val COVER_DECODE_SIZE_PX = 192
        private const val PAYLOAD_PLAYING = "playing"
        private const val PAYLOAD_SELECTION = "selection"

        fun formatDuration(durationMs: Long): String {
            val totalSeconds = TimeUnit.MILLISECONDS.toSeconds(durationMs.coerceAtLeast(0L))
            val minutes = totalSeconds / 60
            val seconds = totalSeconds % 60
            return String.format(Locale.getDefault(), "%d:%02d", minutes, seconds)
        }
    }
}
