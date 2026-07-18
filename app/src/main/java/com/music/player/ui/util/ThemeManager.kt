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
            themeResId = R.style.Theme_MusicPlayer_Dark,
            titleResId = R.string.app_theme_light_title,
            summaryResId = R.string.app_theme_light_summary
        ),
        DARK(
            storageValue = "dark",
            themeResId = R.style.Theme_MusicPlayer_Dark,
            titleResId = R.string.app_theme_dark_title,
            summaryResId = R.string.app_theme_dark_summary
        ),

        // These skins define both a light (values/) and dark (values-night/) variant,
        // so they follow the system day/night setting and let the resource system pick.
        SUNSET(
            storageValue = "sunset",
            themeResId = R.style.Theme_MusicPlayer_Dark,
            titleResId = R.string.app_theme_sunset_title,
            summaryResId = R.string.app_theme_sunset_summary
        ),
        OCEAN(
            storageValue = "ocean",
            themeResId = R.style.Theme_MusicPlayer_Dark,
            titleResId = R.string.app_theme_ocean_title,
            summaryResId = R.string.app_theme_ocean_summary
        ),
        GRAPHITE(
            storageValue = "graphite",
            themeResId = R.style.Theme_MusicPlayer_Dark,
            titleResId = R.string.app_theme_graphite_title,
            summaryResId = R.string.app_theme_graphite_summary
        );

        companion object {
            fun fromStorage(value: String?): AppThemeSkin {
                return DARK
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
                return entries.firstOrNull { it.storageValue == value } ?: MINIMAL
            }
        }
    }

    fun prepareActivity(activity: Activity) {
        AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_YES)
        activity.setTheme(AppThemeSkin.DARK.themeResId)
    }

    fun getNightMode(context: Context): Int {
        return AppCompatDelegate.MODE_NIGHT_YES
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
        return AppThemeSkin.DARK
    }

    fun setAppThemeSkin(context: Context, skin: AppThemeSkin) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_APP_THEME, AppThemeSkin.DARK.storageValue)
            .apply()
        AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_YES)
    }

    fun getPlayerStyle(context: Context): PlayerStyle {
        return PlayerStyle.MINIMAL
    }

    fun setPlayerStyle(context: Context, style: PlayerStyle) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PLAYER_STYLE, PlayerStyle.MINIMAL.storageValue)
            .apply()
    }

    private fun getNightModeForSkin(skin: AppThemeSkin): Int {
        return when (skin) {
            AppThemeSkin.LIGHT -> AppCompatDelegate.MODE_NIGHT_NO
            AppThemeSkin.DARK -> AppCompatDelegate.MODE_NIGHT_YES
            // Sunset/Ocean/Graphite ship both variants, so defer to the system setting.
            AppThemeSkin.SUNSET,
            AppThemeSkin.OCEAN,
            AppThemeSkin.GRAPHITE -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
        }
    }
}
