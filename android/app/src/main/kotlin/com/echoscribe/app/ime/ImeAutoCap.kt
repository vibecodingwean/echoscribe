package com.echoscribe.app.ime

object ImeAutoCap {
    fun shouldCapitalize(textBeforeCursor: String): Boolean {
        val trimmedEnd = textBeforeCursor.trimEnd()
        if (trimmedEnd.isEmpty()) return true
        val last = trimmedEnd.last()
        if (last == '\n') return true
        return last == '.' || last == '!' || last == '?'
    }
}
