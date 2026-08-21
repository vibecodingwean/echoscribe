package com.echoscribe.app.ime

data class ImeLanguage(val code: String, val label: String)

object ImeLanguages {
    val translateTargets: List<ImeLanguage> = listOf(
        ImeLanguage("am", "Amharic"),
        ImeLanguage("ar", "Arabic"),
        ImeLanguage("bn", "Bangla"),
        ImeLanguage("bs", "Bosnian"),
        ImeLanguage("bg", "Bulgarian"),
        ImeLanguage("ca", "Catalan"),
        ImeLanguage("zh", "Chinese (Simplified)"),
        ImeLanguage("hr", "Croatian"),
        ImeLanguage("cs", "Czech"),
        ImeLanguage("da", "Danish"),
        ImeLanguage("nl", "Dutch"),
        ImeLanguage("en", "English"),
        ImeLanguage("et", "Estonian"),
        ImeLanguage("fi", "Finnish"),
        ImeLanguage("fr", "French"),
        ImeLanguage("de", "German"),
        ImeLanguage("el", "Greek"),
        ImeLanguage("gu", "Gujarati"),
        ImeLanguage("he", "Hebrew"),
        ImeLanguage("hi", "Hindi"),
        ImeLanguage("hu", "Hungarian"),
        ImeLanguage("id", "Indonesian"),
        ImeLanguage("it", "Italian"),
        ImeLanguage("ja", "Japanese"),
        ImeLanguage("ko", "Korean"),
        ImeLanguage("lv", "Latvian"),
        ImeLanguage("lt", "Lithuanian"),
        ImeLanguage("ms", "Malay"),
        ImeLanguage("mr", "Marathi"),
        ImeLanguage("no", "Norwegian"),
        ImeLanguage("fa", "Persian"),
        ImeLanguage("pl", "Polish"),
        ImeLanguage("pt", "Portuguese"),
        ImeLanguage("pa", "Punjabi"),
        ImeLanguage("ro", "Romanian"),
        ImeLanguage("ru", "Russian"),
        ImeLanguage("sr", "Serbian"),
        ImeLanguage("sk", "Slovak"),
        ImeLanguage("sl", "Slovenian"),
        ImeLanguage("es", "Spanish"),
        ImeLanguage("sw", "Swahili"),
        ImeLanguage("sv", "Swedish"),
        ImeLanguage("ta", "Tamil"),
        ImeLanguage("te", "Telugu"),
        ImeLanguage("th", "Thai"),
        ImeLanguage("tr", "Turkish"),
        ImeLanguage("uk", "Ukrainian"),
        ImeLanguage("ur", "Urdu"),
        ImeLanguage("vi", "Vietnamese"),
    )

    fun labelFor(code: String): String {
        return translateTargets.firstOrNull { it.code == code }?.label ?: code
    }
}
