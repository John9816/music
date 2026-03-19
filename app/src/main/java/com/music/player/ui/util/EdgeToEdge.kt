package com.music.player.ui.util

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.view.View
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat

fun Activity.applyEdgeToEdge(rootView: View, lightSystemBars: Boolean): WindowInsetsControllerCompat {
    WindowCompat.setDecorFitsSystemWindows(window, false)
    window.statusBarColor = Color.TRANSPARENT
    window.navigationBarColor = Color.TRANSPARENT
    if (Build.VERSION.SDK_INT >= 29) {
        window.isStatusBarContrastEnforced = false
        window.isNavigationBarContrastEnforced = false
    }

    val controller = WindowInsetsControllerCompat(window, rootView)
    controller.isAppearanceLightStatusBars = lightSystemBars
    controller.isAppearanceLightNavigationBars = lightSystemBars
    return controller
}
