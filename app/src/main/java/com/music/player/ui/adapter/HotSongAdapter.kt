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
import com.music.player.databinding.ItemHotSongBinding

class HotSongAdapter(
    private val onSongClick: (Song) -> Unit,
    private val onSongLongClick: (Song) -> Unit = {}
) : ListAdapter<Song, HotSongAdapter.HotSongViewHolder>(Diff) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): HotSongViewHolder {
        val binding = ItemHotSongBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return HotSongViewHolder(binding)
    }

    override fun onBindViewHolder(holder: HotSongViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class HotSongViewHolder(
        private val binding: ItemHotSongBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(song: Song) {
            val context = binding.root.context
            binding.tvSongName.text = song.name
            binding.tvArtist.text = song.artists.joinToString(", ") { it.name }

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

            binding.root.setOnClickListener { onSongClick(song) }
            binding.root.setOnLongClickListener {
                onSongLongClick(song)
                true
            }
        }
    }

    private object Diff : DiffUtil.ItemCallback<Song>() {
        override fun areItemsTheSame(oldItem: Song, newItem: Song): Boolean = oldItem.id == newItem.id
        override fun areContentsTheSame(oldItem: Song, newItem: Song): Boolean = oldItem == newItem
    }
}

