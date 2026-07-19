package com.music.player.ui.adapter

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.model.SearchArtist
import com.music.player.databinding.ItemSearchArtistBinding
import com.music.player.ui.util.ImageUrl

class SearchArtistAdapter(
    private val onArtistClick: (SearchArtist) -> Unit
) : ListAdapter<SearchArtist, SearchArtistAdapter.ViewHolder>(DIFF) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        return ViewHolder(
            ItemSearchArtistBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        )
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.bind(getItem(position), onArtistClick)
    }

    class ViewHolder(private val binding: ItemSearchArtistBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(artist: SearchArtist, onArtistClick: (SearchArtist) -> Unit) {
            binding.tvArtistName.text = artist.name
            binding.tvArtistMeta.text = if (artist.songCount > 0) {
                binding.root.context.getString(R.string.search_artist_song_count, artist.songCount)
            } else {
                binding.root.context.getString(R.string.search_type_artists)
            }
            binding.tvArtistMeta.visibility = android.view.View.VISIBLE
            binding.ivAvatar.imageTintList = null
            Glide.with(binding.ivAvatar)
                .load(ImageUrl.bestQuality(artist.avatarUrl))
                .placeholder(R.drawable.ic_person_24)
                .error(R.drawable.ic_person_24)
                .circleCrop()
                .dontAnimate()
                .into(binding.ivAvatar)
            binding.root.setOnClickListener { onArtistClick(artist) }
        }
    }

    companion object {
        private val DIFF = object : DiffUtil.ItemCallback<SearchArtist>() {
            override fun areItemsTheSame(oldItem: SearchArtist, newItem: SearchArtist) =
                oldItem.id == newItem.id && oldItem.source == newItem.source

            override fun areContentsTheSame(oldItem: SearchArtist, newItem: SearchArtist) = oldItem == newItem
        }
    }
}
