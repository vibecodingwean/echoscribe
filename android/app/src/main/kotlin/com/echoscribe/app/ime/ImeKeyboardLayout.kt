package com.echoscribe.app.ime

object ImeKeyboardLayout {
    const val QWERTY = "qwerty"
    const val QWERTZ = "qwertz"

    fun defaultForLanguage(languageCode: String): String {
        return if (languageCode.equals("de", ignoreCase = true)) QWERTZ else QWERTY
    }

    fun normalize(value: String?, languageCode: String = ""): String {
        val trimmed = value?.trim()?.lowercase().orEmpty()
        if (trimmed == QWERTY || trimmed == QWERTZ) return trimmed
        return if (languageCode.isNotEmpty()) defaultForLanguage(languageCode) else QWERTZ
    }

    fun cycle(current: String, languageCode: String = ""): String {
        return if (normalize(current, languageCode) == QWERTZ) QWERTY else QWERTZ
    }

    fun spaceLabel(layout: String): String {
        return if (normalize(layout) == QWERTZ) "Deutsch" else "English"
    }

    fun displayLetter(base: String, uppercase: Boolean): String {
        if (!uppercase) return base
        return if (base == "ß") "ẞ" else base.uppercase()
    }

    fun row1(layout: String): List<String> {
        return keys(if (normalize(layout) == QWERTY) "qwertyuiop" else "qwertzuiop")
    }

    fun row2(layout: String): List<String> {
        return keys("asdfghjkl")
    }

    fun row3(layout: String): List<String> {
        return keys(if (normalize(layout) == QWERTY) "zxcvbnm" else "yxcvbnm")
    }

    private fun keys(raw: String): List<String> = raw.map { it.toString() }
}
