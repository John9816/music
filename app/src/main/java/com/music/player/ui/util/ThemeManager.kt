package com.music.player.ui.util

import android.app.Activity
import android.content.Context
import androidx.annotation.StringRes
import androidx.appcompat.app.AppCompatDelegate
import com.music.player.R

object ThemeManager {

    private const val PREFS = "ui_prefs"
    private const val KEY_NIGHT_MODE = "night_mode"
    private const val KEY_APP_THEME = "app_theme"
    private const val KEY_PLAYER_STYLE = "player_style"

    enum class AppThemeSkin(
        val storageValue: String,
        val themeResId: Int,
        @StringRes val titleResId: Int,
        @StringRes val summaryResId: Int
    ) {
        SUNSET(
            storageValue = "sunset",
            themeResId = R.style.Theme_MusicPlayer_Sunset,
            titleResId = R.string.app_theme_sunset_title,
            summaryResId = R.string.app_theme_sunset_summary
        ),
        OCEAN(
            storageValue = "ocean",
            themeResId = R.style.Theme_MusicPlayer_Ocean,
            titleResId = R.string.app_theme_ocean_title,
            summaryResId = R.string.app_theme_ocean_summary
        ),
        GRAPHITE(
            storageValue = "graphite",
            themeResId = R.style.Theme_MusicPlayer_Graphite,
            titleResId = R.string.app_theme_graphite_title,
            summaryResId = R.string.app_theme_graphite_summary
        );

        companion object {
            fun fromStorage(value: String?): AppThemeSkin {
                return entries.firstOrNull { it.storageValue == value } ?: SUNSET
            }
        }
    }

    enum class PlayerStyle(
        val storageValue: String,
        @StringRes val titleResId: Int,
        @StringRes val summaryResId: Int
    ) {
        GLASS(
            storageValue = "glass",
            titleResId = R.string.player_style_glass_title,
            summaryResId = R.string.player_style_glass_summary
        ),
        VINYL(
            storageValue = "vinyl",
            titleResId = R.string.player_style_vinyl_title,
            summaryResId = R.string.player_style_vinyl_summary
        ),
        MINIMAL(
            storageValue = "minimal",
            titleResId = R.string.player_style_minimal_title,
            summaryResId = R.string.player_style_minimal_summary
        );

        companion object {
            fun fromStorage(value: String?): PlayerStyle {
                return entries.firstOrNull { it.storageValue == value } ?: GLASS
            }
        }
    }

    fun prepareActivity(activity: Activity) {
        activity.setTheme(getAppThemeSkin(activity).themeResId)
        AppCompatDelegate.setDefaultNightMode(getNightMode(activity))
    }

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

    fun getAppThemeSkin(context: Context): AppThemeSkin {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return AppThemeSkin.fromStorage(prefs.getString(KEY_APP_THEME, null))
    }

    fun setAppThemeSkin(context: Context, skin: AppThemeSkin) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_APP_THEME, skin.storageValue)
            .apply()
    }

    fun getPlayerStyle(context: Context): PlayerStyle {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return PlayerStyle.fromStorage(prefs.getString(KEY_PLAYER_STYLE, null))
    }

    fun setPlayerStyle(context: Context, style: PlayerStyle) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PLAYER_STYLE, style.storageValue)
            .apply()
    }
}
