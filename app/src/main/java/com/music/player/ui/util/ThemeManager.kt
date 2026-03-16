package com.music.player.ui.util

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate

object ThemeManager {

    private const val PREFS = "ui_prefs"
    private const val KEY_NIGHT_MODE = "night_mode"

    fun getNightMode(context: Context): Int {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY_NIGHT_MODE)) return AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
        return prefs.getInt(KEY_NIGHT_MODE, AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
    }

    fun applySavedNightMode(context: Context) {
        AppCompatDelegate.setDefaultNightMode(getNightMode(context))
    }

    fun setNightMode(context: Context, mode: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_NIGHT_MODE, mode)
            .apply()
        AppCompatDelegate.setDefaultNightMode(mode)
    }
}

