package com.music.player.ui.adapter

import android.graphics.Typeface
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.music.player.R
import com.music.player.data.model.LyricLine
import com.music.player.databinding.ItemLyricLineBinding

class LyricsAdapter : RecyclerView.Adapter<LyricsAdapter.LyricViewHolder>() {

    private val items = mutableListOf<LyricLine>()
    private var activeIndex: Int = -1

    fun submitList(lines: List<LyricLine>) {
        items.clear()
        items.addAll(lines)
        activeIndex = -1
        notifyDataSetChanged()
    }

    fun setActiveIndex(index: Int) {
        if (index == activeIndex) return
        val previous = activeIndex
        activeIndex = index
        if (previous in items.indices) notifyItemChanged(previous)
        if (activeIndex in items.indices) notifyItemChanged(activeIndex)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): LyricViewHolder {
        val binding = ItemLyricLineBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return LyricViewHolder(binding)
    }

    override fun onBindViewHolder(holder: LyricViewHolder, position: Int) {
        holder.bind(items[position], isActive = position == activeIndex)
    }

    override fun getItemCount(): Int = items.size

    class LyricViewHolder(
        private val binding: ItemLyricLineBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(line: LyricLine, isActive: Boolean) {
            binding.tvLine.text = line.text
            val context = binding.root.context
            binding.tvLine.setTextColor(
                context.getColor(if (isActive) R.color.brand_primary_dark else R.color.text_secondary)
            )
            binding.tvLine.alpha = if (isActive) 1f else 0.5f
            binding.tvLine.setTypeface(binding.tvLine.typeface, if (isActive) Typeface.BOLD else Typeface.NORMAL)
            binding.tvLine.textSize = if (isActive) 18f else 14f
        }
    }
}
