package com.music.player.ui.util

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.widget.ImageButton
import android.widget.LinearLayout
import androidx.annotation.AttrRes
import androidx.core.graphics.ColorUtils
import com.google.android.material.card.MaterialCardView
import com.music.player.R
import com.music.player.databinding.ActivityMainBinding
import com.music.player.databinding.BottomSheetNowPlayingBinding

object PlayerUiStyler {

    fun applyMiniPlayer(binding: ActivityMainBinding, context: Context) {
        when (ThemeManager.getPlayerStyle(context)) {
            ThemeManager.PlayerStyle.GLASS -> applyGlassMiniPlayer(binding, context)
            ThemeManager.PlayerStyle.VINYL -> applyVinylMiniPlayer(binding, context)
            ThemeManager.PlayerStyle.MINIMAL -> applyMinimalMiniPlayer(binding, context)
        }
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
        val glassStroke = context.resolveThemeColor(R.attr.glassStroke)
        val glassStrokeSoft = context.resolveThemeColor(R.attr.glassStrokeSoft)
        val brandPrimary = context.resolveThemeColor(R.attr.brandPrimary)
        val textPrimary = context.resolveThemeColor(R.attr.textPrimary)

        binding.miniPlayer.radius = context.dp(24f).toFloat()
        binding.miniPlayer.strokeWidth = context.dp(1f)
        binding.miniPlayer.setCardBackgroundColor(glassStrong)
        binding.miniPlayer.strokeColor = glassStroke

        binding.coverContainer.radius = context.dp(22f).toFloat()
        binding.coverContainer.strokeWidth = context.dp(1f)
        binding.coverContainer.setCardBackgroundColor(glassSoft)
        binding.coverContainer.strokeColor = glassStrokeSoft

        binding.btnMiniPlayPause.background = circleDrawable(glassStrong, glassStroke)
        binding.btnMiniQueue.background = circleDrawable(glassStrong, glassStroke)
        binding.btnMiniPlayPause.imageTintList = context.resolveThemeColorStateList(R.attr.textPrimary)
        binding.btnMiniQueue.imageTintList = context.resolveThemeColorStateList(R.attr.textPrimary)
        binding.miniProgress.setIndicatorColor(brandPrimary)
        binding.miniProgress.trackColor = glassSoft
        binding.miniProgress.trackThickness = context.dp(2f)
        binding.tvMiniTitle.setTextColor(textPrimary)
    }

    private fun applyVinylMiniPlayer(binding: ActivityMainBinding, context: Context) {
        val surfaceAlt = context.resolveThemeColor(R.attr.surfaceAltColor)
        val glassStrong = context.resolveThemeColor(R.attr.glassSurfaceStrong)
        val brandPrimary = context.resolveThemeColor(R.attr.brandPrimary)
        val brandPrimaryDark = context.resolveThemeColor(R.attr.brandPrimaryDark)
        val textPrimary = context.resolveThemeColor(R.attr.textPrimary)

        binding.miniPlayer.radius = context.dp(30f).toFloat()
        binding.miniPlayer.strokeWidth = context.dp(1.5f)
        binding.miniPlayer.setCardBackgroundColor(ColorUtils.setAlphaComponent(surfaceAlt, 232))
        binding.miniPlayer.strokeColor = ColorUtils.setAlphaComponent(brandPrimary, 112)

        binding.coverContainer.radius = context.dp(22f).toFloat()
        binding.coverContainer.strokeWidth = context.dp(2f)
        binding.coverContainer.setCardBackgroundColor(ColorUtils.setAlphaComponent(surfaceAlt, 248))
        binding.coverContainer.strokeColor = ColorUtils.setAlphaComponent(brandPrimary, 148)

        binding.btnMiniPlayPause.background = glowCircleDrawable(brandPrimary, brandPrimaryDark)
        binding.btnMiniQueue.background = circleDrawable(ColorUtils.setAlphaComponent(glassStrong, 210), ColorUtils.setAlphaComponent(brandPrimary, 112))
        binding.btnMiniPlayPause.imageTintList = context.resolveThemeColorStateList(com.google.android.material.R.attr.colorOnPrimary)
        binding.btnMiniQueue.imageTintList = context.resolveThemeColorStateList(R.attr.brandPrimary)
        binding.miniProgress.setIndicatorColor(brandPrimary)
        binding.miniProgress.trackColor = ColorUtils.setAlphaComponent(brandPrimary, 52)
        binding.miniProgress.trackThickness = context.dp(3f)
        binding.tvMiniTitle.setTextColor(textPrimary)
    }

