package com.music.player.ui.view

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import com.music.player.R
import com.music.player.ui.util.resolveThemeColor

class ShimmerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private val shaderMatrix = Matrix()
    private var gradient: LinearGradient? = null

    private val baseColor = context.resolveThemeColor(R.attr.glassSurfaceStrong)
    private val highlightColor = context.resolveThemeColor(R.attr.glassHighlight)
    private val cornerRadius = resources.getDimension(R.dimen.radius_s)

    var shimmerTranslate: Float = -1f
        set(value) {
            field = value
            invalidate()
        }

    private val shimmerAnimator = ObjectAnimator.ofFloat(this, "shimmerTranslate", -1f, 2f).apply {
        duration = 1200L
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w > 0) {
            gradient = LinearGradient(
                0f, 0f, w.toFloat(), 0f,
                intArrayOf(baseColor, highlightColor, baseColor),
                floatArrayOf(0f, 0.5f, 1f),
                Shader.TileMode.CLAMP
            )
            paint.shader = gradient
        }
    }

    override fun onDraw(canvas: Canvas) {
        val g = gradient ?: return
        shaderMatrix.reset()
        shaderMatrix.setTranslate(shimmerTranslate * width, 0f)
        g.setLocalMatrix(shaderMatrix)
        rect.set(0f, 0f, width.toFloat(), height.toFloat())
        canvas.drawRoundRect(rect, cornerRadius, cornerRadius, paint)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        shimmerAnimator.start()
    }

    override fun onDetachedFromWindow() {
        shimmerAnimator.cancel()
        super.onDetachedFromWindow()
    }
}
