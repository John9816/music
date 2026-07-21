package com.music.player.ui.util

import java.util.Locale

object FileSizeFormatter {
    fun format(bytes: Long, locale: Locale = Locale.getDefault()): String = when {
        bytes >= GIB -> String.format(locale, "%.1f GB", bytes / GIB.toDouble())
        bytes >= MIB -> String.format(locale, "%.1f MB", bytes / MIB.toDouble())
        bytes >= KIB -> String.format(locale, "%.1f KB", bytes / KIB.toDouble())
        else -> "$bytes B"
    }

    private const val KIB = 1024L
    private const val MIB = KIB * 1024L
    private const val GIB = MIB * 1024L
}
