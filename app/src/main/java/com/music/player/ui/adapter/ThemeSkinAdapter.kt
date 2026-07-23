package com.music.player.ui.adapter

import android.graphics.drawable.GradientDrawable
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.graphics.ColorUtils
import androidx.recyclerview.widget.RecyclerView
import com.music.player.databinding.ItemThemeSkinSwatchBinding
import com.music.player.ui.util.ThemeManager

class ThemeSkinAdapter(
    private val skins: List<ThemeManager.AppThemeSkin>,
    private var selected: ThemeManager.AppThemeSkin,
    private val onSelect: (ThemeManager.AppThemeSkin) -> Unit
) : RecyclerView.Adapter<ThemeSkinAdapter.Holder>() {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val binding = ItemThemeSkinSwatchBinding.inflate(
            LayoutInflater.from(parent.context),
            parent,
            false
        )
        return Holder(binding)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) {
        holder.bind(skins[position], skins[position] == selected)
    }

    override fun getItemCount(): Int = skins.size

    fun select(skin: ThemeManager.AppThemeSkin) {
        if (skin == selected) return
        val old = skins.indexOf(selected)
        selected = skin
        if (old >= 0) notifyItemChanged(old)
        val now = skins.indexOf(selected)
        if (now >= 0) notifyItemChanged(now)
    }

    inner class Holder(
        private val binding: ItemThemeSkinSwatchBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(skin: ThemeManager.AppThemeSkin, isSelected: Boolean) {
            val context = binding.root.context
            binding.tvSkinTitle.text = context.getString(skin.titleResId)

            val density = context.resources.displayMetrics.density
            val swatch = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(skin.previewColor)
                setStroke((1.5f * density).toInt().coerceAtLeast(1), skin.previewStrokeColor)
            }
            binding.viewColorSwatch.background = swatch

            val ring = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(android.graphics.Color.TRANSPARENT)
                setStroke((2.5f * density).toInt().coerceAtLeast(2), skin.previewColor)
            }
            binding.viewSelectedRing.background = ring
            binding.viewSelectedRing.visibility = if (isSelected) View.VISIBLE else View.INVISIBLE

            val checkTint = if (ColorUtils.calculateLuminance(skin.previewColor) > 0.55) {
                0xFF1C1C1E.toInt()
            } else {
                0xFFFFFFFF.toInt()
            }
            binding.ivSelectedCheck.imageTintList =
                android.content.res.ColorStateList.valueOf(checkTint)
            binding.ivSelectedCheck.visibility = if (isSelected) View.VISIBLE else View.GONE

            binding.root.setOnClickListener {
                if (skin == selected) return@setOnClickListener
                onSelect(skin)
            }
        }
    }
}