    private fun applyMinimalMiniPlayer(binding: ActivityMainBinding, context: Context) {
        val surface = context.resolveThemeColor(R.attr.surfaceColor)
        val surfaceAlt = context.resolveThemeColor(R.attr.surfaceAltColor)
        val textPrimary = context.resolveThemeColor(R.attr.textPrimary)
        val brandPrimary = context.resolveThemeColor(R.attr.brandPrimary)

        binding.miniPlayer.radius = context.dp(18f).toFloat()
        binding.miniPlayer.strokeWidth = 0
        binding.miniPlayer.setCardBackgroundColor(ColorUtils.setAlphaComponent(surface, 245))
        binding.miniPlayer.strokeColor = 0

        binding.coverContainer.radius = context.dp(16f).toFloat()
        binding.coverContainer.strokeWidth = 0
        binding.coverContainer.setCardBackgroundColor(surfaceAlt)
        binding.coverContainer.strokeColor = 0

        binding.btnMiniPlayPause.background = circleDrawable(surfaceAlt, 0)
        binding.btnMiniQueue.background = circleDrawable(surfaceAlt, 0)
        binding.btnMiniPlayPause.imageTintList = context.resolveThemeColorStateList(R.attr.textPrimary)
        binding.btnMiniQueue.imageTintList = context.resolveThemeColorStateList(R.attr.textPrimary)
        binding.miniProgress.setIndicatorColor(brandPrimary)
        binding.miniProgress.trackColor = ColorUtils.setAlphaComponent(textPrimary, 22)
        binding.miniProgress.trackThickness = context.dp(2f)
        binding.tvMiniTitle.setTextColor(textPrimary)
    }

    private fun applyGlassNowPlaying(binding: BottomSheetNowPlayingBinding, context: Context) {
        val pageBackground = context.resolveThemeColor(R.attr.pageBackground)
        val glassSurface = context.resolveThemeColor(R.attr.glassSurface)
        val glassStroke = context.resolveThemeColor(R.attr.glassStroke)
        val textSecondary = context.resolveThemeColor(R.attr.textSecondary)
        val brandPrimary = context.resolveThemeColor(R.attr.brandPrimary)

        binding.root.setBackgroundColor(pageBackground)
        binding.viewScrim.setBackgroundColor(pageBackground)
        binding.viewScrim.alpha = 0.72f
        binding.ivBlurBackground.alpha = 0.5f
        binding.cardCoverBig.radius = context.dp(42f).toFloat()
        binding.cardCoverBig.strokeWidth = 0
        binding.cardCoverBig.strokeColor = 0
        binding.cardCoverBig.setCardBackgroundColor(Color.TRANSPARENT)

        binding.progressContainer.background = null
        stylePlayerControlsBar(binding.controlsBar, glassSurface, 0, 28f, 0f, context)
        styleSecondaryButtons(
            buttons = listOf(binding.btnClose, binding.btnPlayMode, binding.btnPrev, binding.btnNext, binding.btnQueue),
            backgroundColor = context.resolveThemeColor(R.attr.glassSurfaceStrong),
            strokeColor = glassStroke,
            tintColor = textSecondary,
            context = context
        )
        binding.btnPlayPause.background = glowCircleDrawable(brandPrimary, context.resolveThemeColor(R.attr.brandPrimaryDark))
    }

