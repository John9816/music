package com.music.player.ui.util

import android.view.View
import android.view.ViewConfiguration
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

/** Common tuning for long vertical lists with fixed-size rows. */
fun RecyclerView.optimizeVerticalScrolling(cacheSize: Int = 12) {
    setHasFixedSize(true)
    itemAnimator = null
    overScrollMode = View.OVER_SCROLL_NEVER
    setItemViewCacheSize(cacheSize)
    recycledViewPool.setMaxRecycledViews(0, cacheSize * 2)

    (layoutManager as? LinearLayoutManager)?.apply {
        isItemPrefetchEnabled = true
        initialPrefetchItemCount = 6
    }
}

/**
 * Collapses headers only after the user scrolls beyond touch slop. This prevents
 * tiny list movements from making the page header flicker or jump.
 */
fun RecyclerView.addSlopAwareHeaderCollapseListener(
    isCollapsed: () -> Boolean,
    setCollapsed: (Boolean) -> Unit,
    onScrolledAfterHeader: (RecyclerView, Int, Int) -> Unit = { _, _, _ -> }
) {
    val threshold = ViewConfiguration.get(context).scaledTouchSlop * 2
    var accumulatedDown = 0

    addOnScrollListener(object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            if (dy > 0 && !isCollapsed()) {
                accumulatedDown += dy
                if (accumulatedDown >= threshold) {
                    accumulatedDown = 0
                    setCollapsed(true)
                }
            } else if (dy < 0) {
                accumulatedDown = 0
                if (!recyclerView.canScrollVertically(-1) && isCollapsed()) {
                    setCollapsed(false)
                }
            }
            onScrolledAfterHeader(recyclerView, dx, dy)
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            if (newState == RecyclerView.SCROLL_STATE_IDLE && !recyclerView.canScrollVertically(-1)) {
                accumulatedDown = 0
                if (isCollapsed()) {
                    setCollapsed(false)
                }
            }
        }
    })
}
