package com.music.player.ui.util

import android.animation.TimeInterpolator
import android.graphics.drawable.RippleDrawable
import android.view.MotionEvent
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.view.animation.PathInterpolator
import androidx.core.content.ContextCompat
import com.music.player.R

/**
 * NetEase Cloud Music–style press feedback:
 * - finger down: quick shrink (ease-out)
 * - finger up / cancel: softer spring-back
 * - optional light ripple when the view has no interactive background
 *
 * Driven by touch state (not click-end chaining), so the press feels immediate
 * and list rows don't wait until the click fires to animate.
 */
object PressFeedback {

    enum class Style(
        val pressedScale: Float,
        val downMs: Long,
        val upMs: Long
    ) {
        /** Song / settings rows — almost full size, very soft. */
        ROW(pressedScale = 0.985f, downMs = 70L, upMs = 170L),

        /** Playlist / album cards. */
        CARD(pressedScale = 0.96f, downMs = 80L, upMs = 180L),

        /** Icon-only controls (more / play / queue). */
        ICON(pressedScale = 0.88f, downMs = 60L, upMs = 150L),

        /** Primary / filled buttons. */
        BUTTON(pressedScale = 0.96f, downMs = 75L, upMs = 160L),

        /** Large play circle (now playing). */
        PLAY(pressedScale = 0.90f, downMs = 70L, upMs = 180L)
    }

    private val DOWN_INTERPOLATOR: TimeInterpolator = PathInterpolator(0.2f, 0f, 0.2f, 1f)
    private val UP_INTERPOLATOR: TimeInterpolator = DecelerateInterpolator(1.6f)
    private val TAG_LISTENER = R.id.press_feedback_listener_tag
    private val TAG_STYLE = R.id.press_feedback_style_tag

    /**
     * Attach press-scale feedback. Safe to call multiple times; replaces prior binding.
     * Does not consume touch events, so [View.OnClickListener] still works.
     */
    @JvmStatic
    @JvmOverloads
    fun bind(view: View, style: Style = Style.ROW, ensureRipple: Boolean = true) {
        if (ensureRipple) {
            ensureInteractiveBackground(view, style)
        }
        // Clear previous animator state if rebound after recycle.
        view.animate().cancel()
        if (view.scaleX != 1f || view.scaleY != 1f) {
            view.scaleX = 1f
            view.scaleY = 1f
        }

        val listener = View.OnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    animateScale(v, style.pressedScale, style.downMs, DOWN_INTERPOLATOR)
                }
                MotionEvent.ACTION_UP,
                MotionEvent.ACTION_CANCEL -> {
                    animateScale(v, 1f, style.upMs, UP_INTERPOLATOR)
                }
                MotionEvent.ACTION_MOVE -> {
                    // Finger left the view bounds — treat as cancel so it doesn't stick pressed.
                    val x = event.x
                    val y = event.y
                    if (x < 0 || y < 0 || x > v.width || y > v.height) {
                        animateScale(v, 1f, style.upMs, UP_INTERPOLATOR)
                    }
                }
            }
            false
        }
        view.setTag(TAG_LISTENER, listener)
        view.setTag(TAG_STYLE, style)
        view.setOnTouchListener(listener)
        if (!view.isClickable && view.hasOnClickListeners()) {
            view.isClickable = true
        }
    }

    @JvmStatic
    fun clear(view: View) {
        view.setOnTouchListener(null)
        view.setTag(TAG_LISTENER, null)
        view.setTag(TAG_STYLE, null)
        view.animate().cancel()
        view.scaleX = 1f
        view.scaleY = 1f
    }

    private fun animateScale(
        view: View,
        scale: Float,
        duration: Long,
        interpolator: TimeInterpolator
    ) {
        view.animate().cancel()
        view.animate()
            .scaleX(scale)
            .scaleY(scale)
            .setDuration(duration)
            .setInterpolator(interpolator)
            .start()
    }

    private fun ensureInteractiveBackground(view: View, style: Style) {
        val bg = view.background
        if (bg is RippleDrawable) return
        // MaterialCardView / AppCompat buttons already draw their own ripple.
        val className = view.javaClass.name
        if (className.contains("MaterialCardView") ||
            className.contains("MaterialButton") ||
            className.contains("FloatingActionButton")
        ) {
            return
        }
        if (bg == null || !bg.isStateful) {
            val res = when (style) {
                Style.ICON, Style.PLAY -> R.drawable.ripple_circular_primary
                else -> R.drawable.ripple_rect_primary
            }
            // Prefer foreground ripple on API 23+ so existing opaque backgrounds stay.
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                if (view.foreground == null) {
                    view.foreground = ContextCompat.getDrawable(view.context, res)
                }
            } else if (bg == null) {
                view.background = ContextCompat.getDrawable(view.context, res)
            }
        }
        if (!view.isClickable) {
            view.isClickable = true
        }
        view.isFocusable = true
    }
}

/** Convenience for Kotlin call sites. */
fun View.bindPressFeedback(
    style: PressFeedback.Style = PressFeedback.Style.ROW,
    ensureRipple: Boolean = true
) {
    PressFeedback.bind(this, style, ensureRipple)
}

fun View.clearPressFeedback() {
    PressFeedback.clear(this)
}
