package com.music.player.ui.util

import android.graphics.Bitmap
import android.graphics.drawable.Drawable
import android.widget.ImageView
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
    private val imageView: ImageView
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
            return
        }

        imageView.alpha = 0.9f
        val newTarget = object : CustomTarget<Bitmap>() {
            override fun onResourceReady(resource: Bitmap, transition: Transition<in Bitmap>?) {
                blurJob?.cancel()
                blurJob = lifecycleOwner.lifecycleScope.launchWhenStarted {
                    val blurred = withContext(Dispatchers.Default) { blurForHeader(resource) }
                    imageView.setImageBitmap(blurred)
                }
            }

            override fun onLoadCleared(placeholder: Drawable?) = Unit

            override fun onLoadFailed(errorDrawable: Drawable?) {
                imageView.alpha = 1f
                imageView.setImageResource(R.drawable.bg_header_default)
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
}

