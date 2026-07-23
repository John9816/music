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

object PlayerUiStyler {

    fun applyMiniPlayer(binding: ActivityMainBinding, context: Context) {
        applyCymusicMiniPlayer(binding, context)
    }

    private fun applyCymusicMiniPlayer(binding: ActivityMainBinding, context: Context) {
        val background = context.resolveThemeColor(R.attr.glassSurfaceStrong)
        val textPrimary = context.resolveThemeColor(R.attr.textPrimary)
        val textSecondary = context.resolveThemeColor(R.attr.textSecondary)

        binding.miniPlayer.radius = context.dp(12f).toFloat()
        binding.miniPlayer.strokeWidth = 0
        binding.miniPlayer.setCardBackgroundColor(background)
        binding.coverContainer.radius = context.dp(8f).toFloat()
        binding.coverContainer.strokeWidth = 0
        binding.btnMiniPlayPause.background = circleDrawable(Color.TRANSPARENT, 0)
        binding.btnMiniQueue.background = circleDrawable(Color.TRANSPARENT, 0)
        binding.btnMiniPlayPause.imageTintList = ColorStateList.valueOf(textPrimary)
        binding.btnMiniQueue.imageTintList = ColorStateList.valueOf(textPrimary)
        binding.miniProgress.setIndicatorColor(ColorUtils.setAlphaComponent(textSecondary, 190))
        binding.miniProgress.trackColor = ColorUtils.setAlphaComponent(textPrimary, 24)
        binding.miniProgress.trackThickness = context.dp(2f)
        binding.tvMiniTitle.setTextColor(textPrimary)
        binding.tvMiniArtist.setTextColor(textSecondary)
        binding.tvMiniArtist.visibility = View.VISIBLE
    }

    fun applyNowPlaying(binding: BottomSheetNowPlayingBinding, context: Context) {
        when (ThemeManager.getPlayerStyle(context)) {
            ThemeManager.PlayerStyle.GLASS -> applyGlassNowPlaying(binding, context)
            ThemeManager.PlayerStyle.VINYL -> applyVinylNowPlaying(binding, context)
            ThemeManager.PlayerStyle.MINIMAL -> applyMinimalNowPlaying(binding, context)
        }
    }

    private fun applyGlassMiniPlayer(binding: ActivityMainBinding, context: Context) {
        val glassStrong = context.resolveThemeColor(R.attr.glassSurfaceStrong)
        val glassSoft = context.resolveThemeColor(R.attr.glassSurfaceSoft)
        val glassStrokeSoft = context.resolveThemeColor(R.attr.glassStrokeSoft)
        val textPrimary = context.resolveThemeColor(R.attr.textPrimary)
        val textSecondary = context.resolveThemeColor(R.attr.textSecondary)

        binding.miniPlayer.radius = context.dp(18f).toFloat()
        binding.miniPlayer.strokeWidth = context.dp(1f)
        binding.miniPlayer.setCardBackgroundColor(glassStrong)
        binding.miniPlayer.strokeColor = glassStrokeSoft

        binding.coverContainer.radius = context.dp(12f).toFloat()
        binding.coverContainer.strokeWidth = 0
        binding.coverContainer.setCardBackgroundColor(glassSoft)
        binding.coverContainer.strokeColor = 0

        binding.btnMiniPlayPause.background = circleDrawable(glassSoft, 0)
        binding.btnMiniQueue.background = circleDrawable(glassSoft, 0)
        binding.btnMiniPlayPause.imageTintList = context.resolveThemeColorStateList(R.attr.textPrimary)
        binding.btnMiniQueue.imageTintList = context.resolveThemeColorStateList(R.attr.textPrimary)
        binding.miniProgress.setIndicatorColor(textPrimary)
        binding.miniProgress.trackColor = glassSoft
        binding.miniProgress.trackThickness = context.dp(2f)
        binding.tvMiniTitle.setTextColor(textPrimary)
        binding.tvMiniArtist.setTextColor(textSecondary)
    }

