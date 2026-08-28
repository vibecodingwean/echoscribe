package com.echoscribe.app.ime

object ImeUmlauts {
    fun primary(base: String): String? {
        return when (base.lowercase()) {
            "a" -> "ä"
            "o" -> "ö"
            "u" -> "ü"
            "s" -> "ß"
            else -> null
        }
    }

    fun popupAccents(base: String): List<String> {
        return when (base.lowercase()) {
            "e" -> listOf("é", "è", "ê", "ë")
            "i" -> listOf("í", "ì", "î", "ï")
            "n" -> listOf("ñ")
            "c" -> listOf("ç")
            else -> emptyList()
        }
    }

    fun hasHold(base: String): Boolean {
        return primary(base) != null || popupAccents(base).isNotEmpty()
    }

    fun applyCase(glyph: String, uppercase: Boolean): String {
        if (glyph.isEmpty()) return glyph
        return ImeKeyboardLayout.displayLetter(glyph.lowercase(), uppercase)
    }
}
