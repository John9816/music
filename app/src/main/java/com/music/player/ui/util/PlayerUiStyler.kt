package com.music.player.ui.util

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.View
import android.widget.ImageButton
import androidx.annotation.AttrRes
import androidx.core.graphics.ColorUtils
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.slider.LabelFormatter
import com.google.android.material.slider.Slider
import com.music.player.R
import com.music.player.databinding.ActivityMainBinding
import com.music.player.databinding.BottomSheetNowPlayingBinding

/**
 * - [applyMiniPlayer]: fixed bottom mini bar (unrelated to PlayerStyle).
 * - [applyNowPlaying]: full-screen page chrome is shared; only the **cover**
 *   shape changes with Glass / Vinyl / Minimal.
 */
object PlayerUiStyler {

    fun applyMiniPlayer(binding: ActivityMainBinding, context: Context) {
        val background = context.resolveThemeColor(R.attr.glassSurfaceStrong)
        val stroke = context.resolveThemeColor(R.attr.glassStrokeSoft)
        val textPrimary = context.resolveThemeColor(R.attr.textPrimary)
        val textSecondary = context.resolveThemeColor(R.attr.textSecondary)
        val brand = context.resolveThemeColor(R.attr.brandPrimary)

        binding.miniPlayer.radius = context.dp(14f).toFloat()
        binding.miniPlayer.strokeWidth = context.dp(1f)
        binding.miniPlayer.strokeColor = stroke
        binding.miniPlayer.setCardBackgroundColor(background)
        binding.coverContainer.radius = context.dp(9f).toFloat()
        binding.coverContainer.strokeWidth = 0
        binding.btnMiniPlayPause.background = circleDrawable(Color.TRANSPARENT, 0)
        binding.btnMiniQueue.background = circleDrawable(Color.TRANSPARENT, 0)
        binding.btnMiniPlayPause.imageTintList = ColorStateList.valueOf(textPrimary)
        binding.btnMiniQueue.imageTintList = ColorStateList.valueOf(textSecondary)
        binding.miniProgress.setIndicatorColor(brand)
        binding.miniProgress.trackColor = ColorUtils.setAlphaComponent(textPrimary, 28)
        binding.miniProgress.trackThickness = context.dp(2f)
        binding.tvMiniTitle.setTextColor(textPrimary)
        binding.tvMiniArtist.setTextColor(textSecondary)
        binding.tvMiniArtist.visibility = View.VISIBLE
    }

    fun applyNowPlaying(binding: BottomSheetNowPlayingBinding, context: Context) {
        // Shared bottom chrome (controls / progress / transport) — never per-style.
        applySharedNowPlayingChrome(binding, context)
        // PlayerStyle only changes the cover block.
        when (ThemeManager.getPlayerStyle(context)) {
            ThemeManager.PlayerStyle.GLASS -> styleCover(
                binding = binding,
                radiusDp = 16f,
                strokeColor = ColorUtils.setAlphaComponent(Color.WHITE, 0x28),
                strokeDp = 1.5f,
                elevationDp = 12f
            )
            ThemeManager.PlayerStyle.VINYL -> styleCover(
                binding = binding,
                radiusDp = 999f,
                strokeColor = ColorUtils.setAlphaComponent(Color.WHITE, 0x40),
                strokeDp = 2f,
                elevationDp = 16f
            )
            ThemeManager.PlayerStyle.MINIMAL -> styleCover(
                binding = binding,
                radiusDp = 8f,
                strokeColor = 0,
                strokeDp = 0f,
                elevationDp = 0f
            )
        }
    }

    /**
     * One NetEase-like control strip for every style: transparent bar,
     * white play CTA, thin progress, light-on-dark icons.
     */
    private fun applySharedNowPlayingChrome(
        binding: BottomSheetNowPlayingBinding,
        context: Context
    ) {
        val textPrimary = Color.WHITE
        val textSecondary = ColorUtils.setAlphaComponent(Color.WHITE, 0xB3)
        val textTertiary = ColorUtils.setAlphaComponent(Color.WHITE, 0x80)

        applyImmersiveBackground(binding)
        binding.progressContainer.background = null
        stylePlayerControlsBar(
            card = binding.controlsBar,
            backgroundColor = Color.TRANSPARENT,
            strokeColor = 0,
            radiusDp = 0f,
            strokeWidthDp = 0f,
            context = context
        )
        styleSecondaryButtons(
            buttons = listOf(binding.btnClose, binding.btnOverflow),
            backgroundColor = Color.TRANSPARENT,
            strokeColor = 0,
            tintColor = textPrimary
        )
        styleSecondaryButtons(
            buttons = listOf(
                binding.btnFavorite,
                binding.btnPlayMode,
                binding.btnPrev,
                binding.btnNext,
                binding.btnQueue
            ),
            backgroundColor = Color.TRANSPARENT,
            strokeColor = 0,
            tintColor = textSecondary
        )
        binding.btnPrev.imageTintList = ColorStateList.valueOf(textPrimary)
        binding.btnNext.imageTintList = ColorStateList.valueOf(textPrimary)
        binding.btnPlayPause.background = circleDrawable(Color.WHITE, 0)
        binding.btnPlayPause.imageTintList = ColorStateList.valueOf(Color.parseColor("#1A1A1A"))
        stylePillButton(
            button = binding.btnAudioQuality,
            backgroundColor = ColorUtils.setAlphaComponent(Color.WHITE, 0x18),
            strokeColor = ColorUtils.setAlphaComponent(Color.WHITE, 0x28),
            textColor = textSecondary,
            iconTintColor = textSecondary,
            context = context
        )
        binding.tvSheetTitle.setTextColor(textPrimary)
        binding.tvSheetSubtitle.setTextColor(textSecondary)
        binding.tvSheetMetaDetail.setTextColor(textTertiary)
        binding.playerContent.tvLyricsPlain.setTextColor(textSecondary)

        styleCompactSlider(
            slider = binding.sliderProgress,
            thumbRadiusPx = context.dp(5f),
            trackHeightPx = context.dp(2f),
            activeTrack = textPrimary,
            inactiveTrack = ColorUtils.setAlphaComponent(Color.WHITE, 42),
            thumb = textPrimary
        )
        binding.tvCurrentTime.setTextColor(textTertiary)
        binding.tvTotalTime.setTextColor(textTertiary)
        binding.tvControlSongTitle.setTextColor(textPrimary)
        binding.tvControlSongArtist.setTextColor(textSecondary)
    }

