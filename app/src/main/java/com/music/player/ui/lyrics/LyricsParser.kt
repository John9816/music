package com.music.player.ui.lyrics

import com.music.player.data.model.LyricLine

object LyricsParser {

    private val timeTag = Regex("""\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?]""")
    private val offsetTag = Regex("""\[offset:([+-]?\d+)]""", RegexOption.IGNORE_CASE)
    private val inlineWordTimeTag = Regex("""<\s*\d+\s*,\s*\d+(?:\s*,\s*\d+)?\s*>""")

    fun parse(lrc: String?): List<LyricLine> {
        val source = lrc?.trim().orEmpty()
        if (source.isBlank()) return emptyList()

        val offsetMs = offsetTag.find(source)?.groupValues?.getOrNull(1)?.toLongOrNull() ?: 0L
        val grouped = linkedMapOf<Float, MutableList<String>>()

        source.lineSequence().forEach { rawLine ->
            val line = rawLine.trim()
            if (line.isBlank()) return@forEach

            val matches = timeTag.findAll(line).toList()
            if (matches.isEmpty()) return@forEach

            val text = line
                .replace(timeTag, "")
                .replace(inlineWordTimeTag, "")
                .trim()
            if (text.isBlank()) return@forEach

            for (match in matches) {
                val minutes = match.groupValues[1].toIntOrNull() ?: continue
                val seconds = match.groupValues[2].toIntOrNull() ?: continue
                val fraction = match.groupValues.getOrNull(3).orEmpty()
                val millis = when (fraction.length) {
                    0 -> 0
                    1 -> fraction.toIntOrNull()?.times(100) ?: 0
                    2 -> fraction.toIntOrNull()?.times(10) ?: 0
                    else -> fraction.take(3).toIntOrNull() ?: 0
                }
                val timeSeconds = (minutes * 60_000L + seconds * 1_000L + millis + offsetMs)
                    .coerceAtLeast(0L) / 1000f
                grouped.getOrPut(timeSeconds) { mutableListOf() }.add(text)
            }
        }

        return grouped.entries
            .sortedBy { it.key }
            .map { (time, texts) ->
                LyricLine(time = time, text = texts.distinct().joinToString("\n"))
            }
    }

    fun findActiveIndex(lines: List<LyricLine>, positionMs: Long): Int {
        if (lines.isEmpty()) return -1
        val t = (positionMs.coerceAtLeast(0L) / 1000f)

        var low = 0
        var high = lines.lastIndex
        var best = -1

        while (low <= high) {
            val mid = (low + high) ushr 1
            val midTime = lines[mid].time
            if (midTime <= t) {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best
    }
}
