package com.music.player.ui.adapter

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.music.player.R
import com.music.player.data.model.UserPlaylist
import com.music.player.databinding.ItemUserPlaylistBinding
import com.music.player.ui.util.ImageUrl
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.bindPressFeedback

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

    override fun onViewRecycled(holder: UserPlaylistViewHolder) {
        holder.recycle()
        super.onViewRecycled(holder)
    }

    inner class UserPlaylistViewHolder(
        private val binding: ItemUserPlaylistBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        private var bound: UserPlaylist? = null

        init {
            binding.root.bindPressFeedback(PressFeedback.Style.CARD)
            binding.root.setOnClickListener { bound?.let(onPlaylistClick) }
            binding.root.setOnLongClickListener {
                bound?.let(onPlaylistLongClick)
                bound != null
            }
        }

        fun bind(playlist: UserPlaylist) {
            bound = playlist
            val context = binding.root.context
            binding.tvPlaylistName.text = playlist.name
            binding.tvPlaylistMeta.text = buildMeta(context, playlist)

            val desc = playlist.description?.replace(Regex("\\s+"), " ")?.trim().orEmpty()
            binding.tvPlaylistDesc.text = desc
            binding.tvPlaylistDesc.visibility = if (desc.isBlank()) android.view.View.GONE else android.view.View.VISIBLE

            Glide.with(binding.ivCover)
                .load(ImageUrl.thumbnail(playlist.coverUrl, 300))
                .override(300, 300)
                .diskCacheStrategy(DiskCacheStrategy.AUTOMATIC)
                .placeholder(R.drawable.ic_playlist_placeholder)
                .error(R.drawable.ic_playlist_placeholder)
                .centerCrop()
                .dontAnimate()
                .into(binding.ivCover)
        }

        fun recycle() {
            Glide.with(binding.ivCover).clear(binding.ivCover)
        }

        private fun buildMeta(context: android.content.Context, playlist: UserPlaylist): String {
            val source = when (playlist.source?.lowercase()) {
                "local" -> context.getString(R.string.user_playlist_local)
                "qq" -> context.getString(R.string.user_playlist_source_qq)
                "netease" -> context.getString(R.string.user_playlist_source_netease)
                "kuwo" -> context.getString(R.string.user_playlist_source_kuwo)
                else -> context.getString(
                    if (playlist.isPublic) R.string.user_playlist_public else R.string.user_playlist_private
                )
            }
            val countText = context.resources.getQuantityString(
                R.plurals.user_playlist_track_count,
                playlist.trackCount,
                playlist.trackCount
            )
            val dateText = playlist.updatedAt?.take(10)?.trim().orEmpty()
            return listOf(source, countText, dateText)
                .filter { it.isNotBlank() }
                .joinToString(" · ")
        }
    }

    private class DiffCallback : DiffUtil.ItemCallback<UserPlaylist>() {
        override fun areItemsTheSame(oldItem: UserPlaylist, newItem: UserPlaylist): Boolean = oldItem.id == newItem.id
        override fun areContentsTheSame(oldItem: UserPlaylist, newItem: UserPlaylist): Boolean = oldItem == newItem
    }
}
