package com.echoscribe.app.ime

/** Swipe left from backspace deletes whole words. */
object ImeBackspaceGestures {
    const val WORD_SLOT_DP = 40

    fun wordDeleteCount(textBeforeCursor: String): Int {
        if (textBeforeCursor.isEmpty()) return 0
        var i = textBeforeCursor.length
        while (i > 0 && textBeforeCursor[i - 1].isWhitespace()) i--
        while (i > 0 && !textBeforeCursor[i - 1].isWhitespace()) i--
        return textBeforeCursor.length - i
    }

    /** How many extra words the leftward swipe covers after the first slot. */
    fun extraWordsFromSwipe(deltaPx: Float, slotWidthPx: Float): Int {
        if (deltaPx >= 0f || slotWidthPx <= 0f) return 0
        val slots = kotlin.math.floor((-deltaPx / slotWidthPx) + 0.0001f).toInt()
        return slots.coerceAtLeast(0)
    }
}
