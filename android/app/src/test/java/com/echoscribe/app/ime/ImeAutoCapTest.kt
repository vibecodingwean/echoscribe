package com.echoscribe.app.ime

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeAutoCapTest {
    @Test
    fun emptyOrWhitespaceArmsCapital() {
        assertTrue(ImeAutoCap.shouldCapitalize(""))
        assertTrue(ImeAutoCap.shouldCapitalize("   "))
        assertTrue(ImeAutoCap.shouldCapitalize("\n"))
    }

    @Test
    fun sentenceEndArmsCapitalIncludingAfterDeletingFirstLetter() {
        assertTrue(ImeAutoCap.shouldCapitalize("Hallo. "))
        assertTrue(ImeAutoCap.shouldCapitalize("Hallo."))
        assertTrue(ImeAutoCap.shouldCapitalize("Hallo!"))
        assertTrue(ImeAutoCap.shouldCapitalize("Hallo?\n"))
        assertTrue(ImeAutoCap.shouldCapitalize("Ok.\n\n"))
    }

    @Test
    fun midWordOrMidSentenceStaysLowercase() {
        assertFalse(ImeAutoCap.shouldCapitalize("H"))
        assertFalse(ImeAutoCap.shouldCapitalize("Hallo"))
        assertFalse(ImeAutoCap.shouldCapitalize("Hallo "))
        assertFalse(ImeAutoCap.shouldCapitalize("Hallo, "))
    }
}
