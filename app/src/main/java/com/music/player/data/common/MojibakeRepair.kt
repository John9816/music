package com.music.player.data.common

import java.nio.charset.Charset
import java.nio.charset.StandardCharsets

/**
 * Heuristic repair for API text that was double-encoded by broken upstream pipelines.
 *
 * Two plausible corruption chains are repaired:
 * 1. UTF-8 bytes misdecoded as ISO-8859-1 (Latin-1).
 * 2. UTF-8 bytes misdecoded as Windows-1252.
 *
 * The candidate with the highest readability score wins; text that does not look like
 * mojibake is returned unchanged.
 */
internal fun repairPotentialMojibake(value: String): String {
    if (value.isBlank()) return value
    val normalized = value.trim()
    if (!looksLikeMojibake(normalized)) return normalized

    val latin1Fixed = runCatching {
        String(normalized.toByteArray(StandardCharsets.ISO_8859_1), StandardCharsets.UTF_8)
    }.getOrNull()
    // Re-encode with Windows-1252 and decode as UTF-8: the reverse of the corruption.
    val win1252Fixed = runCatching {
        repairWindows1252(normalized)
    }.getOrNull()

    return sequenceOf(normalized, latin1Fixed, win1252Fixed)
        .filterNotNull()
        .maxByOrNull(::readabilityScore)
        .orEmpty()
}

/**
 * Reverses UTF-8-bytes-misdecoded-as-Windows-1252. cp1252 leaves five byte values
 * undefined (0x81, 0x8D, 0x8F, 0x90, 0x9D), which the decoder turns into U+FFFD.
 * Those positions are brute-forced over the five candidates and the most readable
 * UTF-8 result wins. Pathological inputs with too many FFFD are not repairable.
 */
private fun repairWindows1252(value: String): String? {
    val charset = Charset.forName("Windows-1252")
    val undefined = byteArrayOf(0x81.toByte(), 0x8D.toByte(), 0x8F.toByte(), 0x90.toByte(), 0x9D.toByte())
    val base = value.toByteArray(charset)
    val fffdPositions = value.indices.filter { value[it] == '\uFFFD' }
    if (fffdPositions.isEmpty()) {
        return String(base, StandardCharsets.UTF_8)
    }
    if (fffdPositions.size > MAX_FFFD_POSITIONS) return null

    var best: String? = null
    var bestScore = Int.MIN_VALUE
    fun tryCombinations(index: Int, bytes: ByteArray) {
        if (index == fffdPositions.size) {
            val candidate = String(bytes, StandardCharsets.UTF_8)
            val score = readabilityScore(candidate)
            if (score > bestScore) {
                bestScore = score
                best = candidate
            }
            return
        }
        for (candidate in undefined) {
            bytes[fffdPositions[index]] = candidate
            tryCombinations(index + 1, bytes)
        }
    }
    tryCombinations(0, base.copyOf())
    return best
}

private const val MAX_FFFD_POSITIONS = 5

private fun looksLikeMojibake(value: String): Boolean {
    return value.contains("脙") ||
        value.contains("芒") ||
        value.contains("忙") ||
        value.contains("氓") ||
        value.contains("盲") ||
        value.contains("茂") ||
        hasLatin1MojibakeSignature(value)
}

/**
 * Detects the signature of UTF-8 bytes misdecoded as ISO-8859-1/Windows-1252: every CJK
 * character turns into roughly three Latin-1 supplement characters (Ã â ä å æ ¸ – ‡ …).
 * Requiring two or more hits keeps European words such as "âge" or "Müller" out of the
 * repair path; the readability score is the final gate anyway.
 */
private fun hasLatin1MojibakeSignature(value: String): Boolean {
    val suspicious = charArrayOf(
        '\u00C3', // Ã
        '\u00E2', // â
        '\u00E4', // ä
        '\u00E5', // å
        '\u00E6', // æ
        '\u00E7', // ç
        '\u00E8', // è
        '\u00E9', // é
        '\u00EF', // ï
        '\u00B8', // ¸
        '\u00B9', // ¹
        '\u00BA', // º
        '\u2013', // –
        '\u2014', // —
        '\u201A', // ‚
        '\u2021', // ‡
        '\u2020', // †
        '\u2039', // ‹
        '\u203A', // ›
        '\u2018', // '
        '\u2019'  // '
    )
    var hits = 0
    for (ch in value) {
        if (ch in suspicious) {
            hits++
            if (hits >= 2) return true
        }
    }
    return false
}

private fun readabilityScore(value: String): Int {
    var score = 0
    value.forEach { ch ->
        when {
            ch in '\u4E00'..'\u9FFF' -> score += 3
            ch.isLetterOrDigit() -> score += 1
        }
        if (ch == '\u00C3' || ch == '\u00E2' || ch == '\uFFFD') {
            score -= 3
        }
    }
    return score
}
