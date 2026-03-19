package com.music.player.ui.util

import android.graphics.Bitmap
import android.graphics.Color
import android.content.res.Configuration
import android.graphics.drawable.Drawable
import android.widget.ImageView
import androidx.core.graphics.ColorUtils
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import com.bumptech.glide.Glide
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.transition.Transition
import com.music.player.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

class ImmersiveHeaderBackground(
    private val lifecycleOwner: LifecycleOwner,
    private val imageView: ImageView,
    private val onSystemBarStyleSuggested: ((SystemBarStyleSuggestion) -> Unit)? = null
) {
    private var lastUrl: String? = null
    private var blurJob: Job? = null
    private var target: CustomTarget<Bitmap>? = null

    init {
        lifecycleOwner.lifecycle.addObserver(
            LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_DESTROY) {
                    clear()
                }
            }
        )
    }

    fun setImageUrl(url: String?) {
        val normalized = url?.trim().orEmpty().ifBlank { null }
        if (normalized == lastUrl) return
        lastUrl = normalized

        blurJob?.cancel()
        blurJob = null

        target?.let { Glide.with(imageView).clear(it) }
        target = null

        if (normalized == null) {
            imageView.alpha = 1f
            imageView.setImageResource(R.drawable.bg_header_default)
            val isNight =
                (imageView.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                    Configuration.UI_MODE_NIGHT_YES
            onSystemBarStyleSuggested?.invoke(
                SystemBarStyleSuggestion(
                    lightSystemBars = !isNight,
                    topScrimAlpha = 0.14f
                )
            )
            return
        }

        imageView.alpha = 0.9f
        val newTarget = object : CustomTarget<Bitmap>() {
            override fun onResourceReady(resource: Bitmap, transition: Transition<in Bitmap>?) {
                blurJob?.cancel()
                blurJob = lifecycleOwner.lifecycleScope.launchWhenStarted {
                    val (blurred, suggestion) = withContext(Dispatchers.Default) {
                        val blurredBitmap = blurForHeader(resource)
                        blurredBitmap to suggestSystemBars(blurredBitmap)
                    }
                    imageView.setImageBitmap(blurred)
                    suggestion?.let { onSystemBarStyleSuggested?.invoke(it) }
                }
            }

            override fun onLoadCleared(placeholder: Drawable?) = Unit

            override fun onLoadFailed(errorDrawable: Drawable?) {
                imageView.alpha = 1f
                imageView.setImageResource(R.drawable.bg_header_default)
                val isNight =
                    (imageView.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                        Configuration.UI_MODE_NIGHT_YES
                onSystemBarStyleSuggested?.invoke(
                    SystemBarStyleSuggestion(
                        lightSystemBars = !isNight,
                        topScrimAlpha = 0.18f
                    )
                )
            }
        }
        target = newTarget

        Glide.with(imageView)
            .asBitmap()
            .load(normalized)
            .centerCrop()
            .into(newTarget)
    }

    fun clear() {
        blurJob?.cancel()
        blurJob = null
        target?.let { Glide.with(imageView).clear(it) }
        target = null
    }

    private fun blurForHeader(bitmap: Bitmap): Bitmap {
        val maxSide = 520
        val w = bitmap.width.coerceAtLeast(1)
        val h = bitmap.height.coerceAtLeast(1)
        val scale = (maxSide / maxOf(w, h).toFloat()).coerceAtMost(1f)
        val scaled =
            if (scale >= 1f) bitmap else Bitmap.createScaledBitmap(
                bitmap,
                (w * scale).roundToInt().coerceAtLeast(1),
                (h * scale).roundToInt().coerceAtLeast(1),
                true
            )
        return StackBlur.blur(scaled, radius = 18)
    }

    private fun suggestSystemBars(bitmap: Bitmap): SystemBarStyleSuggestion? {
        if (bitmap.width <= 0 || bitmap.height <= 0) return null
        val average = averageColor(bitmap)
        val contrastWhite = ColorUtils.calculateContrast(Color.WHITE, average)
        val contrastBlack = ColorUtils.calculateContrast(Color.BLACK, average)
        val lightSystemBars = contrastBlack >= contrastWhite
        val bestContrast = maxOf(contrastWhite, contrastBlack)
        val topScrimAlpha = when {
            bestContrast < 2.2 -> 0.40f
            bestContrast < 3.0 -> 0.28f
            bestContrast < 3.6 -> 0.20f
            else -> 0.14f
        }
        return SystemBarStyleSuggestion(lightSystemBars = lightSystemBars, topScrimAlpha = topScrimAlpha)
    }

    private fun averageColor(bitmap: Bitmap): Int {
        val sampleX = 12
        val sampleY = 12
        val w = bitmap.width
        val h = bitmap.height
        var sumR = 0L
        var sumG = 0L
        var sumB = 0L
        var count = 0L

        for (iy in 0 until sampleY) {
            val y = ((iy + 0.5f) * h / sampleY).toInt().coerceIn(0, h - 1)
            for (ix in 0 until sampleX) {
                val x = ((ix + 0.5f) * w / sampleX).toInt().coerceIn(0, w - 1)
                val c = bitmap.getPixel(x, y)
                sumR += Color.red(c)
                sumG += Color.green(c)
                sumB += Color.blue(c)
                count++
            }
        }

        val r = (sumR / count).toInt().coerceIn(0, 255)
        val g = (sumG / count).toInt().coerceIn(0, 255)
        val b = (sumB / count).toInt().coerceIn(0, 255)
        return Color.rgb(r, g, b)
    }
}
