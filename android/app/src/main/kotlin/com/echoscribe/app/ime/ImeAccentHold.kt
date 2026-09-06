package com.echoscribe.app.ime

/**
 * Gboard-style long-press accent hold lists and slide-to-select indexing.
 * Primary umlaut (or first popup accent) is always index 0.
 */
object ImeAccentHold {
    fun defaultIndex(base: String = ""): Int = 0

    fun holdGlyphs(base: String): List<String> {
        val key = base.lowercase()
        val primary = ImeUmlauts.primary(key)
        if (primary != null) {
            return listOf(primary) + extrasAfterPrimary(key)
        }
        return ImeUmlauts.popupAccents(key)
    }

    fun hasHold(base: String): Boolean = holdGlyphs(base).isNotEmpty()

    /**
     * Maps a horizontal finger delta to a glyph index.
     * Crossing roughly one [slotWidthPx] selects the neighbor.
     */
    fun indexFromHorizontalDelta(
        deltaPx: Float,
        slotWidthPx: Float,
        count: Int,
        startIndex: Int = defaultIndex(),
    ): Int {
        if (count <= 0) return 0
        val start = startIndex.coerceIn(0, count - 1)
        if (slotWidthPx <= 0f) return start
        val ratio = deltaPx / slotWidthPx
        val steps = if (ratio >= 0f) {
            kotlin.math.floor(ratio + 0.5f).toInt()
        } else {
            kotlin.math.ceil(ratio - 0.5f).toInt()
        }
        return (start + steps).coerceIn(0, count - 1)
    }

    private fun extrasAfterPrimary(base: String): List<String> {
        return when (base) {
            "a" -> listOf("à", "á", "â", "ã", "å", "æ")
            "o" -> listOf("ò", "ó", "ô", "õ", "ø", "œ")
            "u" -> listOf("ù", "ú", "û")
            "s" -> listOf("ś", "š", "ş")
            else -> emptyList()
        }
    }
}
