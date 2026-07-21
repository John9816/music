package com.music.player.ui.adapter

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.databinding.ItemDownloadedSongBinding
import com.music.player.ui.activity.DownloadsActivity
import com.music.player.ui.util.FileSizeFormatter
import java.io.File

class DownloadedSongAdapter(
    private val onPlay: (DownloadsActivity.DownloadInfo) -> Unit,
    private val onDelete: (DownloadsActivity.DownloadInfo) -> Unit
) : ListAdapter<DownloadsActivity.DownloadInfo, DownloadedSongAdapter.ViewHolder>(Diff) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val binding = ItemDownloadedSongBinding.inflate(
            LayoutInflater.from(parent.context),
            parent,
            false
        )
        return ViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class ViewHolder(
        private val binding: ItemDownloadedSongBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(download: DownloadsActivity.DownloadInfo) {
            binding.tvTitle.text = download.title
            Glide.with(binding.ivCover)
                .load(download.coverPath?.let(::File))
                .placeholder(R.drawable.ic_music_note_24)
                .error(R.drawable.ic_music_note_24)
                .centerCrop()
                .into(binding.ivCover)
            binding.tvSize.text = listOf(download.artist, FileSizeFormatter.format(download.size))
                .filter { it.isNotBlank() }
                .joinToString(" · ")

            binding.root.setOnClickListener {
                it.animate().scaleX(0.97f).scaleY(0.97f).setDuration(60).withEndAction {
                    it.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    onPlay(download)
                }.start()
            }

            binding.btnDelete.setOnClickListener {
                onDelete(download)
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
}