    private fun applyVinylMiniPlayer(binding: ActivityMainBinding, context: Context) {
        val surfaceAlt = context.resolveThemeColor(R.attr.surfaceAltColor)
        val glassStrong = context.resolveThemeColor(R.attr.glassSurfaceStrong)
        val textPrimary = context.resolveThemeColor(R.attr.textPrimary)
        val textSecondary = context.resolveThemeColor(R.attr.textSecondary)

        binding.miniPlayer.radius = context.dp(18f).toFloat()
        binding.miniPlayer.strokeWidth = context.dp(1f)
        binding.miniPlayer.setCardBackgroundColor(ColorUtils.setAlphaComponent(glassStrong, 238))
        binding.miniPlayer.strokeColor = ColorUtils.setAlphaComponent(textPrimary, 24)

        binding.coverContainer.radius = context.dp(12f).toFloat()
        binding.coverContainer.strokeWidth = 0
        binding.coverContainer.setCardBackgroundColor(ColorUtils.setAlphaComponent(surfaceAlt, 248))
        binding.coverContainer.strokeColor = 0

        binding.btnMiniPlayPause.background = circleDrawable(ColorUtils.setAlphaComponent(glassStrong, 210), 0)
        binding.btnMiniQueue.background = circleDrawable(ColorUtils.setAlphaComponent(glassStrong, 210), 0)
        binding.btnMiniPlayPause.imageTintList = context.resolveThemeColorStateList(R.attr.textPrimary)
        binding.btnMiniQueue.imageTintList = context.resolveThemeColorStateList(R.attr.textPrimary)
        binding.miniProgress.setIndicatorColor(textPrimary)
        binding.miniProgress.trackColor = ColorUtils.setAlphaComponent(textPrimary, 52)
        binding.miniProgress.trackThickness = context.dp(3f)
        binding.tvMiniTitle.setTextColor(textPrimary)
        binding.tvMiniArtist.setTextColor(textSecondary)
    }

    private fun applyMinimalMiniPlayer(binding: ActivityMainBinding, context: Context) {
        val surface = context.resolveThemeColor(R.attr.surfaceColor)
        val surfaceAlt = context.resolveThemeColor(R.attr.surfaceAltColor)
        val textPrimary = context.resolveThemeColor(R.attr.textPrimary)
        val textSecondary = context.resolveThemeColor(R.attr.textSecondary)

        binding.miniPlayer.radius = context.dp(18f).toFloat()
        binding.miniPlayer.strokeWidth = context.dp(1f)
        binding.miniPlayer.setCardBackgroundColor(ColorUtils.setAlphaComponent(surface, 246))
        binding.miniPlayer.strokeColor = ColorUtils.setAlphaComponent(textPrimary, 22)

        binding.coverContainer.radius = context.dp(12f).toFloat()
        binding.coverContainer.strokeWidth = 0
        binding.coverContainer.setCardBackgroundColor(surfaceAlt)
        binding.coverContainer.strokeColor = 0

        binding.btnMiniPlayPause.background = circleDrawable(surfaceAlt, 0)
        binding.btnMiniQueue.background = circleDrawable(surfaceAlt, 0)
        binding.btnMiniPlayPause.imageTintList = context.resolveThemeColorStateList(R.attr.textPrimary)
        binding.btnMiniQueue.imageTintList = context.resolveThemeColorStateList(R.attr.textPrimary)
        binding.miniProgress.setIndicatorColor(textPrimary)
        binding.miniProgress.trackColor = ColorUtils.setAlphaComponent(textPrimary, 22)
        binding.miniProgress.trackThickness = context.dp(2f)
        binding.tvMiniTitle.setTextColor(textPrimary)
        binding.tvMiniArtist.setTextColor(textSecondary)
    }

    private fun applyGlassNowPlaying(binding: BottomSheetNowPlayingBinding, context: Context) {
        applyNetEaseNowPlayingChrome(binding, context)
    }

    private fun applyVinylNowPlaying(binding: BottomSheetNowPlayingBinding, context: Context) {
        applyNetEaseNowPlayingChrome(binding, context)
    }

    private fun applyMinimalNowPlaying(binding: BottomSheetNowPlayingBinding, context: Context) {
        applyNetEaseNowPlayingChrome(binding, context)
    }

