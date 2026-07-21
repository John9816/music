package com.music.player.ui.util

import android.annotation.SuppressLint
import android.view.MotionEvent
import android.view.View

@SuppressLint("ClickableViewAccessibility")
fun View.installDownwardDragToDismiss(
    dismissDistancePx: Float,
    dragSlopPx: Float,
    onDismiss: () -> Unit
) {
    var downY = 0f
    var dragging = false

    setOnTouchListener { view, event ->
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downY = event.rawY
                dragging = false
            }
            MotionEvent.ACTION_MOVE -> {
                if (event.rawY - downY > dragSlopPx) dragging = true
            }
            MotionEvent.ACTION_UP -> {
                val shouldDismiss = dragging && event.rawY - downY >= dismissDistancePx
                dragging = false
                if (shouldDismiss) onDismiss() else view.performClick()
            }
            MotionEvent.ACTION_CANCEL -> dragging = false
        }
        true
    }
}
