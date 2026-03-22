package com.music.player.ui.adapter

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.model.NewestAlbum
import com.music.player.databinding.ItemNewestAlbumBannerBinding
import com.music.player.ui.util.ImageUrl
import com.music.player.ui.util.resolveThemeColorStateList

class NewestAlbumBannerAdapter : ListAdapter<NewestAlbum, NewestAlbumBannerAdapter.Vh>(Diff) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Vh {
        val binding = ItemNewestAlbumBannerBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return Vh(binding)
    }

    override fun onBindViewHolder(holder: Vh, position: Int) {
        holder.bind(getItem(position))
    }

    class Vh(
        private val binding: ItemNewestAlbumBannerBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(item: NewestAlbum) {
            val context = binding.root.context
            binding.tvAlbumName.text = item.album.name
            binding.tvArtist.text = item.artistNames

            val coverUrl = item.album.picUrl.takeIf { it.isNotBlank() }
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
        }
    }

    private object Diff : DiffUtil.ItemCallback<NewestAlbum>() {
        override fun areItemsTheSame(oldItem: NewestAlbum, newItem: NewestAlbum): Boolean =
            oldItem.album.id == newItem.album.id

        override fun areContentsTheSame(oldItem: NewestAlbum, newItem: NewestAlbum): Boolean =
            oldItem == newItem
    }
}
