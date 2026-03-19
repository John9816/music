package com.music.player.ui.util

import android.view.View
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding

fun View.applySystemBarInsetPadding(
    applyLeft: Boolean = false,
    applyTop: Boolean = false,
    applyRight: Boolean = false,
    applyBottom: Boolean = false
) {
    val initialLeft = paddingLeft
    val initialTop = paddingTop
    val initialRight = paddingRight
    val initialBottom = paddingBottom

    ViewCompat.setOnApplyWindowInsetsListener(this) { v, insets ->
        val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
        v.updatePadding(
            left = initialLeft + if (applyLeft) bars.left else 0,
            top = initialTop + if (applyTop) bars.top else 0,
            right = initialRight + if (applyRight) bars.right else 0,
            bottom = initialBottom + if (applyBottom) bars.bottom else 0
        )
        insets
    }
    requestApplyInsetsWhenAttached()
}

fun View.applyStatusBarInsetPadding() {
    applySystemBarInsetPadding(applyTop = true)
}

fun View.applyNavigationBarInsetPadding() {
    applySystemBarInsetPadding(applyBottom = true)
}

fun View.applyStatusBarInsetHeight() {
    val initialHeight = layoutParams?.height ?: 0
    ViewCompat.setOnApplyWindowInsetsListener(this) { v, insets ->
        val top = insets.getInsets(WindowInsetsCompat.Type.statusBars()).top
        v.layoutParams = v.layoutParams.apply { height = initialHeight + top }
        insets
    }
    requestApplyInsetsWhenAttached()
}

private fun View.requestApplyInsetsWhenAttached() {
    if (isAttachedToWindow) {
        requestApplyInsets()
    } else {
        addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) {
                v.removeOnAttachStateChangeListener(this)
                v.requestApplyInsets()
            }

            override fun onViewDetachedFromWindow(v: View) = Unit
        })
    }
}
