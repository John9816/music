package com.music.player.ui.adapter

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.model.UserPlaylist
import com.music.player.databinding.ItemUserPlaylistBinding

class UserPlaylistAdapter(
    private val onPlaylistClick: (UserPlaylist) -> Unit,
    private val onPlaylistLongClick: (UserPlaylist) -> Unit
) : ListAdapter<UserPlaylist, UserPlaylistAdapter.UserPlaylistViewHolder>(DiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): UserPlaylistViewHolder {
        val binding = ItemUserPlaylistBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return UserPlaylistViewHolder(binding)
    }

    override fun onBindViewHolder(holder: UserPlaylistViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class UserPlaylistViewHolder(
        private val binding: ItemUserPlaylistBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(playlist: UserPlaylist) {
            val context = binding.root.context
            binding.tvPlaylistName.text = playlist.name
            binding.tvPlaylistMeta.text = playlist.description?.takeIf { it.isNotBlank() }
                ?: context.getString(if (playlist.isPublic) R.string.user_playlist_public else R.string.user_playlist_private)

            Glide.with(binding.ivCover)
                .load(playlist.coverUrl)
                .placeholder(R.drawable.ic_playlist_placeholder)
                .centerCrop()
                .into(binding.ivCover)

            binding.root.setOnClickListener { onPlaylistClick(playlist) }
            binding.root.setOnLongClickListener {
                onPlaylistLongClick(playlist)
                true
            }
        }
    }

    private class DiffCallback : DiffUtil.ItemCallback<UserPlaylist>() {
        override fun areItemsTheSame(oldItem: UserPlaylist, newItem: UserPlaylist): Boolean = oldItem.id == newItem.id
        override fun areContentsTheSame(oldItem: UserPlaylist, newItem: UserPlaylist): Boolean = oldItem == newItem
    }
}

