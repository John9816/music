package com.music.player.ui.adapter

import android.graphics.Typeface
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.interpolator.view.animation.FastOutSlowInInterpolator
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.music.player.R
import com.music.player.data.model.LyricLine
import com.music.player.databinding.ItemLyricLineBinding
import com.music.player.ui.util.resolveThemeColor

class LyricsAdapter : ListAdapter<LyricLine, LyricsAdapter.LyricViewHolder>(LYRIC_DIFF) {

    private var activeIndex: Int = -1

    private companion object {
        const val ANIMATION_DURATION = 120L
        const val SCALE_ACTIVE = 1.03f
        const val SCALE_INACTIVE = 1.0f
        const val PAYLOAD_ACTIVATE = "activate"
        const val PAYLOAD_DEACTIVATE = "deactivate"

        val LYRIC_DIFF = object : DiffUtil.ItemCallback<LyricLine>() {
            override fun areItemsTheSame(oldItem: LyricLine, newItem: LyricLine): Boolean =
                oldItem.time == newItem.time

            override fun areContentsTheSame(oldItem: LyricLine, newItem: LyricLine): Boolean =
                oldItem == newItem
        }
    }

    fun submitLyrics(lines: List<LyricLine>, onCommitted: (() -> Unit)? = null) {
        activeIndex = -1
        submitList(lines.toList()) { onCommitted?.invoke() }
    }

    fun setActiveIndex(index: Int) {
        if (index == activeIndex) return
        val previous = activeIndex
        activeIndex = index
        if (previous in currentList.indices) notifyItemChanged(previous, PAYLOAD_DEACTIVATE)
        if (activeIndex in currentList.indices) notifyItemChanged(activeIndex, PAYLOAD_ACTIVATE)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): LyricViewHolder {
        val binding = ItemLyricLineBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return LyricViewHolder(binding)
    }

    override fun onBindViewHolder(holder: LyricViewHolder, position: Int) {
        holder.bind(getItem(position), isActive = position == activeIndex, animate = false)
    }

    override fun onBindViewHolder(holder: LyricViewHolder, position: Int, payloads: MutableList<Any>) {
        if (payloads.isEmpty()) {
            super.onBindViewHolder(holder, position, payloads)
        } else {
            // Partial bind with animation
            val isActive = position == activeIndex
            holder.bind(getItem(position), isActive = isActive, animate = true)
        }
    }

    class LyricViewHolder(
        private val binding: ItemLyricLineBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(line: LyricLine, isActive: Boolean, animate: Boolean) {
            binding.tvLine.animate().cancel()
            binding.tvLine.text = line.text
            val context = binding.root.context

            val targetColor = context.resolveThemeColor(
                if (isActive) R.attr.brandPrimaryDark else R.attr.textSecondary
            )
            val targetAlpha = if (isActive) 1f else 0.5f
            val targetScale = if (isActive) SCALE_ACTIVE else SCALE_INACTIVE
            val targetTypeface = if (isActive) Typeface.BOLD else Typeface.NORMAL

            if (animate) {
                binding.tvLine.animate()
                    .alpha(targetAlpha)
                    .scaleX(targetScale)
                    .scaleY(targetScale)
                    .setDuration(ANIMATION_DURATION)
                    .setInterpolator(FastOutSlowInInterpolator())
                    .withStartAction {
                        binding.tvLine.setTextColor(targetColor)
                        binding.tvLine.setTypeface(binding.tvLine.typeface, targetTypeface)
                    }
                    .start()
            } else {
                binding.tvLine.setTextColor(targetColor)
                binding.tvLine.alpha = targetAlpha
                binding.tvLine.scaleX = targetScale
                binding.tvLine.scaleY = targetScale
                binding.tvLine.setTypeface(binding.tvLine.typeface, targetTypeface)
            }
        }
    }
}
