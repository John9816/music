package com.music.player.ui.util

import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import com.music.player.MainActivity
import com.music.player.R
import com.music.player.ui.activity.DownloadsActivity

object AppShortcuts {

    const val ACTION_OPEN_SEARCH = "com.music.player.action.OPEN_SEARCH"
    const val ACTION_OPEN_DOWNLOADS = "com.music.player.action.OPEN_DOWNLOADS"
    const val ACTION_OPEN_FAVORITES = "com.music.player.action.OPEN_FAVORITES"
    const val EXTRA_SHORTCUT_ID = "extra_shortcut_id"
    const val SHORTCUT_SEARCH = "search"
    const val SHORTCUT_FAVORITES = "favorites"
    const val SHORTCUT_DOWNLOADS = "downloads"

    fun publish(context: Context) {
        val sm = context.getSystemService(ShortcutManager::class.java) ?: return
        val app = context.applicationContext

        val search = ShortcutInfo.Builder(app, SHORTCUT_SEARCH)
            .setShortLabel(app.getString(R.string.shortcut_search_short))
            .setLongLabel(app.getString(R.string.shortcut_search_long))
            .setIcon(Icon.createWithResource(app, R.drawable.ic_search_24))
            .setIntent(
                Intent(app, MainActivity::class.java).apply {
                    action = ACTION_OPEN_SEARCH
                    flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra(MainActivity.EXTRA_FOCUS_LIBRARY_SEARCH, true)
                    putExtra(MainActivity.EXTRA_INITIAL_TAB_ID, R.id.nav_library)
                    putExtra(EXTRA_SHORTCUT_ID, SHORTCUT_SEARCH)
                }
            )
            .build()

        val favorites = ShortcutInfo.Builder(app, SHORTCUT_FAVORITES)
            .setShortLabel(app.getString(R.string.shortcut_favorites_short))
            .setLongLabel(app.getString(R.string.shortcut_favorites_long))
            .setIcon(Icon.createWithResource(app, R.drawable.ic_favorite_24))
            .setIntent(
                Intent(app, MainActivity::class.java).apply {
                    action = ACTION_OPEN_FAVORITES
                    flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra(MainActivity.EXTRA_INITIAL_TAB_ID, R.id.nav_library)
                    putExtra(EXTRA_SHORTCUT_ID, SHORTCUT_FAVORITES)
                }
            )
            .build()

        val downloads = ShortcutInfo.Builder(app, SHORTCUT_DOWNLOADS)
            .setShortLabel(app.getString(R.string.shortcut_downloads_short))
            .setLongLabel(app.getString(R.string.shortcut_downloads_long))
            .setIcon(Icon.createWithResource(app, R.drawable.ic_download_24))
            .setIntent(
                Intent(app, DownloadsActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
                    putExtra(EXTRA_SHORTCUT_ID, SHORTCUT_DOWNLOADS)
                }
            )
            .build()

        runCatching {
            sm.dynamicShortcuts = listOf(search, favorites, downloads)
        }
    }
}
