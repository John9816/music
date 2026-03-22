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
import com.music.player.databinding.ItemPlaylistGridBinding
import com.music.player.ui.util.ImageUrl

class PlaylistGridAdapter(
    private val onPlaylistClick: (Playlist) -> Unit
) : ListAdapter<Playlist, PlaylistGridAdapter.VH>(DIFF) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val binding = ItemPlaylistGridBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return VH(binding, onPlaylistClick)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        holder.bind(getItem(position))
    }

    class VH(
        private val binding: ItemPlaylistGridBinding,
        private val onPlaylistClick: (Playlist) -> Unit
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(playlist: Playlist) {
            val context = binding.root.context
            binding.tvPlaylistName.text = playlist.name

            val desc = playlist.description.replace(Regex("\\s+"), " ").trim()
            binding.tvPlaylistDesc.text = desc
            binding.tvPlaylistDesc.visibility = if (desc.isBlank()) View.GONE else View.VISIBLE

            val playCountText = formatPlayCount(context, playlist.playCount)
            binding.tvPlayCountBadge.text = playCountText
            binding.tvPlayCountBadge.visibility = if (playlist.playCount > 0) View.VISIBLE else View.GONE

            val meta = buildMeta(context, playlist, playCountText)
            binding.tvPlaylistMeta.text = meta
            binding.tvPlaylistMeta.visibility = if (meta.isBlank()) View.GONE else View.VISIBLE

            Glide.with(binding.ivCover)
                .load(ImageUrl.bestQuality(playlist.coverImgUrl))
                .placeholder(R.drawable.ic_playlist_placeholder)
                .error(R.drawable.ic_playlist_placeholder)
                .centerCrop()
                .dontAnimate()
                .into(binding.ivCover)

            binding.root.setOnClickListener { onPlaylistClick(playlist) }
        }

        private fun formatPlayCount(context: Context, playCount: Long): String {
            return when {
                playCount >= 100_000_000 -> context.getString(R.string.play_count_yi, playCount / 100_000_000f)
                playCount >= 10_000 -> context.getString(R.string.play_count_wan, playCount / 10_000f)
                else -> context.getString(R.string.play_count_plain, playCount)
            }
        }

        private fun buildMeta(context: Context, playlist: Playlist, playCountText: String): String {
            if (playlist.trackCount <= 0 && playlist.playCount <= 0) return ""
            return context.getString(
                R.string.playlist_meta,
                playlist.trackCount.coerceAtLeast(0),
                playCountText
            )
        }
    }

    companion object {
        private val DIFF = object : DiffUtil.ItemCallback<Playlist>() {
            override fun areItemsTheSame(oldItem: Playlist, newItem: Playlist) = oldItem.id == newItem.id
            override fun areContentsTheSame(oldItem: Playlist, newItem: Playlist) = oldItem == newItem
        }
    }
}