    private fun applyImmersiveBackground(binding: BottomSheetNowPlayingBinding) {
        binding.root.setBackgroundResource(R.drawable.bg_now_playing_cymusic_scrim)
        binding.ivBlurBackground.visibility = View.VISIBLE
        binding.ivBlurBackground.alpha = 0.92f
        binding.viewScrim.setBackgroundResource(R.drawable.bg_now_playing_blur_scrim)
        binding.viewScrim.alpha = 1f
        binding.viewScrim.setTag(R.id.tag_player_style_scrim_alpha, 1f)
    }

    /** Cover-only chrome — the only piece driven by PlayerStyle. */
    private fun styleCover(
        binding: BottomSheetNowPlayingBinding,
        radiusDp: Float,
        strokeColor: Int,
        strokeDp: Float,
        elevationDp: Float
    ) {
        val density = binding.root.resources.displayMetrics.density
        val card = binding.playerContent.cardCoverBig
        card.radius = radiusDp * density
        card.strokeWidth = if (strokeColor == 0 || strokeDp <= 0f) {
            0
        } else {
            (strokeDp * density).toInt().coerceAtLeast(1)
        }
        card.strokeColor = strokeColor
        card.cardElevation = elevationDp * density
        binding.playerContent.lyricsStage.background = null
        binding.playerContent.rvLyrics.background = null
        binding.playerContent.tvLyricsPlain.background = null
    }

    private fun styleCompactSlider(
        slider: Slider,
        thumbRadiusPx: Int,
        trackHeightPx: Int,
        activeTrack: Int,
        inactiveTrack: Int,
        thumb: Int
    ) {
        slider.thumbRadius = thumbRadiusPx
        slider.haloRadius = 0
        slider.trackHeight = trackHeightPx
        slider.setLabelBehavior(LabelFormatter.LABEL_GONE)
        slider.trackActiveTintList = ColorStateList.valueOf(activeTrack)
        slider.trackInactiveTintList = ColorStateList.valueOf(inactiveTrack)
        slider.thumbTintList = ColorStateList.valueOf(thumb)
        slider.haloTintList = ColorStateList.valueOf(Color.TRANSPARENT)
        slider.thumbStrokeWidth = 0f
    }

    private fun stylePlayerControlsBar(
        card: MaterialCardView,
        backgroundColor: Int,
        strokeColor: Int,
        radiusDp: Float,
        strokeWidthDp: Float,
        context: Context
    ) {
        card.radius = context.dp(radiusDp).toFloat()
        card.strokeWidth = context.dp(strokeWidthDp)
        card.setCardBackgroundColor(backgroundColor)
        card.strokeColor = strokeColor
    }

    private fun styleSecondaryButtons(
        buttons: List<ImageButton>,
        backgroundColor: Int,
        strokeColor: Int,
        tintColor: Int
    ) {
        val background = circleDrawable(backgroundColor, strokeColor)
        buttons.forEach { button ->
            button.background = background.constantState?.newDrawable()?.mutate()
            button.imageTintList = ColorStateList.valueOf(tintColor)
        }
    }

    private fun stylePillButton(
        button: MaterialButton,
        backgroundColor: Int,
        strokeColor: Int,
        textColor: Int,
        iconTintColor: Int,
        context: Context
    ) {
        button.backgroundTintList = ColorStateList.valueOf(backgroundColor)
        button.strokeWidth = if (strokeColor == 0) 0 else context.dp(1f)
        button.strokeColor = if (strokeColor == 0) null else ColorStateList.valueOf(strokeColor)
        button.setTextColor(textColor)
        button.iconTint = ColorStateList.valueOf(iconTintColor)
    }

    private fun circleDrawable(backgroundColor: Int, strokeColor: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(backgroundColor)
            if (strokeColor != 0) {
                setStroke(2, strokeColor)
            }
        }
    }

    private fun Context.dp(value: Float): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun Context.resolveThemeColor(@AttrRes attrResId: Int): Int {
        val typedValue = TypedValue()
        theme.resolveAttribute(attrResId, typedValue, true)
        return typedValue.data
    }
}
