package com.music.player.ui.util

import android.app.Activity
import android.app.Application
import android.graphics.PixelFormat
import android.graphics.drawable.ColorDrawable
import android.os.Build
import android.os.Bundle
import android.view.View
import com.music.player.R

object LegacyRenderingCompat {

    fun install(application: Application) {
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
                val backgroundColor = activity.resolveThemeColor(R.attr.pageBackground)
                activity.window.setBackgroundDrawable(ColorDrawable(backgroundColor))

                if (requiresLegacySoftwareRendering(
                        sdkInt = Build.VERSION.SDK_INT,
                        manufacturer = Build.MANUFACTURER,
                        model = Build.MODEL,
                        device = Build.DEVICE
                    )
                ) {
                    activity.window.setFormat(PixelFormat.OPAQUE)
                    activity.window.decorView.setBackgroundColor(backgroundColor)
                    activity.window.decorView.setLayerType(View.LAYER_TYPE_SOFTWARE, null)
                }
            }

            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityResumed(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        })
    }
}

internal fun requiresLegacySoftwareRendering(
    sdkInt: Int,
    manufacturer: String,
    model: String,
    device: String
): Boolean {
    if (sdkInt > Build.VERSION_CODES.P) return false

    val isXiaomi = manufacturer.contains("xiaomi", ignoreCase = true)
    val isRedmi6A = model.replace(" ", "").equals("redmi6a", ignoreCase = true) ||
        device.equals("cactus", ignoreCase = true)
    return isXiaomi && isRedmi6A
}
