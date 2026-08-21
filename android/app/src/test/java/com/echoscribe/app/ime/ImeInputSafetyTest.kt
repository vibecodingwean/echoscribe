package com.echoscribe.app.ime

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeInputSafetyTest {
    @Test
    fun passwordFieldsAreSensitive() {
        val password = ImeInputSafety.TYPE_CLASS_TEXT or ImeInputSafety.TYPE_TEXT_VARIATION_PASSWORD
        val visible = ImeInputSafety.TYPE_CLASS_TEXT or ImeInputSafety.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        val web = ImeInputSafety.TYPE_CLASS_TEXT or ImeInputSafety.TYPE_TEXT_VARIATION_WEB_PASSWORD
        val numberPassword = ImeInputSafety.TYPE_CLASS_NUMBER or ImeInputSafety.TYPE_NUMBER_VARIATION_PASSWORD

        assertTrue(ImeInputSafety.shouldHideAiAndMic(password))
        assertTrue(ImeInputSafety.shouldHideAiAndMic(visible))
        assertTrue(ImeInputSafety.shouldHideAiAndMic(web))
        assertTrue(ImeInputSafety.shouldHideAiAndMic(numberPassword))
    }

    @Test
    fun phoneAndPaymentHintsAreSensitive() {
        assertTrue(ImeInputSafety.shouldHideAiAndMic(ImeInputSafety.TYPE_CLASS_PHONE))
        assertTrue(
            ImeInputSafety.shouldHideAiAndMic(
                inputType = ImeInputSafety.TYPE_CLASS_TEXT,
                autofillHints = listOf("creditCardNumber"),
            ),
        )
        assertTrue(
            ImeInputSafety.shouldHideAiAndMic(
                inputType = ImeInputSafety.TYPE_CLASS_TEXT,
                hintOrDescription = "PIN eingeben",
            ),
        )
    }

    @Test
    fun imeIdShortAndFullFormsMatch() {
        assertTrue(ImeIds.matches("com.echoscribe.app", "com.echoscribe.app/.ime.EchoScribeImeService"))
        assertTrue(
            ImeIds.matches(
                "com.echoscribe.app",
                "com.echoscribe.app/com.echoscribe.app.ime.EchoScribeImeService",
            ),
        )
        assertFalse(ImeIds.matches("com.echoscribe.app", "com.google.android.inputmethod.latin/.LatinIME"))
    }

    @Test
    fun normalTextIsSafe() {
        assertFalse(ImeInputSafety.shouldHideAiAndMic(ImeInputSafety.TYPE_CLASS_TEXT))
        assertFalse(
            ImeInputSafety.shouldHideAiAndMic(
                inputType = ImeInputSafety.TYPE_CLASS_TEXT,
                autofillHints = listOf("username"),
                hintOrDescription = "Nachricht",
            ),
        )
    }
}
