package com.echoscribe.app.ime

/** Gboard-style spacebar: double-space period and hold-to-move cursor. */
object ImeSpaceGestures {
    const val CURSOR_SLOT_DP = 12
    const val LINE_SLOT_DP = 28
    const val HOLD_MS = 350L
    const val LOUPE_WINDOW = 24
    const val LOUPE_MARKER = '│'

    /**
     * If [textBeforeCursor] ends with a letter/digit then a single space,
     * the second space should become ". " (replace that trailing space).
     */
    fun shouldInsertPeriod(textBeforeCursor: String): Boolean {
        if (textBeforeCursor.length < 2) return false
        if (!textBeforeCursor.endsWith(' ')) return false
        val prev = textBeforeCursor[textBeforeCursor.length - 2]
        return prev.isLetterOrDigit()
    }

    fun cursorSteps(deltaPx: Float, slotWidthPx: Float): Int {
        if (slotWidthPx <= 0f) return 0
        val ratio = deltaPx / slotWidthPx
        return if (ratio >= 0f) {
            kotlin.math.floor(ratio + 0.5f).toInt()
        } else {
            kotlin.math.ceil(ratio - 0.5f).toInt()
        }
    }

    fun clampCursor(beforeLen: Int, afterLen: Int, steps: Int): Int {
        val total = (beforeLen + afterLen).coerceAtLeast(0)
        return (beforeLen + steps).coerceIn(0, total)
    }

    /**
     * 360° caret move from a local text snapshot.
     * Horizontal [charSteps] move by character (and may cross lines when
     * [lineSteps] is 0). Vertical [lineSteps] keep the column, then apply
     * remaining [charSteps] on the target line and clamp.
     */
    fun moveIndex(text: String, startIndex: Int, charSteps: Int, lineSteps: Int): Int {
        if (text.isEmpty()) return 0
        val start = startIndex.coerceIn(0, text.length)
        if (lineSteps == 0) {
            return (start + charSteps).coerceIn(0, text.length)
        }
        val lineStarts = lineStartIndices(text)
        val lineIdx = lineIndexAt(lineStarts, start)
        val col = start - lineStarts[lineIdx]
        val targetLine = (lineIdx + lineSteps).coerceIn(0, lineStarts.lastIndex)
        val maxCol = lineLength(text, lineStarts, targetLine)
        val targetCol = (col + charSteps).coerceIn(0, maxCol)
        return lineStarts[targetLine] + targetCol
    }

    fun loupeSnippet(
        text: String,
        caretIndex: Int,
        window: Int = LOUPE_WINDOW,
        marker: Char = LOUPE_MARKER,
    ): String {
        if (window <= 0) return marker.toString()
        val caret = caretIndex.coerceIn(0, text.length)
        val half = window / 2
        var start = (caret - half).coerceAtLeast(0)
        var end = (start + window).coerceAtMost(text.length)
        start = (end - window).coerceAtLeast(0)
        return sanitizeLoupe(text.substring(start, caret)) +
            marker +
            sanitizeLoupe(text.substring(caret, end))
    }

    internal fun lineStartIndices(text: String): IntArray {
        val starts = ArrayList<Int>(8)
        starts.add(0)
        for (i in text.indices) {
            if (text[i] == '\n') starts.add(i + 1)
        }
        return starts.toIntArray()
    }

    private fun lineIndexAt(lineStarts: IntArray, index: Int): Int {
        var i = lineStarts.size - 1
        while (i > 0 && lineStarts[i] > index) i--
        return i
    }

    private fun lineLength(text: String, lineStarts: IntArray, line: Int): Int {
        val start = lineStarts[line]
        val end = if (line + 1 < lineStarts.size) {
            lineStarts[line + 1] - 1
        } else {
            text.length
        }
        return (end - start).coerceAtLeast(0)
    }

    private fun sanitizeLoupe(value: String): String {
        return value.replace('\n', ' ').replace('\r', ' ')
    }
}
