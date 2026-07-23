package com.music.player.ui.util

import android.animation.TimeInterpolator
import android.graphics.drawable.RippleDrawable
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.animation.PathInterpolator
import androidx.core.content.ContextCompat
import com.music.player.R

/**
 * Snappy press feedback (NetEase-like, but tuned for 60fps lists):
 * - Wait past touch-slop before shrinking so scroll gestures don't animate every row
 * - Very short press-in / spring-back so the UI never feels "heavy"
 * - Does not consume touches; click listeners still fire
 */
object PressFeedback {

    enum class Style(
        val pressedScale: Float,
        val downMs: Long,
        val upMs: Long
    ) {
        /** Song / settings rows — almost full size, instant. */
        ROW(pressedScale = 0.988f, downMs = 45L, upMs = 110L),

        /** Playlist / album cards. */
        CARD(pressedScale = 0.97f, downMs = 50L, upMs = 120L),

        /** Icon-only controls (more / play / queue). */
        ICON(pressedScale = 0.90f, downMs = 40L, upMs = 100L),

        /** Primary / filled buttons. */
        BUTTON(pressedScale = 0.97f, downMs = 45L, upMs = 110L),

        /** Large play circle (now playing). */
        PLAY(pressedScale = 0.92f, downMs = 45L, upMs = 120L)
    }

    // Material-like ease: quick commit, soft settle (faster than DecelerateInterpolator).
    private val DOWN_INTERPOLATOR: TimeInterpolator = PathInterpolator(0.2f, 0f, 0f, 1f)
    private val UP_INTERPOLATOR: TimeInterpolator = PathInterpolator(0.2f, 0f, 0.2f, 1f)
    private val TAG_LISTENER = R.id.press_feedback_listener_tag
    private val TAG_STYLE = R.id.press_feedback_style_tag
    private val TAG_PRESSED = R.id.press_feedback_pressed_tag
    private val TAG_DOWN_RUNNABLE = R.id.press_feedback_down_runnable_tag

    /** Delay press scale so flings / scrolls don't shrink rows. */
    private const val PRESS_ARM_DELAY_MS = 35L

    @JvmStatic
    @JvmOverloads
    fun bind(view: View, style: Style = Style.ROW, ensureRipple: Boolean = true) {
        if (ensureRipple) {
            ensureInteractiveBackground(view, style)
        }
        resetVisual(view)

        val touchSlop = ViewConfiguration.get(view.context).scaledTouchSlop
        var downX = 0f
        var downY = 0f

        val listener = View.OnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x
                    downY = event.y
                    schedulePress(v, style)
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.x - downX
                    val dy = event.y - downY
                    if (dx * dx + dy * dy > touchSlop * touchSlop) {
                        // Scroll / drag started — cancel arm and any active press.
                        cancelPress(v, animateBack = true, style = style)
                    } else if (event.x < 0 || event.y < 0 || event.x > v.width || event.y > v.height) {
                        cancelPress(v, animateBack = true, style = style)
                    }
                }
                MotionEvent.ACTION_UP,
                MotionEvent.ACTION_CANCEL -> {
                    cancelPress(v, animateBack = true, style = style)
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
        cancelPress(view, animateBack = false, style = null)
        view.setOnTouchListener(null)
        view.setTag(TAG_LISTENER, null)
        view.setTag(TAG_STYLE, null)
        resetVisual(view)
    }

    private fun schedulePress(view: View, style: Style) {
        cancelArm(view)
        val arm = Runnable {
            view.setTag(TAG_PRESSED, true)
            animateScale(view, style.pressedScale, style.downMs, DOWN_INTERPOLATOR)
        }
        view.setTag(TAG_DOWN_RUNNABLE, arm)
        view.postDelayed(arm, PRESS_ARM_DELAY_MS)
    }

    private fun cancelPress(view: View, animateBack: Boolean, style: Style?) {
        cancelArm(view)
        val wasPressed = view.getTag(TAG_PRESSED) == true
        view.setTag(TAG_PRESSED, false)
        if (!animateBack) {
            view.animate().cancel()
            view.scaleX = 1f
            view.scaleY = 1f
            return
        }
        if (wasPressed || view.scaleX != 1f || view.scaleY != 1f) {
            val upMs = style?.upMs ?: 110L
            animateScale(view, 1f, upMs, UP_INTERPOLATOR)
        }
    }

    private fun cancelArm(view: View) {
        val arm = view.getTag(TAG_DOWN_RUNNABLE) as? Runnable
        if (arm != null) {
            view.removeCallbacks(arm)
            view.setTag(TAG_DOWN_RUNNABLE, null)
        }
    }

    private fun resetVisual(view: View) {
        cancelArm(view)
        view.setTag(TAG_PRESSED, false)
        view.animate().cancel()
        if (view.scaleX != 1f || view.scaleY != 1f) {
            view.scaleX = 1f
            view.scaleY = 1f
        }
    }

    private fun animateScale(
        view: View,
        scale: Float,
        duration: Long,
        interpolator: TimeInterpolator
    ) {
        // Skip no-op animations (common when cancel fires without a committed press).
        if (view.scaleX == scale && view.scaleY == scale) return
        view.animate().cancel()
        view.animate()
            .scaleX(scale)
            .scaleY(scale)
            .setDuration(duration)
            .setInterpolator(interpolator)
            .setListener(null)
            .start()
    }

    private fun ensureInteractiveBackground(view: View, style: Style) {
        val bg = view.background
        if (bg is RippleDrawable) return
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

fun View.bindPressFeedback(
    style: PressFeedback.Style = PressFeedback.Style.ROW,
    ensureRipple: Boolean = true
) {
    PressFeedback.bind(this, style, ensureRipple)
}

fun View.clearPressFeedback() {
    PressFeedback.clear(this)
}
