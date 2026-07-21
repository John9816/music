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
import com.music.player.data.model.Song
import com.music.player.databinding.ItemSongBinding
import com.music.player.ui.util.ImageUrl
import com.music.player.ui.util.resolveThemeColorStateList

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

    override fun onViewRecycled(holder: SongViewHolder) {
        holder.recycle()
        super.onViewRecycled(holder)
    }

    inner class SongViewHolder(
        private val binding: ItemSongBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        private var boundSong: Song? = null

        init {
            binding.root.setOnClickListener { boundSong?.let(onSongClick) }
            binding.root.setOnLongClickListener {
                boundSong?.let(onSongLongClick)
                boundSong != null
            }
            binding.btnMore.setOnClickListener {
                boundSong?.let { song -> onMoreClick?.invoke(binding.btnMore, song) }
            }
        }

        fun bind(song: Song) {
            boundSong = song
            val context = binding.root.context
            binding.tvSongName.text = song.name
            binding.tvArtist.text = buildMetaLine(song)

            binding.tvDuration.visibility = View.GONE

            if (onMoreClick == null) {
                binding.btnMore.visibility = View.GONE
            } else {
                binding.btnMore.visibility = View.VISIBLE
            }

            val coverUrl = song.album.picUrl.takeIf { it.isNotBlank() }
            if (coverUrl == null) {
                Glide.with(binding.ivCover).clear(binding.ivCover)
                binding.ivCover.setImageResource(R.drawable.ic_music_note_24)
                binding.ivCover.imageTintList = context.resolveThemeColorStateList(R.attr.brandPrimary)
            } else {
                binding.ivCover.imageTintList = null
                Glide.with(binding.ivCover)
                    .load(ImageUrl.bestQuality(coverUrl))
                    .placeholder(R.drawable.ic_music_note_24)
                    .diskCacheStrategy(DiskCacheStrategy.AUTOMATIC)
                    .override(COVER_DECODE_SIZE_PX, COVER_DECODE_SIZE_PX)
                    .centerCrop()
                    .dontAnimate()
                    .into(binding.ivCover)
            }
        }

        fun recycle() {
            boundSong = null
            Glide.with(binding.ivCover).clear(binding.ivCover)
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

    private companion object {
        const val COVER_DECODE_SIZE_PX = 160
    }
}
