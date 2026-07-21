package com.music.player.ui.util

import android.graphics.Color
import android.util.TypedValue
import android.view.View
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updateLayoutParams
import androidx.core.view.updatePadding
import androidx.fragment.app.Fragment
import com.bumptech.glide.Glide
import com.google.android.material.appbar.AppBarLayout
import com.music.player.R
import com.music.player.databinding.FragmentSongCollectionBinding
import kotlin.math.abs

/**
 * NetEase-style playlist/chart header:
 * - Immersive full-bleed cover + scrim
 * - Pinned toolbar (back always visible)
 * - Collapsed title fades in with content scrim
 * - Sticky "play all" row under AppBar
 */
object SongCollectionHeaderHelper {

    fun setup(
        fragment: Fragment,
        binding: FragmentSongCollectionBinding,
        initialTitle: CharSequence = ""
    ) {
        applyToolbarStatusBarInset(binding)
        binding.toolbarCollapsed.setNavigationOnClickListener {
            fragment.requireActivity().onBackPressedDispatcher.onBackPressed()
        }
        setTitle(binding, initialTitle)
        bindCollapseProgress(binding)
    }

    fun setTitle(binding: FragmentSongCollectionBinding, title: CharSequence?) {
        val text = title?.toString().orEmpty()
        binding.tvHeaderTitle.text = text
        binding.toolbarCollapsed.title = text
        val primary = resolveThemeColor(binding.root, R.attr.textPrimary)
        binding.toolbarCollapsed.setTitleTextColor(ColorUtils.setAlphaComponent(primary, 0))
    }

    fun loadCovers(
        binding: FragmentSongCollectionBinding,
        coverUrl: String?,
        placeholderTint: Boolean = true
    ) {
        val url = coverUrl?.trim().orEmpty()
        val cover = binding.ivHeaderCover
        val backdrop = binding.ivHeaderBackdrop

        if (url.isBlank()) {
            cover.setImageResource(R.drawable.ic_music_note_24)
            cover.imageTintList = if (placeholderTint) {
                binding.root.context.resolveThemeColorStateList(R.attr.brandPrimary)
            } else {
                null
            }
            backdrop.setImageResource(R.drawable.bg_header_default)
            return
        }

        cover.imageTintList = null
        val best = ImageUrl.bestQuality(url)
        Glide.with(cover)
            .load(best)
            .placeholder(R.drawable.ic_music_note_24)
            .centerCrop()
            .into(cover)

        // Full-bleed backdrop (scrim drawable darkens it for text contrast).
        Glide.with(backdrop)
            .load(best)
            .placeholder(R.drawable.bg_header_default)
            .error(R.drawable.bg_header_default)
            .centerCrop()
            .into(backdrop)
    }

    private fun bindCollapseProgress(binding: FragmentSongCollectionBinding) {
        val textPrimary = resolveThemeColor(binding.root, R.attr.textPrimary)
        val white = Color.WHITE

        binding.appBar.addOnOffsetChangedListener(
            AppBarLayout.OnOffsetChangedListener { appBar, verticalOffset ->
                val range = appBar.totalScrollRange.takeIf { it > 0 } ?: return@OnOffsetChangedListener
                val progress = (abs(verticalOffset) / range.toFloat()).coerceIn(0f, 1f)

                binding.expandedHeader.alpha = (1f - progress * 1.25f).coerceIn(0f, 1f)
                binding.headerBackdrop.alpha = (1f - progress * 0.25f).coerceIn(0.65f, 1f)

                // Title appears once header is mostly collapsed.
                val titleAlpha = ((progress - 0.35f) / 0.4f).coerceIn(0f, 1f)
                binding.toolbarCollapsed.setTitleTextColor(
                    ColorUtils.setAlphaComponent(textPrimary, (titleAlpha * 255).toInt())
                )

                val iconBlend = ColorUtils.blendARGB(white, textPrimary, titleAlpha)
                binding.toolbarCollapsed.navigationIcon?.mutate()?.setTint(iconBlend)
            }
        )
    }

    private fun applyToolbarStatusBarInset(binding: FragmentSongCollectionBinding) {
        val toolbar = binding.toolbarCollapsed
        val basePaddingTop = toolbar.paddingTop
        val baseMinHeight = actionBarSizePx(toolbar)

        ViewCompat.setOnApplyWindowInsetsListener(toolbar) { v, insets ->
            val top = insets.getInsetsIgnoringVisibility(
                WindowInsetsCompat.Type.statusBars() or WindowInsetsCompat.Type.displayCutout()
            ).top
            v.updatePadding(top = basePaddingTop + top)
            v.updateLayoutParams {
                height = baseMinHeight + top
            }
            binding.collapsingHeader.minimumHeight = baseMinHeight + top
            insets
        }
        if (ViewCompat.isAttachedToWindow(toolbar)) {
            ViewCompat.requestApplyInsets(toolbar)
        } else {
            toolbar.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(v: View) {
                    v.removeOnAttachStateChangeListener(this)
                    ViewCompat.requestApplyInsets(v)
                }

                override fun onViewDetachedFromWindow(v: View) = Unit
            })
        }
    }

    private fun actionBarSizePx(view: View): Int {
        val tv = TypedValue()
        return if (view.context.theme.resolveAttribute(android.R.attr.actionBarSize, tv, true)) {
            TypedValue.complexToDimensionPixelSize(tv.data, view.resources.displayMetrics)
        } else {
            (56 * view.resources.displayMetrics.density).toInt()
        }
    }

    private fun resolveThemeColor(view: View, attr: Int): Int {
        val tv = TypedValue()
        return if (view.context.theme.resolveAttribute(attr, tv, true)) {
            if (tv.resourceId != 0) {
                ContextCompat.getColor(view.context, tv.resourceId)
            } else {
                tv.data
            }
        } else {
            Color.WHITE
        }
    }
}
