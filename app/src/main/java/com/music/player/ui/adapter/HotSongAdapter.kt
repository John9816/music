package com.music.player.ui.adapter

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.databinding.ItemHotSongBinding
import com.music.player.ui.util.ImageUrl
import com.music.player.ui.util.resolveThemeColorStateList

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
            val artists = song.artists.joinToString(", ") { it.name }.trim()
            val album = song.album.name.trim()
            binding.tvArtist.text = when {
                artists.isBlank() -> album
                album.isBlank() || album == song.name -> artists
                else -> "$artists · $album"
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
