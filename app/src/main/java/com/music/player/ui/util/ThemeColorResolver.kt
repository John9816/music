package com.music.player.ui.util

import android.content.Context
import android.content.res.ColorStateList
import android.util.TypedValue
import androidx.annotation.AttrRes

fun Context.resolveThemeColor(@AttrRes attrResId: Int): Int {
    val typedValue = TypedValue()
    theme.resolveAttribute(attrResId, typedValue, true)
    return typedValue.data
}

fun Context.resolveThemeColorStateList(@AttrRes attrResId: Int): ColorStateList {
    return ColorStateList.valueOf(resolveThemeColor(attrResId))
}