    /**
     * Shared full-player chrome: album blur + dark scrim, light controls on top,
     * white circular play button, thin white progress (NetEase-like).
     */
    private fun applyNetEaseNowPlayingChrome(binding: BottomSheetNowPlayingBinding, context: Context) {
        // Always light-on-dark chrome so album blur backgrounds stay readable.
        val textPrimary = Color.WHITE
        val textSecondary = ColorUtils.setAlphaComponent(Color.WHITE, 0xB3)
        val textTertiary = ColorUtils.setAlphaComponent(Color.WHITE, 0x80)

        applyImmersiveNowPlayingBackground(binding)

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
            buttons = listOf(binding.btnFavorite, binding.btnPlayMode, binding.btnPrev, binding.btnNext, binding.btnQueue),
            backgroundColor = Color.TRANSPARENT,
            strokeColor = 0,
            tintColor = textSecondary
        )
        // Prev/next slightly brighter than secondary actions.
        binding.btnPrev.imageTintList = ColorStateList.valueOf(textPrimary)
        binding.btnNext.imageTintList = ColorStateList.valueOf(textPrimary)
        // Big white play CTA (do not theme-tint away).
        binding.btnPlayPause.setBackgroundResource(R.drawable.bg_now_playing_play_circle)
        binding.btnPlayPause.imageTintList = ColorStateList.valueOf(Color.parseColor("#1A1A1A"))
        stylePillButton(
            button = binding.btnAudioQuality,
            backgroundColor = Color.TRANSPARENT,
            strokeColor = 0,
            textColor = textSecondary,
            iconTintColor = textSecondary,
            context = context
        )
        styleNowPlayingSliders(
            binding = binding,
            context = context,
            activeTrack = textPrimary,
            inactiveTrack = ColorUtils.setAlphaComponent(Color.WHITE, 40),
            thumb = textPrimary
        )
        binding.tvCurrentTime.setTextColor(textTertiary)
        binding.tvTotalTime.setTextColor(textTertiary)
        binding.tvControlSongTitle.setTextColor(textPrimary)
        binding.tvControlSongArtist.setTextColor(textSecondary)
        styleNowPlayingContent(binding, textPrimary, textSecondary)
    }

    private fun styleNowPlayingSliders(
        binding: BottomSheetNowPlayingBinding,
        context: Context,
        activeTrack: Int,
        inactiveTrack: Int,
        thumb: Int
    ) {
        val thumbRadiusPx = context.dp(6f)
        val trackHeightPx = context.dp(3f)
        styleCompactSlider(
            slider = binding.sliderProgress,
            thumbRadiusPx = thumbRadiusPx,
            trackHeightPx = trackHeightPx,
            activeTrack = activeTrack,
            inactiveTrack = inactiveTrack,
            thumb = thumb
        )
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
            button.imageTintList = android.content.res.ColorStateList.valueOf(tintColor)
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

    private fun styleNowPlayingContent(
        binding: BottomSheetNowPlayingBinding,
        primaryText: Int,
        secondaryText: Int
    ) {
        // Continuous immersive surface — no floating control card.
        binding.controlsBar.setCardBackgroundColor(Color.TRANSPARENT)
        binding.controlsBar.strokeWidth = 0
        binding.controlsBar.radius = 0f
        binding.playerContent.lyricsStage.background = null
        binding.playerContent.rvLyrics.background = null
        binding.playerContent.tvLyricsPlain.background = null
        binding.playerContent.cardCoverBig.strokeWidth = 0
        binding.playerContent.cardCoverBig.strokeColor = 0
        binding.playerContent.cardCoverBig.radius =
            binding.root.resources.displayMetrics.density * 12f
        binding.playerContent.tvLyricsPlain.setTextColor(secondaryText)
        binding.tvSheetTitle.setTextColor(primaryText)
        binding.tvSheetSubtitle.setTextColor(secondaryText)
        binding.tvSheetMetaDetail.setTextColor(ColorUtils.setAlphaComponent(Color.WHITE, 0x80))
    }

    private fun applyImmersiveNowPlayingBackground(binding: BottomSheetNowPlayingBinding) {
        // Fallback gradient while blur loads; album art blur sits under a dark scrim.
        binding.root.setBackgroundResource(R.drawable.bg_now_playing_cymusic_scrim)
        binding.ivBlurBackground.visibility = View.VISIBLE
        binding.ivBlurBackground.alpha = 0.92f
        binding.viewScrim.setBackgroundResource(R.drawable.bg_now_playing_blur_scrim)
        binding.viewScrim.alpha = 1f
    }

    private fun roundedPanelDrawable(
        backgroundColor: Int,
        strokeColor: Int,
        radiusDp: Float,
        context: Context
    ): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = context.dp(radiusDp).toFloat()
            setColor(backgroundColor)
            if (strokeColor != 0) {
                setStroke(context.dp(1f), strokeColor)
            }
        }
    }

    private fun layeredPanelDrawable(
        startColor: Int,
        endColor: Int,
        strokeColor: Int,
        radiusDp: Float,
        context: Context
    ): GradientDrawable {
        return GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            intArrayOf(startColor, endColor)
        ).apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = context.dp(radiusDp).toFloat()
            setStroke(context.dp(1f), strokeColor)
        }
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

    private fun glowCircleDrawable(coreColor: Int, edgeColor: Int): GradientDrawable {
        return GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            intArrayOf(ColorUtils.setAlphaComponent(coreColor, 255), ColorUtils.setAlphaComponent(edgeColor, 230))
        ).apply {
            shape = GradientDrawable.OVAL
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

    private fun Context.resolveThemeColorStateList(@AttrRes attrResId: Int): ColorStateList {
        return ColorStateList.valueOf(resolveThemeColor(attrResId))
    }
}
