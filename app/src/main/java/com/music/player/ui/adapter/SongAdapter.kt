package com.music.player.ui.adapter

import android.content.res.ColorStateList
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.databinding.ItemSongBinding

class SongAdapter(
    private val onSongClick: (Song) -> Unit,
    private val onSongLongClick: (Song) -> Unit = {}
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
            binding.tvArtist.text = song.artists.joinToString(", ") { it.name }
            binding.tvDuration.text = formatDuration(song.duration)

            val coverUrl = song.album.picUrl.takeIf { it.isNotBlank() }
            if (coverUrl == null) {
                binding.ivCover.setImageResource(R.drawable.ic_music_note_24)
                binding.ivCover.imageTintList = ColorStateList.valueOf(context.getColor(R.color.brand_primary))
            } else {
                binding.ivCover.imageTintList = null
                Glide.with(binding.ivCover)
                    .load(coverUrl)
                    .placeholder(R.drawable.ic_music_note_24)
                    .centerCrop()
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
            val seconds = (millis / 1000) % 60
            val minutes = (millis / (1000 * 60)) % 60
            return String.format("%02d:%02d", minutes, seconds)
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
