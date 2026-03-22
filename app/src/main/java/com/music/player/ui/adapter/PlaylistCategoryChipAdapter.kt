package com.music.player.ui.adapter

import android.graphics.Color
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.music.player.R
import com.music.player.data.model.PlaylistCategory
import com.music.player.databinding.ItemPlaylistCategoryChipBinding
import com.music.player.ui.util.resolveThemeColor

class PlaylistCategoryChipAdapter(
    private val onClick: (PlaylistCategory) -> Unit
) : ListAdapter<PlaylistCategory, PlaylistCategoryChipAdapter.VH>(DIFF) {

    var selectedApiName: String? = null
        set(value) {
            if (field == value) return
            field = value
            notifyDataSetChanged()
        }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val binding = ItemPlaylistCategoryChipBinding.inflate(
            LayoutInflater.from(parent.context),
            parent,
            false
        )
        return VH(binding, onClick)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        holder.bind(getItem(position), selectedApiName)
    }

    class VH(
        private val binding: ItemPlaylistCategoryChipBinding,
        private val onClick: (PlaylistCategory) -> Unit
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: PlaylistCategory, selectedApiName: String?) {
            binding.tvName.text = item.name
            val selected = selectedApiName == item.apiName
            val context = binding.root.context
            binding.root.strokeColor = binding.root.context.resolveThemeColor(
                if (selected) R.attr.brandPrimary else R.attr.dividerColor
            )
            binding.root.setCardBackgroundColor(
                if (selected) context.resolveThemeColor(R.attr.brandPrimaryLight) else Color.TRANSPARENT
            )
            binding.tvName.setTextColor(
                context.resolveThemeColor(if (selected) R.attr.brandPrimaryDark else R.attr.textSecondary)
            )
            binding.root.setOnClickListener { onClick(item) }
        }
    }

    companion object {
        private val DIFF = object : DiffUtil.ItemCallback<PlaylistCategory>() {
            override fun areItemsTheSame(oldItem: PlaylistCategory, newItem: PlaylistCategory) =
                oldItem.apiName == newItem.apiName

            override fun areContentsTheSame(oldItem: PlaylistCategory, newItem: PlaylistCategory) =
                oldItem == newItem
        }
    }
}
