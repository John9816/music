package com.music.player.ui.util

import android.app.Activity
import android.content.Context
import androidx.annotation.StringRes
import androidx.appcompat.app.AppCompatDelegate
import com.music.player.R

object ThemeManager {

    private const val PREFS = "ui_prefs"
    private const val KEY_APP_THEME = "app_theme"
    private const val KEY_PLAYER_STYLE = "player_style"

    enum class AppThemeSkin(
        val storageValue: String,
        val themeResId: Int,
        @StringRes val titleResId: Int,
        @StringRes val summaryResId: Int
    ) {
        LIGHT(
            storageValue = "light",
            themeResId = R.style.Theme_MusicPlayer_Light,
            titleResId = R.string.app_theme_light_title,
            summaryResId = R.string.app_theme_light_summary
        ),
        DARK(
            storageValue = "dark",
            themeResId = R.style.Theme_MusicPlayer_Dark,
            titleResId = R.string.app_theme_dark_title,
            summaryResId = R.string.app_theme_dark_summary
        );

        companion object {
            fun fromStorage(value: String?): AppThemeSkin {
                return entries.firstOrNull { it.storageValue == value } ?: LIGHT
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
        val themeSkin = getAppThemeSkin(activity)
        AppCompatDelegate.setDefaultNightMode(getNightModeForSkin(themeSkin))
        activity.setTheme(themeSkin.themeResId)
    }

    fun getNightMode(context: Context): Int {
        return getNightModeForSkin(getAppThemeSkin(context))
    }

    fun applySavedNightMode(context: Context) {
        AppCompatDelegate.setDefaultNightMode(getNightMode(context))
    }

    fun setNightMode(context: Context, mode: Int) {
        val theme = when (mode) {
            AppCompatDelegate.MODE_NIGHT_YES -> AppThemeSkin.DARK
            else -> AppThemeSkin.LIGHT
        }
        setAppThemeSkin(context, theme)
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
        AppCompatDelegate.setDefaultNightMode(getNightModeForSkin(skin))
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

    private fun getNightModeForSkin(skin: AppThemeSkin): Int {
        return when (skin) {
            AppThemeSkin.LIGHT -> AppCompatDelegate.MODE_NIGHT_NO
            AppThemeSkin.DARK -> AppCompatDelegate.MODE_NIGHT_YES
        }
    }
}
