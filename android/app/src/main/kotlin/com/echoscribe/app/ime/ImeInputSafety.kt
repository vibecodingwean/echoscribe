package com.echoscribe.app.ime

/**
 * Pure InputType / autofill safety checks for the EchoScribe IME.
 * Uses numeric InputType constants so JVM unit tests do not need an Android device.
 */
object ImeInputSafety {
    // android.text.InputType
    const val TYPE_MASK_CLASS = 0x0000000f
    const val TYPE_MASK_VARIATION = 0x00000ff0
    const val TYPE_CLASS_TEXT = 0x00000001
    const val TYPE_CLASS_NUMBER = 0x00000002
    const val TYPE_CLASS_PHONE = 0x00000003
    const val TYPE_TEXT_VARIATION_PASSWORD = 0x00000080
    const val TYPE_TEXT_VARIATION_VISIBLE_PASSWORD = 0x00000090
    const val TYPE_TEXT_VARIATION_WEB_PASSWORD = 0x000000e0
    const val TYPE_NUMBER_VARIATION_PASSWORD = 0x00000010

    private val sensitiveAutofillHints = setOf(
        "password",
        "passwordAuto",
        "newPassword",
        "newPasswordAuto",
        "creditCardNumber",
        "creditCardSecurityCode",
        "creditCardExpirationDate",
        "creditCardExpirationMonth",
        "creditCardExpirationYear",
        "creditCardExpirationDay",
        "postalAddress",
        "postalCode",
        "phoneNational",
        "phoneNumber",
        "phoneNumberDevice",
        "phoneCountryCode",
        "smsOTP",
        "emailOTP",
        "appOTP",
        "otp",
    )

    private val sensitiveHintTokens = listOf(
        "password",
        "passwort",
        "pin",
        "otp",
        "cvv",
        "cvc",
        "card number",
        "kartennummer",
        "credit card",
        "kreditkarte",
        "iban",
        "secure code",
        "sicherheitscode",
    )

    fun isSensitiveInput(
        inputType: Int,
        autofillHints: List<String> = emptyList(),
        hintOrDescription: String? = null,
    ): Boolean {
        if (isSensitiveInputType(inputType)) return true
        if (autofillHints.any { isSensitiveAutofillHint(it) }) return true
        val meta = hintOrDescription?.lowercase().orEmpty()
        return meta.isNotBlank() && sensitiveHintTokens.any { meta.contains(it) }
    }

    fun isSensitiveInputType(inputType: Int): Boolean {
        val inputClass = inputType and TYPE_MASK_CLASS
        val variation = inputType and TYPE_MASK_VARIATION
        if (inputClass == TYPE_CLASS_PHONE) return true
        if (inputClass == TYPE_CLASS_TEXT &&
            (variation == TYPE_TEXT_VARIATION_PASSWORD ||
                variation == TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                variation == TYPE_TEXT_VARIATION_WEB_PASSWORD)
        ) {
            return true
        }
        if (inputClass == TYPE_CLASS_NUMBER && variation == TYPE_NUMBER_VARIATION_PASSWORD) {
            return true
        }
        return false
    }

    fun isSensitiveAutofillHint(hint: String): Boolean {
        val normalized = hint.trim()
        if (normalized.isEmpty()) return false
        val bare = normalized.substringAfterLast('.').substringAfterLast(':')
        return sensitiveAutofillHints.any { it.equals(bare, ignoreCase = true) } ||
            bare.contains("password", ignoreCase = true) ||
            bare.contains("creditCard", ignoreCase = true) ||
            bare.contains("otp", ignoreCase = true)
    }

    /** When true, AI toolbar and mic must be hidden and field text must not leave the device. */
    fun shouldHideAiAndMic(
        inputType: Int,
        autofillHints: List<String> = emptyList(),
        hintOrDescription: String? = null,
    ): Boolean = isSensitiveInput(inputType, autofillHints, hintOrDescription)
}
