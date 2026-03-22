package com.music.player.ui.adapter

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.databinding.ItemSongBinding
import com.music.player.ui.util.ImageUrl
import com.music.player.ui.util.resolveThemeColorStateList
import java.util.Locale

class SongAdapter(
    private val onSongClick: (Song) -> Unit,
    private val onSongLongClick: (Song) -> Unit = {},
    private val onMoreClick: ((anchor: View, song: Song) -> Unit)? = null
) : ListAdapter<Song, SongAdapter.SongViewHolder>(SongDiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): SongViewHolder {
        val binding = ItemSongBinding.inflate(
            LayoutInflater.from(parent.context),
            parent,
            false
        )
        return SongViewHolder(binding)
    }

    override fun onBindViewHolder(holder: SongViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class SongViewHolder(
        private val binding: ItemSongBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(song: Song) {
            val context = binding.root.context
            binding.tvSongName.text = song.name
            binding.tvArtist.text = buildMetaLine(song)

            val hasDuration = song.duration > 0L
            binding.tvDuration.visibility = if (hasDuration) View.VISIBLE else View.GONE
            if (hasDuration) {
                binding.tvDuration.text = formatDuration(song.duration)
            }

            if (onMoreClick == null) {
                binding.btnMore.visibility = View.GONE
                binding.btnMore.setOnClickListener(null)
            } else {
                binding.btnMore.visibility = View.VISIBLE
                binding.btnMore.setOnClickListener { onMoreClick.invoke(binding.btnMore, song) }
            }

            val coverUrl = song.album.picUrl.takeIf { it.isNotBlank() }
            if (coverUrl == null) {
                binding.ivCover.setImageResource(R.drawable.ic_music_note_24)
                binding.ivCover.imageTintList = context.resolveThemeColorStateList(R.attr.brandPrimary)
            } else {
                binding.ivCover.imageTintList = null
                Glide.with(binding.ivCover)
                    .load(ImageUrl.bestQuality(coverUrl))
                    .placeholder(R.drawable.ic_music_note_24)
                    .centerCrop()
                    .dontAnimate()
                    .into(binding.ivCover)
            }

            binding.root.setOnClickListener {
                onSongClick(song)
            }

            binding.root.setOnLongClickListener {
                onSongLongClick(song)
                true
            }
        }

        private fun formatDuration(millis: Long): String {
            val totalSeconds = (millis / 1000).coerceAtLeast(0)
            val seconds = totalSeconds % 60
            val minutes = (totalSeconds / 60) % 60
            val hours = totalSeconds / 3600
            return if (hours > 0) {
                String.format(Locale.getDefault(), "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                String.format(Locale.getDefault(), "%02d:%02d", minutes, seconds)
            }
        }

        private fun buildMetaLine(song: Song): String {
            val artists = song.artists.joinToString(", ") { it.name }.trim()
            val album = song.album.name.trim()
            return when {
                artists.isBlank() -> album
                album.isBlank() || album == song.name -> artists
                else -> "$artists · $album"
            }
        }
    }

    class SongDiffCallback : DiffUtil.ItemCallback<Song>() {
        override fun areItemsTheSame(oldItem: Song, newItem: Song): Boolean {
            return oldItem.id == newItem.id
        }

        override fun areContentsTheSame(oldItem: Song, newItem: Song): Boolean {
            return oldItem == newItem
        }
    }
}
