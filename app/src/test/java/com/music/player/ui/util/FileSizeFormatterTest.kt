package com.music.player.ui.util

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class FileSizeFormatterTest {
    @Test
    fun formatsBinaryUnitsWithExplicitLocale() {
        assertEquals("512 B", FileSizeFormatter.format(512, Locale.US))
        assertEquals("1.0 KB", FileSizeFormatter.format(1024, Locale.US))
        assertEquals("1.5 MB", FileSizeFormatter.format(1_572_864, Locale.US))
    }
}
