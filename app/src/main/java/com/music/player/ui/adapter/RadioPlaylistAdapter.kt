package com.music.player.ui.adapter

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.model.Playlist
import com.music.player.databinding.ItemRadioPlaylistBinding
import com.music.player.ui.util.ImageUrl
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.bindPressFeedback

class RadioPlaylistAdapter(
    private val onPlaylistClick: (Playlist) -> Unit
) : ListAdapter<Playlist, RadioPlaylistAdapter.ViewHolder>(DiffCallback) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val binding = ItemRadioPlaylistBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return ViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class ViewHolder(
        private val binding: ItemRadioPlaylistBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        private var bound: Playlist? = null

        init {
            binding.root.bindPressFeedback(PressFeedback.Style.CARD)
            binding.root.setOnClickListener { bound?.let(onPlaylistClick) }
        }

        fun bind(playlist: Playlist) {
            bound = playlist
            binding.tvName.text = playlist.name
            Glide.with(binding.ivCover)
                .load(ImageUrl.bestQuality(playlist.coverImgUrl))
                .placeholder(R.drawable.ic_playlist_placeholder)
                .error(R.drawable.ic_playlist_placeholder)
                .centerCrop()
                .dontAnimate()
                .into(binding.ivCover)
        }
    }

    private object DiffCallback : DiffUtil.ItemCallback<Playlist>() {
        override fun areItemsTheSame(oldItem: Playlist, newItem: Playlist): Boolean =
            oldItem.id == newItem.id && oldItem.source == newItem.source

        override fun areContentsTheSame(oldItem: Playlist, newItem: Playlist): Boolean =
            oldItem == newItem
    }
}
