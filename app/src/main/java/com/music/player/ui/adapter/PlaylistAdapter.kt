package com.music.player.ui.adapter

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.model.Playlist
import com.music.player.databinding.ItemPlaylistBinding
import com.music.player.ui.util.ImageUrl

class PlaylistAdapter(
    private val onPlaylistClick: (Playlist) -> Unit
) : ListAdapter<Playlist, PlaylistAdapter.PlaylistViewHolder>(PlaylistDiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PlaylistViewHolder {
        val binding = ItemPlaylistBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return PlaylistViewHolder(binding)
    }

    override fun onBindViewHolder(holder: PlaylistViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class PlaylistViewHolder(
        private val binding: ItemPlaylistBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(playlist: Playlist) {
            val context = binding.root.context
            binding.tvPlaylistName.text = playlist.name

            val desc = playlist.description.trim()
            binding.tvPlaylistDesc.text = desc
            binding.tvPlaylistDesc.visibility = if (desc.isBlank()) View.GONE else View.VISIBLE

            val playCountText = formatPlayCount(context, playlist.playCount)
            binding.tvPlayCountBadge.text = playCountText
            binding.tvPlayCountBadge.visibility = if (playlist.playCount > 0) View.VISIBLE else View.GONE

            binding.tvPlaylistMeta.visibility = View.GONE

            Glide.with(binding.ivCover)
                .load(ImageUrl.bestQuality(playlist.coverImgUrl))
                .placeholder(R.drawable.ic_playlist_placeholder)
                .error(R.drawable.ic_playlist_placeholder)
                .fitCenter()
                .dontAnimate()
                .into(binding.ivCover)

            binding.root.setOnClickListener { onPlaylistClick(playlist) }
        }
    }

    class PlaylistDiffCallback : DiffUtil.ItemCallback<Playlist>() {
        override fun areItemsTheSame(oldItem: Playlist, newItem: Playlist): Boolean = oldItem.id == newItem.id

        override fun areContentsTheSame(oldItem: Playlist, newItem: Playlist): Boolean = oldItem == newItem
    }

    private fun formatPlayCount(context: Context, playCount: Long): String {
        return when {
            playCount >= 100_000_000 -> context.getString(R.string.play_count_yi, playCount / 100_000_000f)
            playCount >= 10_000 -> context.getString(R.string.play_count_wan, playCount / 10_000f)
            else -> context.getString(R.string.play_count_plain, playCount)
        }
    }
}