    private fun applyVinylNowPlaying(binding: BottomSheetNowPlayingBinding, context: Context) {
        val surface = context.resolveThemeColor(R.attr.surfaceColor)
        val surfaceAlt = context.resolveThemeColor(R.attr.surfaceAltColor)
        val brandPrimary = context.resolveThemeColor(R.attr.brandPrimary)
        val brandPrimaryDark = context.resolveThemeColor(R.attr.brandPrimaryDark)
        val textPrimary = context.resolveThemeColor(R.attr.textPrimary)
        val textSecondary = context.resolveThemeColor(R.attr.textSecondary)

        binding.root.setBackgroundColor(surface)
        binding.viewScrim.setBackgroundColor(ColorUtils.blendARGB(surface, brandPrimaryDark, 0.22f))
        binding.viewScrim.alpha = 0.60f
        binding.ivBlurBackground.alpha = 0.7f
        binding.cardCoverBig.radius = context.dp(36f).toFloat()
        binding.cardCoverBig.strokeWidth = 0
        binding.cardCoverBig.strokeColor = 0
        binding.cardCoverBig.setCardBackgroundColor(Color.TRANSPARENT)

        binding.progressContainer.background = null
        stylePlayerControlsBar(
            binding.controlsBar,
            backgroundColor = ColorUtils.setAlphaComponent(surfaceAlt, 248),
            strokeColor = 0,
            radiusDp = 32f,
            strokeWidthDp = 0f,
            context = context
        )
        styleSecondaryButtons(
            buttons = listOf(binding.btnClose, binding.btnPlayMode, binding.btnPrev, binding.btnNext, binding.btnQueue),
            backgroundColor = ColorUtils.setAlphaComponent(surfaceAlt, 250),
            strokeColor = ColorUtils.setAlphaComponent(brandPrimary, 96),
            tintColor = textPrimary,
            context = context
        )
        binding.btnPlayPause.background = glowCircleDrawable(brandPrimary, brandPrimaryDark)
        binding.btnPlayPause.imageTintList = context.resolveThemeColorStateList(com.google.android.material.R.attr.colorOnPrimary)
        binding.sliderProgress.trackActiveTintList = context.resolveThemeColorStateList(R.attr.brandPrimary)
        binding.sliderProgress.trackInactiveTintList = context.resolveThemeColorStateList(R.attr.brandPrimaryLight)
        binding.sliderProgress.thumbTintList = context.resolveThemeColorStateList(R.attr.brandPrimary)
        binding.sliderProgress.haloTintList = context.resolveThemeColorStateList(R.attr.brandPrimaryLight)
        binding.tvCurrentTime.setTextColor(textSecondary)
        binding.tvTotalTime.setTextColor(textSecondary)
    }

    private fun applyMinimalNowPlaying(binding: BottomSheetNowPlayingBinding, context: Context) {
        val pageBackground = context.resolveThemeColor(R.attr.pageBackground)
        val surface = context.resolveThemeColor(R.attr.surfaceColor)
        val surfaceAlt = context.resolveThemeColor(R.attr.surfaceAltColor)
        val brandPrimary = context.resolveThemeColor(R.attr.brandPrimary)
        val textPrimary = context.resolveThemeColor(R.attr.textPrimary)
        val textSecondary = context.resolveThemeColor(R.attr.textSecondary)

        binding.root.setBackgroundColor(pageBackground)
        binding.viewScrim.setBackgroundColor(pageBackground)
        binding.viewScrim.alpha = 0.88f
        binding.ivBlurBackground.alpha = 0.28f
        binding.cardCoverBig.radius = context.dp(24f).toFloat()
        binding.cardCoverBig.strokeWidth = 0
        binding.cardCoverBig.strokeColor = 0
        binding.cardCoverBig.setCardBackgroundColor(Color.TRANSPARENT)

        binding.progressContainer.background = null
        stylePlayerControlsBar(binding.controlsBar, surface, 0, 22f, 0f, context)
        styleSecondaryButtons(
            buttons = listOf(binding.btnClose, binding.btnPlayMode, binding.btnPrev, binding.btnNext, binding.btnQueue),
            backgroundColor = surfaceAlt,
            strokeColor = 0,
            tintColor = textPrimary,
            context = context
        )
        binding.btnPlayPause.background = circleDrawable(brandPrimary, 0)
        binding.btnPlayPause.imageTintList = context.resolveThemeColorStateList(com.google.android.material.R.attr.colorOnPrimary)
        binding.sliderProgress.trackActiveTintList = context.resolveThemeColorStateList(R.attr.brandPrimary)
        binding.sliderProgress.trackInactiveTintList = context.resolveThemeColorStateList(R.attr.dividerColor)
        binding.sliderProgress.thumbTintList = context.resolveThemeColorStateList(R.attr.brandPrimary)
        binding.sliderProgress.haloTintList = context.resolveThemeColorStateList(R.attr.brandPrimaryLight)
        binding.tvCurrentTime.setTextColor(textSecondary)
        binding.tvTotalTime.setTextColor(textSecondary)
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
        tintColor: Int,
        context: Context
    ) {
        val background = circleDrawable(backgroundColor, strokeColor)
        buttons.forEach { button ->
            button.background = background.constantState?.newDrawable()?.mutate()
            button.imageTintList = android.content.res.ColorStateList.valueOf(tintColor)
        }
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
